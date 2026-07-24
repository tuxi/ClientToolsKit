import ClientToolProtocol
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Renders PDF pages to images so image-only PDFs can be analyzed by OCR tools.
public struct RenderPDFPagesTool: ClientTool {
    public let name = "render_pdf_pages"
    public let description = """
将 workspace 内 PDF 的指定页渲染为 PNG 或 JPEG，并返回可继续传给 analyze_local_image 的图片路径。
页码从 1 开始；默认渲染全部页面。scale 控制相对 PDF 点尺寸的缩放倍率，默认 2，最大 4。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内 PDF 的相对路径")
                ]),
                "start_page": .object([
                    "type": .string("integer"),
                    "description": .string("起始页码（从 1 开始），默认 1"),
                    "minimum": .integer(1),
                    "default": .integer(1)
                ]),
                "end_page": .object([
                    "type": .string("integer"),
                    "description": .string("结束页码（含），默认最后一页"),
                    "minimum": .integer(1)
                ]),
                "scale": .object([
                    "type": .string("number"),
                    "description": .string("渲染倍率，范围 0.5 到 4，默认 2"),
                    "minimum": .number(0.5),
                    "maximum": .number(4),
                    "default": .number(2)
                ]),
                "format": .object([
                    "type": .string("string"),
                    "description": .string("输出格式，默认 png"),
                    "enum": .array([.string("png"), .string("jpeg")]),
                    "default": .string("png")
                ]),
                "output_directory": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的输出目录；默认 renders/<PDF 文件名>")
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
            throw RenderPDFPagesError.invalidArguments("Missing required string parameter: path")
        }

        let workspace = try ToolWorkspace(context: context)
        let pdfURL = try workspace.resolve(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw RenderPDFPagesError.fileNotFound(relativePath)
        }
        guard let document = PDFDocument(url: pdfURL) else {
            throw RenderPDFPagesError.invalidPDF(relativePath)
        }
        guard !document.isLocked else {
            throw RenderPDFPagesError.lockedPDF(relativePath)
        }
        guard document.pageCount > 0 else {
            throw RenderPDFPagesError.emptyPDF(relativePath)
        }

        let startPage = try Self.integer(values["start_page"], name: "start_page", defaultValue: 1)
        let endPage = try Self.integer(values["end_page"], name: "end_page", defaultValue: document.pageCount)
        guard startPage >= 1, endPage >= startPage, endPage <= document.pageCount else {
            throw RenderPDFPagesError.invalidPageRange(start: startPage, end: endPage, pageCount: document.pageCount)
        }

        let scale = try Self.number(values["scale"], name: "scale", defaultValue: 2)
        guard (0.5...4).contains(scale) else {
            throw RenderPDFPagesError.invalidArguments("scale must be between 0.5 and 4")
        }
        let format = try OutputFormat(argument: values["format"])
        let defaultDirectory = "renders/\(pdfURL.deletingPathExtension().lastPathComponent)"
        let outputDirectory: String
        if case .string(let requestedDirectory) = values["output_directory"] {
            outputDirectory = requestedDirectory
        } else {
            outputDirectory = defaultDirectory
        }
        let directoryURL = try workspace.resolve(relativePath: outputDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var renderedPages: [RenderedPDFPage] = []
        var assets: [AgentAssetRef] = []
        for pageNumber in startPage...endPage {
            guard let page = document.page(at: pageNumber - 1) else {
                throw RenderPDFPagesError.pageUnavailable(pageNumber)
            }
            let bounds = page.bounds(for: .mediaBox)
            let width = max(1, Int(ceil(abs(bounds.width) * scale)))
            let height = max(1, Int(ceil(abs(bounds.height) * scale)))
            guard width <= 16_384, height <= 16_384 else {
                throw RenderPDFPagesError.pageTooLarge(page: pageNumber, width: width, height: height)
            }

            let fileName = String(format: "page-%04d.%@", pageNumber, format.fileExtension)
            let outputPath = "\(outputDirectory)/\(fileName)"
            let outputURL = try workspace.resolve(relativePath: outputPath, createParentDirectory: true)
            try Self.render(
                page: page,
                bounds: bounds,
                width: width,
                height: height,
                scale: scale,
                format: format,
                outputURL: outputURL
            )
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            renderedPages.append(RenderedPDFPage(
                pageNumber: pageNumber,
                relativePath: outputPath,
                width: width,
                height: height,
                bytes: bytes,
                mimeType: format.mimeType
            ))
            assets.append(AgentAssetRef(
                id: "\(context.callID)-pdf-page-\(pageNumber)",
                kind: "image",
                displayName: fileName,
                workspaceID: context.workspaceID,
                workspaceRelativePath: outputPath,
                absolutePath: outputURL.path,
                mimeType: format.mimeType,
                sourceTurnID: context.turnID,
                sourceCallID: context.callID,
                metadata: ["page_number": .integer(pageNumber)]
            ))
        }

        return try ToolResultEncoder.executionResult(
            RenderPDFPagesResult(
                success: true,
                sourcePath: relativePath,
                pageCount: document.pageCount,
                outputDirectory: outputDirectory,
                pages: renderedPages
            ),
            assets: assets
        )
    }

    private static func render(
        page: PDFPage,
        bounds: CGRect,
        width: Int,
        height: Int,
        scale: Double,
        format: OutputFormat,
        outputURL: URL
    ) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderPDFPagesError.renderFailed
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                format.type.identifier as CFString,
                1,
                nil
              ) else {
            throw RenderPDFPagesError.renderFailed
        }
        let properties: CFDictionary?
        if format == .jpeg {
            properties = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        } else {
            properties = nil
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw RenderPDFPagesError.renderFailed
        }
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
        default: throw RenderPDFPagesError.invalidArguments("\(name) must be an integer")
        }
    }

    private static func number(
        _ value: JSONValue?,
        name: String,
        defaultValue: Double
    ) throws -> Double {
        guard let value else { return defaultValue }
        switch value {
        case .integer(let number): return Double(number)
        case .number(let number): return number
        default: throw RenderPDFPagesError.invalidArguments("\(name) must be a number")
        }
    }
}

private enum OutputFormat: String {
    case png
    case jpeg

    init(argument: JSONValue?) throws {
        guard let argument else {
            self = .png
            return
        }
        guard case .string(let value) = argument, let format = Self(rawValue: value) else {
            throw RenderPDFPagesError.invalidArguments("format must be png or jpeg")
        }
        self = format
    }

    var fileExtension: String { rawValue }
    var mimeType: String { self == .png ? "image/png" : "image/jpeg" }
    var type: UTType { self == .png ? .png : .jpeg }
}

private struct RenderPDFPagesResult: Encodable {
    let success: Bool
    let sourcePath: String
    let pageCount: Int
    let outputDirectory: String
    let pages: [RenderedPDFPage]

    enum CodingKeys: String, CodingKey {
        case success, pages
        case sourcePath = "source_path"
        case pageCount = "page_count"
        case outputDirectory = "output_directory"
    }
}

private struct RenderedPDFPage: Encodable {
    let pageNumber: Int
    let relativePath: String
    let width: Int
    let height: Int
    let bytes: Int64
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case width, height, bytes
        case pageNumber = "page_number"
        case relativePath = "relative_path"
        case mimeType = "mime_type"
    }
}

public enum RenderPDFPagesError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case invalidPDF(String)
    case lockedPDF(String)
    case emptyPDF(String)
    case invalidPageRange(start: Int, end: Int, pageCount: Int)
    case pageUnavailable(Int)
    case pageTooLarge(page: Int, width: Int, height: Int)
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return "Invalid arguments: \(message)"
        case .fileNotFound(let path): return "PDF file was not found in the workspace: \(path)"
        case .invalidPDF(let path): return "The file is not a readable PDF: \(path)"
        case .lockedPDF(let path): return "The PDF is password-protected and cannot be rendered: \(path)"
        case .emptyPDF(let path): return "The PDF contains no pages: \(path)"
        case .invalidPageRange(let start, let end, let count):
            return "Invalid page range \(start)...\(end); this PDF has \(count) pages."
        case .pageUnavailable(let page): return "PDF page \(page) is unavailable."
        case .pageTooLarge(let page, let width, let height):
            return "Rendered PDF page \(page) would be too large: \(width)x\(height)."
        case .renderFailed: return "Failed to render the PDF page."
        }
    }
}
