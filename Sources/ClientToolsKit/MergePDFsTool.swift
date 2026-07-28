import ClientToolProtocol
import Foundation
import PDFKit

/// Merges multiple PDFs in the workspace into a single PDF.
///
/// Pages are inserted in the order the source paths appear. All source files
/// remain unchanged; the merged result is written to a new file.
public struct MergePDFsTool: ClientTool {
    public let name = "merge_pdfs"
    public let description = """
将当前 workspace 中的多个 PDF 合并为一个 PDF 文件。
来源文件保持不变，合并结果输出为新文件。页码按来源路径顺序编排。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "paths": .object([
                    "type": .string("array"),
                    "description": .string("workspace 内 PDF 文件的相对路径数组，按顺序合并"),
                    "items": .object([
                        "type": .string("string")
                    ])
                ]),
                "output_path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的输出路径，默认 documents/merged.pdf")
                ])
            ]),
            "required": .array([.string("paths")])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args,
              case .array(let pathValues) = values["paths"] else {
            throw MergePDFsError.invalidArguments("Missing required array parameter: paths")
        }
        let relativePaths: [String] = try pathValues.map { value in
            guard case .string(let path) = value else {
                throw MergePDFsError.invalidArguments("Each paths element must be a string")
            }
            return path
        }
        guard relativePaths.count >= 1 else {
            throw MergePDFsError.insufficientInputs
        }

        let outputPath: String
        if case .string(let op) = values["output_path"] {
            outputPath = op
        } else {
            outputPath = "documents/merged.pdf"
        }

        let workspace = try ToolWorkspace(context: context)

        // Open all source documents
        var sourceDocs: [(path: String, doc: PDFDocument)] = []
        for relativePath in relativePaths {
            let url = try workspace.resolve(relativePath: relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MergePDFsError.fileNotFound(relativePath)
            }
            guard let doc = PDFDocument(url: url) else {
                throw MergePDFsError.invalidPDF(relativePath)
            }
            guard !doc.isLocked else {
                throw MergePDFsError.lockedPDF(relativePath)
            }
            sourceDocs.append((relativePath, doc))
        }

        // Merge: copy pages from each source into a fresh document.
        // To reliably transfer pages across documents, we serialise each source
        // as data and re-open it — this avoids internal page-ownership issues.
        let merged = PDFDocument()
        var totalPages = 0

        for (path, sourceDoc) in sourceDocs {
            let pageCount = sourceDoc.pageCount
            guard pageCount > 0 else { continue }

            // Round-trip through data to disconnect pages from the source document.
            guard let sourceData = sourceDoc.dataRepresentation(),
                  let detachedDoc = PDFDocument(data: sourceData) else {
                throw MergePDFsError.mergeFailed("Failed to copy pages from \(path)")
            }

            for i in 0..<detachedDoc.pageCount {
                guard let page = detachedDoc.page(at: i) else { continue }
                merged.insert(page, at: merged.pageCount)
                totalPages += 1
            }
        }

        guard totalPages > 0 else {
            throw MergePDFsError.mergeFailed("All source documents are empty.")
        }

        // Write merged document
        let outputURL = try workspace.resolve(relativePath: outputPath, createParentDirectory: true)
        guard let mergedData = merged.dataRepresentation() else {
            throw MergePDFsError.mergeFailed("Failed to serialise merged PDF.")
        }
        try mergedData.write(to: outputURL, options: .atomic)

        let fileSize = Int64(mergedData.count)
        let totalSourcePages = sourceDocs.reduce(0) { $0 + $1.doc.pageCount }

        let result = MergePDFsResult(
            success: true,
            outputPath: outputPath,
            inputCount: sourceDocs.count,
            totalSourcePages: totalSourcePages,
            mergedPages: totalPages,
            bytes: fileSize,
            mimeType: "application/pdf"
        )
        return try ToolResultEncoder.executionResult(result)
    }
}

// MARK: - Result

private struct MergePDFsResult: Encodable {
    let success: Bool
    let outputPath: String
    let inputCount: Int
    let totalSourcePages: Int
    let mergedPages: Int
    let bytes: Int64
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case success, bytes
        case outputPath = "relative_path"
        case inputCount = "input_count"
        case totalSourcePages = "total_source_pages"
        case mergedPages = "merged_pages"
        case mimeType = "mime_type"
    }
}

// MARK: - Errors

public enum MergePDFsError: LocalizedError {
    case invalidArguments(String)
    case insufficientInputs
    case fileNotFound(String)
    case invalidPDF(String)
    case lockedPDF(String)
    case mergeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .insufficientInputs:
            return "At least one PDF path is required for merging."
        case .fileNotFound(let path):
            return "PDF file was not found in the workspace: \(path)"
        case .invalidPDF(let path):
            return "The file is not a readable PDF: \(path)"
        case .lockedPDF(let path):
            return "The PDF is password-protected: \(path)"
        case .mergeFailed(let detail):
            return "Failed to merge PDFs: \(detail)"
        }
    }
}
