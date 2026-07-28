import ClientToolProtocol
import Foundation
import PDFKit

/// Extracts selected pages from a PDF and saves them as a new PDF in the workspace.
///
/// Accepts page ranges like `"1-5"`, `"1,3,5"`, or `"1-5,8,10-12"`. Page numbers
/// are 1-based, matching the convention used by `ReadPDFTool` and `RenderPDFPagesTool`.
public struct SplitPDFTool: ClientTool {
    public let name = "split_pdf"
    public let description = """
从 workspace 中 PDF 的指定页面提取为新 PDF 文件。页码从 1 开始，支持逗号分隔和范围格式\
（如 "1-5"、"1,3,5"、"1-5,8,10-12"）。来源文件保持不变。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内源 PDF 的相对路径")
                ]),
                "pages": .object([
                    "type": .string("string"),
                    "description": .string("要提取的页码范围，如 \"1-5\"、\"1,3,5\"、\"1-5,8,10-12\"")
                ]),
                "output_path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的输出路径，默认 documents/split.pdf")
                ])
            ]),
            "required": .array([.string("path"), .string("pages")])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args,
              case .string(let relativePath) = values["path"],
              case .string(let pagesArg) = values["pages"] else {
            throw SplitPDFError.invalidArguments(
                "Missing required parameters: path (string) and pages (string)"
            )
        }

        let outputPath: String
        if case .string(let op) = values["output_path"] {
            outputPath = op
        } else {
            outputPath = "documents/split.pdf"
        }

        let workspace = try ToolWorkspace(context: context)
        let sourceURL = try workspace.resolve(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SplitPDFError.fileNotFound(relativePath)
        }
        guard let sourceDoc = PDFDocument(url: sourceURL) else {
            throw SplitPDFError.invalidPDF(relativePath)
        }
        guard !sourceDoc.isLocked else {
            throw SplitPDFError.lockedPDF(relativePath)
        }
        let sourcePageCount = sourceDoc.pageCount
        guard sourcePageCount > 0 else {
            throw SplitPDFError.emptyPDF(relativePath)
        }

        // Parse page range (1-based)
        let pageNumbers1Based = try parsePageRange(pagesArg, pageCount: sourcePageCount)

        // Round-trip source through data to detach page ownership
        guard let sourceData = sourceDoc.dataRepresentation(),
              let detachedDoc = PDFDocument(data: sourceData) else {
            throw SplitPDFError.splitFailed("Failed to read source PDF data.")
        }

        // Build output document
        let outputDoc = PDFDocument()
        for pageNumber in pageNumbers1Based {
            guard let page = detachedDoc.page(at: pageNumber - 1) else {
                throw SplitPDFError.pageUnavailable(pageNumber)
            }
            outputDoc.insert(page, at: outputDoc.pageCount)
        }

        // Write output
        let outputURL = try workspace.resolve(relativePath: outputPath, createParentDirectory: true)
        guard let outputData = outputDoc.dataRepresentation() else {
            throw SplitPDFError.splitFailed("Failed to serialise output PDF.")
        }
        try outputData.write(to: outputURL, options: .atomic)

        let fileSize = Int64(outputData.count)

        let result = SplitPDFResult(
            success: true,
            sourcePath: relativePath,
            outputPath: outputPath,
            sourcePageCount: sourcePageCount,
            extractedPages: pageNumbers1Based,
            extractedPageCount: pageNumbers1Based.count,
            bytes: fileSize,
            mimeType: "application/pdf"
        )
        return try ToolResultEncoder.executionResult(result)
    }
}

// MARK: - Result

private struct SplitPDFResult: Encodable {
    let success: Bool
    let sourcePath: String
    let outputPath: String
    let sourcePageCount: Int
    let extractedPages: [Int]
    let extractedPageCount: Int
    let bytes: Int64
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case success, bytes
        case sourcePath = "source_path"
        case outputPath = "relative_path"
        case sourcePageCount = "source_page_count"
        case extractedPages = "extracted_pages"
        case extractedPageCount = "extracted_page_count"
        case mimeType = "mime_type"
    }
}

// MARK: - Errors

public enum SplitPDFError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case invalidPDF(String)
    case lockedPDF(String)
    case emptyPDF(String)
    case pageUnavailable(Int)
    case splitFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .fileNotFound(let path):
            return "PDF file was not found in the workspace: \(path)"
        case .invalidPDF(let path):
            return "The file is not a readable PDF: \(path)"
        case .lockedPDF(let path):
            return "The PDF is password-protected: \(path)"
        case .emptyPDF(let path):
            return "The PDF contains no pages: \(path)"
        case .pageUnavailable(let page):
            return "PDF page \(page) is unavailable."
        case .splitFailed(let detail):
            return "Failed to split PDF: \(detail)"
        }
    }
}
