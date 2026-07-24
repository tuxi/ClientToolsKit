import ClientToolProtocol
import Compression
import Foundation

/// Safely extracts standard ZIP archives without shelling out to platform tools.
///
/// The implementation supports stored and DEFLATE entries, rejects encryption,
/// ZIP64, symlinks and path traversal, and enforces entry-count and expanded-size
/// budgets before writing anything.
public struct ExtractArchiveTool: ClientTool {
    public let name = "extract_archive"
    public let description = """
安全解压 workspace 内的 ZIP 文件，支持 stored/DEFLATE。默认输出到 extracted/<压缩包名>。
会拒绝路径穿越、绝对路径、符号链接、加密 ZIP 和 ZIP64，并限制文件数量及解压后总大小，防止 ZIP bomb。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内 ZIP 文件的相对路径")
                ]),
                "output_directory": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的输出目录，默认 extracted/<压缩包名>")
                ]),
                "overwrite": .object([
                    "type": .string("boolean"),
                    "description": .string("输出目录已存在时是否替换，默认 false"),
                    "default": .bool(false)
                ]),
                "max_entries": .object([
                    "type": .string("integer"),
                    "description": .string("最大条目数，默认 1000，最大 10000"),
                    "minimum": .integer(1),
                    "maximum": .integer(10_000),
                    "default": .integer(1_000)
                ]),
                "max_uncompressed_bytes": .object([
                    "type": .string("integer"),
                    "description": .string("最大解压后总字节数，默认 200MB，最大 1GB"),
                    "minimum": .integer(1),
                    "maximum": .integer(1_000_000_000),
                    "default": .integer(200_000_000)
                ])
            ]),
            "required": .array([.string("path")])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args,
              case .string(let relativePath) = values["path"] else {
            throw ExtractArchiveError.invalidArguments("Missing required string parameter: path")
        }
        let maxEntries = try Self.integer(values["max_entries"], name: "max_entries", defaultValue: 1_000)
        let maxBytes = try Self.integer64(
            values["max_uncompressed_bytes"],
            name: "max_uncompressed_bytes",
            defaultValue: 200_000_000
        )
        guard (1...10_000).contains(maxEntries) else {
            throw ExtractArchiveError.invalidArguments("max_entries must be between 1 and 10000")
        }
        guard (1...1_000_000_000).contains(maxBytes) else {
            throw ExtractArchiveError.invalidArguments("max_uncompressed_bytes must be between 1 and 1000000000")
        }
        let overwrite: Bool
        if case .bool(let value) = values["overwrite"] {
            overwrite = value
        } else {
            overwrite = false
        }

        let workspace = try ToolWorkspace(context: context)
        let archiveURL = try workspace.resolve(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: archiveURL.path) else {
            throw ExtractArchiveError.fileNotFound(relativePath)
        }
        let outputDirectory: String
        if case .string(let requestedOutput) = values["output_directory"] {
            outputDirectory = requestedOutput
        } else {
            outputDirectory = "extracted/\(archiveURL.deletingPathExtension().lastPathComponent)"
        }
        let destinationURL = try workspace.resolve(relativePath: outputDirectory)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path), !overwrite {
            throw ExtractArchiveError.destinationExists(outputDirectory)
        }

        let reader = try ZIPReader(url: archiveURL)
        let entries = try reader.validatedEntries(maxEntries: maxEntries, maxBytes: maxBytes)
        try Task.checkCancellation()

        let temporaryName = ".extracting-\(UUID().uuidString)"
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(temporaryName, isDirectory: true)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        var shouldCleanTemporary = true
        defer {
            if shouldCleanTemporary {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        for entry in entries {
            try Task.checkCancellation()
            try reader.extract(entry, to: temporaryURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
        shouldCleanTemporary = false

        let files = entries.filter { !$0.isDirectory }
        let previewLimit = 200
        let payload = ExtractArchiveResult(
            success: true,
            sourcePath: relativePath,
            outputDirectory: outputDirectory,
            entryCount: entries.count,
            fileCount: files.count,
            uncompressedBytes: entries.reduce(0) { $0 + $1.uncompressedSize },
            extractedPaths: Array(files.prefix(previewLimit).map(\.path)),
            omittedPathCount: max(0, files.count - previewLimit)
        )
        let asset = AgentAssetRef(
            id: "\(context.callID)-extracted",
            kind: "directory",
            displayName: destinationURL.lastPathComponent,
            workspaceID: context.workspaceID,
            workspaceRelativePath: outputDirectory,
            absolutePath: destinationURL.path,
            sourceTurnID: context.turnID,
            sourceCallID: context.callID,
            metadata: [
                "entry_count": .integer(entries.count),
                "file_count": .integer(files.count)
            ]
        )
        return try ToolResultEncoder.executionResult(payload, assets: [asset])
    }

    private static func integer(
        _ value: JSONValue?,
        name: String,
        defaultValue: Int
    ) throws -> Int {
        guard let value else { return defaultValue }
        switch value {
        case .integer(let number): return number
        case .number(let number) where number.rounded() == number: return Int(number)
        default: throw ExtractArchiveError.invalidArguments("\(name) must be an integer")
        }
    }

    private static func integer64(
        _ value: JSONValue?,
        name: String,
        defaultValue: Int64
    ) throws -> Int64 {
        guard let value else { return defaultValue }
        switch value {
        case .integer(let number): return Int64(number)
        case .number(let number) where number.rounded() == number: return Int64(number)
        default: throw ExtractArchiveError.invalidArguments("\(name) must be an integer")
        }
    }
}

private struct ZIPEntry {
    let path: String
    let compressionMethod: UInt16
    let crc32: UInt32
    let compressedSize: Int
    let uncompressedSize: Int64
    let localHeaderOffset: Int
    let isDirectory: Bool
}

private struct ZIPReader {
    private static let endSignature: UInt32 = 0x0605_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let localSignature: UInt32 = 0x0403_4b50

    private let data: Data
    private let entries: [ZIPEntry]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: [.mappedIfSafe])
        entries = try Self.parseEntries(in: data)
    }

    func validatedEntries(maxEntries: Int, maxBytes: Int64) throws -> [ZIPEntry] {
        guard entries.count <= maxEntries else {
            throw ExtractArchiveError.tooManyEntries(actual: entries.count, maximum: maxEntries)
        }
        var total: Int64 = 0
        var seenPaths = Set<String>()
        for entry in entries {
            guard seenPaths.insert(entry.path).inserted else {
                throw ExtractArchiveError.duplicateEntry(entry.path)
            }
            let (next, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, next <= maxBytes else {
                throw ExtractArchiveError.expandedSizeLimitExceeded(maximum: maxBytes)
            }
            total = next
        }
        return entries
    }

    func extract(_ entry: ZIPEntry, to rootURL: URL) throws {
        let destination = rootURL.appendingPathComponent(entry.path).standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard destination.path.hasPrefix(rootPath + "/") else {
            throw ExtractArchiveError.unsafeEntryPath(entry.path)
        }
        if entry.isDirectory {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            return
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard Self.uint32(data, at: entry.localHeaderOffset) == Self.localSignature else {
            throw ExtractArchiveError.invalidZIP("Invalid local header for \(entry.path)")
        }
        let nameLength = Int(Self.uint16(data, at: entry.localHeaderOffset + 26))
        let extraLength = Int(Self.uint16(data, at: entry.localHeaderOffset + 28))
        let dataOffset = entry.localHeaderOffset + 30 + nameLength + extraLength
        guard dataOffset >= 0,
              entry.compressedSize >= 0,
              dataOffset <= data.count,
              entry.compressedSize <= data.count - dataOffset else {
            throw ExtractArchiveError.invalidZIP("Entry data is outside the archive: \(entry.path)")
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        let crc: UInt32
        switch entry.compressionMethod {
        case 0:
            crc = try writeStored(
                range: dataOffset..<(dataOffset + entry.compressedSize),
                expectedSize: entry.uncompressedSize,
                to: handle
            )
        case 8:
            crc = try writeDeflated(
                range: dataOffset..<(dataOffset + entry.compressedSize),
                expectedSize: entry.uncompressedSize,
                to: handle
            )
        default:
            throw ExtractArchiveError.unsupportedCompression(entry.compressionMethod, entry.path)
        }
        guard crc == entry.crc32 else {
            throw ExtractArchiveError.crcMismatch(entry.path)
        }
    }

    private func writeStored(
        range: Range<Int>,
        expectedSize: Int64,
        to handle: FileHandle
    ) throws -> UInt32 {
        guard Int64(range.count) == expectedSize else {
            throw ExtractArchiveError.invalidZIP("Stored entry size mismatch")
        }
        var crc = CRC32.initial
        var cursor = range.lowerBound
        let chunkSize = 64 * 1_024
        while cursor < range.upperBound {
            let end = min(cursor + chunkSize, range.upperBound)
            let chunk = data.subdata(in: cursor..<end)
            try handle.write(contentsOf: chunk)
            crc = CRC32.update(crc, with: chunk)
            cursor = end
        }
        return CRC32.finalize(crc)
    }

    private func writeDeflated(
        range: Range<Int>,
        expectedSize: Int64,
        to handle: FileHandle
    ) throws -> UInt32 {
        let initialPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { initialPointer.deallocate() }
        var stream = compression_stream(
            dst_ptr: initialPointer,
            dst_size: 0,
            src_ptr: UnsafePointer(initialPointer),
            src_size: 0,
            state: nil
        )
        let initialization = compression_stream_init(
            &stream,
            COMPRESSION_STREAM_DECODE,
            COMPRESSION_ZLIB
        )
        guard initialization != COMPRESSION_STATUS_ERROR else {
            throw ExtractArchiveError.decompressionFailed
        }
        defer { compression_stream_destroy(&stream) }

        var totalWritten: Int64 = 0
        var crc = CRC32.initial
        let outputSize = 64 * 1_024
        var output = [UInt8](repeating: 0, count: outputSize)
        try data.withUnsafeBytes { archiveBytes in
            guard let archiveBase = archiveBytes.bindMemory(to: UInt8.self).baseAddress else {
                throw ExtractArchiveError.decompressionFailed
            }
            try output.withUnsafeMutableBytes { outputBytes in
                guard let outputBase = outputBytes.bindMemory(to: UInt8.self).baseAddress else {
                    throw ExtractArchiveError.decompressionFailed
                }
                stream.src_ptr = archiveBase.advanced(by: range.lowerBound)
                stream.src_size = range.count
                repeat {
                    stream.dst_ptr = outputBase
                    stream.dst_size = outputSize
                    let status = compression_stream_process(
                        &stream,
                        Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                    )
                    guard status != COMPRESSION_STATUS_ERROR else {
                        throw ExtractArchiveError.decompressionFailed
                    }
                    let produced = outputSize - stream.dst_size
                    if produced > 0 {
                        totalWritten += Int64(produced)
                        guard totalWritten <= expectedSize else {
                            throw ExtractArchiveError.decompressionFailed
                        }
                        let chunk = Data(bytes: outputBase, count: produced)
                        try handle.write(contentsOf: chunk)
                        crc = CRC32.update(crc, with: chunk)
                    }
                    if status == COMPRESSION_STATUS_END { break }
                    guard produced > 0 || stream.src_size > 0 else {
                        throw ExtractArchiveError.decompressionFailed
                    }
                } while true
            }
        }
        guard totalWritten == expectedSize else {
            throw ExtractArchiveError.decompressionFailed
        }
        return CRC32.finalize(crc)
    }

    private static func parseEntries(in data: Data) throws -> [ZIPEntry] {
        guard data.count >= 22 else {
            throw ExtractArchiveError.invalidZIP("End of central directory was not found")
        }
        let searchStart = max(0, data.count - 65_557)
        var endOffset: Int?
        var cursor = data.count - 22
        while cursor >= searchStart {
            if uint32(data, at: cursor) == endSignature {
                endOffset = cursor
                break
            }
            cursor -= 1
        }
        guard let endOffset else {
            throw ExtractArchiveError.invalidZIP("End of central directory was not found")
        }
        guard uint16(data, at: endOffset + 4) == 0,
              uint16(data, at: endOffset + 6) == 0 else {
            throw ExtractArchiveError.invalidZIP("Multi-disk ZIP files are unsupported")
        }
        let entryCount = Int(uint16(data, at: endOffset + 10))
        let centralSize = uint32(data, at: endOffset + 12)
        let centralOffset = uint32(data, at: endOffset + 16)
        guard entryCount != Int(UInt16.max),
              centralSize != UInt32.max,
              centralOffset != UInt32.max else {
            throw ExtractArchiveError.zip64Unsupported
        }
        var entries: [ZIPEntry] = []
        entries.reserveCapacity(entryCount)
        cursor = Int(centralOffset)
        for _ in 0..<entryCount {
            guard cursor >= 0, cursor + 46 <= data.count,
                  uint32(data, at: cursor) == centralSignature else {
                throw ExtractArchiveError.invalidZIP("Invalid central directory")
            }
            let flags = uint16(data, at: cursor + 8)
            guard flags & 0x0001 == 0 else {
                throw ExtractArchiveError.encryptedZIPUnsupported
            }
            let method = uint16(data, at: cursor + 10)
            let crc = uint32(data, at: cursor + 16)
            let compressedSize = uint32(data, at: cursor + 20)
            let uncompressedSize = uint32(data, at: cursor + 24)
            let nameLength = Int(uint16(data, at: cursor + 28))
            let extraLength = Int(uint16(data, at: cursor + 30))
            let commentLength = Int(uint16(data, at: cursor + 32))
            let externalAttributes = uint32(data, at: cursor + 38)
            let localOffset = uint32(data, at: cursor + 42)
            guard compressedSize != UInt32.max,
                  uncompressedSize != UInt32.max,
                  localOffset != UInt32.max else {
                throw ExtractArchiveError.zip64Unsupported
            }
            let nameStart = cursor + 46
            let next = nameStart + nameLength + extraLength + commentLength
            guard nameLength > 0, next <= data.count else {
                throw ExtractArchiveError.invalidZIP("Invalid central directory entry length")
            }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            guard let rawName = String(data: nameData, encoding: .utf8) else {
                throw ExtractArchiveError.invalidZIP("Entry name is not UTF-8")
            }
            let path = try safePath(rawName)
            let unixType = (externalAttributes >> 16) & 0xF000
            guard unixType != 0xA000 else {
                throw ExtractArchiveError.symlinkUnsupported(path)
            }
            entries.append(ZIPEntry(
                path: path,
                compressionMethod: method,
                crc32: crc,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int64(uncompressedSize),
                localHeaderOffset: Int(localOffset),
                isDirectory: rawName.hasSuffix("/")
            ))
            cursor = next
        }
        return entries
    }

    private static func safePath(_ rawPath: String) throws -> String {
        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"), !normalized.contains("\0") else {
            throw ExtractArchiveError.unsafeEntryPath(rawPath)
        }
        var components = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if components.last == "" { components.removeLast() }
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              !(components.first?.contains(":") ?? false) else {
            throw ExtractArchiveError.unsafeEntryPath(rawPath)
        }
        return components.joined(separator: "/")
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private enum CRC32 {
    static let initial = UInt32.max

    static func update(_ crc: UInt32, with data: Data) -> UInt32 {
        data.reduce(crc) { current, byte in
            var value = current ^ UInt32(byte)
            for _ in 0..<8 {
                value = (value >> 1) ^ (value & 1 == 1 ? 0xEDB8_8320 : 0)
            }
            return value
        }
    }

    static func finalize(_ crc: UInt32) -> UInt32 {
        crc ^ UInt32.max
    }
}

private struct ExtractArchiveResult: Encodable {
    let success: Bool
    let sourcePath: String
    let outputDirectory: String
    let entryCount: Int
    let fileCount: Int
    let uncompressedBytes: Int64
    let extractedPaths: [String]
    let omittedPathCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case sourcePath = "source_path"
        case outputDirectory = "output_directory"
        case entryCount = "entry_count"
        case fileCount = "file_count"
        case uncompressedBytes = "uncompressed_bytes"
        case extractedPaths = "extracted_paths"
        case omittedPathCount = "omitted_path_count"
    }
}

public enum ExtractArchiveError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case destinationExists(String)
    case invalidZIP(String)
    case zip64Unsupported
    case encryptedZIPUnsupported
    case unsafeEntryPath(String)
    case symlinkUnsupported(String)
    case duplicateEntry(String)
    case tooManyEntries(actual: Int, maximum: Int)
    case expandedSizeLimitExceeded(maximum: Int64)
    case unsupportedCompression(UInt16, String)
    case decompressionFailed
    case crcMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return "Invalid arguments: \(message)"
        case .fileNotFound(let path): return "Archive was not found in the workspace: \(path)"
        case .destinationExists(let path): return "Extraction destination already exists: \(path)"
        case .invalidZIP(let message): return "Invalid ZIP archive: \(message)"
        case .zip64Unsupported: return "ZIP64 archives are not supported."
        case .encryptedZIPUnsupported: return "Encrypted ZIP archives are not supported."
        case .unsafeEntryPath(let path): return "ZIP contains an unsafe entry path: \(path)"
        case .symlinkUnsupported(let path): return "ZIP symbolic links are not allowed: \(path)"
        case .duplicateEntry(let path): return "ZIP contains a duplicate entry path: \(path)"
        case .tooManyEntries(let actual, let maximum):
            return "ZIP contains \(actual) entries, exceeding the limit of \(maximum)."
        case .expandedSizeLimitExceeded(let maximum):
            return "ZIP expanded size exceeds the limit of \(maximum) bytes."
        case .unsupportedCompression(let method, let path):
            return "ZIP entry \(path) uses unsupported compression method \(method)."
        case .decompressionFailed: return "ZIP DEFLATE decompression failed."
        case .crcMismatch(let path): return "ZIP entry failed its CRC integrity check: \(path)"
        }
    }
}
