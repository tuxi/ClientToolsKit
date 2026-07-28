import ClientToolProtocol
import Foundation
import PDFKit

/// Extracts selectable text and document metadata from a PDF in the shared workspace.
///
/// Scanned/image-only PDFs do not contain selectable text; run an OCR-capable tool on
/// rendered pages when text extraction returns empty strings.
public struct ReadPDFTool: ClientTool {
    public let name = "read_pdf"
    public let description = "读取 workspace 内 PDF 的元数据和可选择文本。支持用 start_page/end_page 读取页码范围；max_characters 限制返回文本，默认 20,000 字符。扫描件或图片型 PDF 不含可提取文字，需另行 OCR。"

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
                    "description": .string("起始页码（从 1 开始），默认第 1 页"),
                    "minimum": .integer(1),
                    "default": .integer(1)
                ]),
                "end_page": .object([
                    "type": .string("integer"),
                    "description": .string("结束页码（含），默认最后一页"),
                    "minimum": .integer(1)
                ]),
                "max_characters": .object([
                    "type": .string("integer"),
                    "description": .string("最多返回的文本字符数，范围 1 到 100,000，默认 20,000"),
                    "minimum": .integer(1),
                    "maximum": .integer(100_000),
                    "default": .integer(20_000)
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
            throw ReadPDFToolError.invalidArguments("Missing required string parameter: path")
        }

        let workspace = try ToolWorkspace(context: context)
        let pdfURL = try workspace.resolve(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw ReadPDFToolError.fileNotFound(relativePath)
        }
        guard let document = PDFDocument(url: pdfURL) else {
            throw ReadPDFToolError.invalidPDF(relativePath)
        }
        guard !document.isLocked else {
            throw ReadPDFToolError.lockedPDF(relativePath)
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw ReadPDFToolError.emptyPDF(relativePath)
        }

        let startPage = try integerArgument(values["start_page"], named: "start_page", defaultValue: 1)
        let endPage = try integerArgument(values["end_page"], named: "end_page", defaultValue: max(1, min(pageCount, 2))) // 默认一次最多只能读2页
        let maxCharacters = try integerArgument(values["max_characters"], named: "max_characters", defaultValue: 20_000)

        guard startPage >= 1, endPage >= startPage, endPage <= pageCount else {
            throw ReadPDFToolError.invalidPageRange(start: startPage, end: endPage, pageCount: pageCount)
        }
        guard (1...100_000).contains(maxCharacters) else {
            throw ReadPDFToolError.invalidArguments("max_characters must be between 1 and 100000")
        }

        var remainingCharacters = maxCharacters
        var pages: [PDFPageText] = []
        var textParts: [String] = []
        var didTruncate = false

        for pageNumber in startPage...endPage {
            let extracted = document.page(at: pageNumber - 1)?.string ?? ""
            let text = String(extracted.prefix(remainingCharacters))
            if text.count < extracted.count {
                didTruncate = true
            }
            pages.append(PDFPageText(pageNumber: pageNumber, text: text))
            if !text.isEmpty {
                textParts.append(text)
                remainingCharacters -= text.count
            }
            if remainingCharacters == 0 { break }
        }

        let text = textParts.joined(separator: "\n\n")
        if !didTruncate,
           remainingCharacters == 0,
           let lastReadPage = pages.last?.pageNumber,
           lastReadPage < endPage {
            didTruncate = ((lastReadPage + 1)...endPage).contains {
                !(document.page(at: $0 - 1)?.string ?? "").isEmpty
            }
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: pdfURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let metadata = document.documentAttributes ?? [:]

        let result = PDFReadResult(
            success: true,
            relativePath: relativePath,
            pageCount: pageCount,
            requestedStartPage: startPage,
            requestedEndPage: endPage,
            pages: pages,
            text: text,
            truncated: didTruncate,
            bytes: bytes,
            title: metadata[PDFDocumentAttribute.titleAttribute] as? String,
            author: metadata[PDFDocumentAttribute.authorAttribute] as? String,
            subject: metadata[PDFDocumentAttribute.subjectAttribute] as? String,
            creator: metadata[PDFDocumentAttribute.creatorAttribute] as? String
        )
        return try ToolResultEncoder.executionResult(result)
    }

    private func integerArgument(
        _ value: JSONValue?,
        named name: String,
        defaultValue: Int
    ) throws -> Int {
        guard let value else { return defaultValue }
        switch value {
        case .integer(let integer): return integer
        case .number(let number) where number.rounded() == number: return Int(number)
        default: throw ReadPDFToolError.invalidArguments("\(name) must be an integer")
        }
    }
}

private struct PDFReadResult: Encodable {
    let success: Bool
    let relativePath: String
    let pageCount: Int
    let requestedStartPage: Int
    let requestedEndPage: Int
    let pages: [PDFPageText]
    let text: String
    let truncated: Bool
    let bytes: Int64
    let title: String?
    let author: String?
    let subject: String?
    let creator: String?

    enum CodingKeys: String, CodingKey {
        case success, pages, text, truncated, bytes, title, author, subject, creator
        case relativePath = "relative_path"
        case pageCount = "page_count"
        case requestedStartPage = "requested_start_page"
        case requestedEndPage = "requested_end_page"
    }
}

private struct PDFPageText: Encodable {
    let pageNumber: Int
    let text: String

    enum CodingKeys: String, CodingKey {
        case text
        case pageNumber = "page_number"
    }
}

public enum ReadPDFToolError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case invalidPDF(String)
    case lockedPDF(String)
    case emptyPDF(String)
    case invalidPageRange(start: Int, end: Int, pageCount: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return "Invalid arguments: \(message)"
        case .fileNotFound(let path): return "PDF file was not found in the workspace: \(path)"
        case .invalidPDF(let path): return "The file is not a readable PDF: \(path)"
        case .lockedPDF(let path): return "The PDF is password-protected and cannot be read: \(path)"
        case .emptyPDF(let path): return "The PDF contains no pages: \(path)"
        case .invalidPageRange(let start, let end, let pageCount):
            return "Invalid page range \(start)...\(end); this PDF has \(pageCount) pages."
        }
    }
}
