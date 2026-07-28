import ClientToolProtocol
import Foundation
import PDFKit

/// Creates a PDF document from Markdown, HTML, or plain-text content.
///
/// Markdown is parsed with the system `AttributedString` parser (iOS 15+/macOS 12+)
/// and rendered through CoreText + CGPDFContext — no WebView or UI context required.
public struct CreatePDFTool: ClientTool {
    public let name = "create_pdf"
    public let description = """
从 Markdown、HTML 或纯文本创建排版精美的 PDF 文件。\
Agent 可将产出、分析报告、会议纪要直接生成为 PDF 保存在 workspace 中。

支持 A4、Letter、Legal 页面尺寸，自动分页并添加页码。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "content": .object([
                    "type": .string("string"),
                    "description": .string("要转换为 PDF 的 Markdown、HTML 或纯文本内容")
                ]),
                "format": .object([
                    "type": .string("string"),
                    "description": .string("内容格式"),
                    "enum": .array([.string("markdown"), .string("html"), .string("text")]),
                    "default": .string("markdown")
                ]),
                "output_path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的输出路径，默认 documents/<标题>.pdf")
                ]),
                "page_size": .object([
                    "type": .string("string"),
                    "description": .string("页面尺寸"),
                    "enum": .array([.string("a4"), .string("letter"), .string("legal")]),
                    "default": .string("a4")
                ]),
                "title": .object([
                    "type": .string("string"),
                    "description": .string("PDF 元数据标题和页眉文字")
                ]),
                "author": .object([
                    "type": .string("string"),
                    "description": .string("PDF 元数据作者")
                ]),
                "font_size": .object([
                    "type": .string("number"),
                    "description": .string("正文字号（仅纯文本/HTML 模式生效；Markdown 由系统自动排版），范围 6-72，默认 11"),
                    "minimum": .integer(6),
                    "maximum": .integer(72),
                    "default": .integer(11)
                ])
            ]),
            "required": .array([.string("content")])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args,
              case .string(let content) = values["content"] else {
            throw CreatePDFError.invalidArguments("Missing required string parameter: content")
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CreatePDFError.emptyContent
        }

        let format = try parseFormat(values["format"])
        let pageSize = try parsePageSize(values["page_size"])
        let title: String? = extractString(values["title"])
        let author: String? = extractString(values["author"])
        let fontSize = try parseFontSize(values["font_size"])

        // Determine output path
        let outputPath: String
        if case .string(let op) = values["output_path"] {
            outputPath = op
        } else {
            let safeTitle = (title ?? "output")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            outputPath = "documents/\(safeTitle).pdf"
        }

        // Build attributed string from content (never throws)
        let attributedString = buildAttributedString(
            content: content,
            format: format,
            fontSize: fontSize
        )

        // Render to PDF data
        var pdfData = try renderAttributedStringToPDF(
            attributedString: attributedString,
            pageSize: pageSize,
            headerTitle: title
        )

        // Apply PDF metadata (title, author) if provided
        if title != nil || author != nil {
            if let doc = PDFDocument(data: pdfData) {
                var attributes = doc.documentAttributes ?? [:]
                if let title = title {
                    attributes[PDFDocumentAttribute.titleAttribute] = title
                }
                if let author = author {
                    attributes[PDFDocumentAttribute.authorAttribute] = author
                }
                doc.documentAttributes = attributes
                if let updatedData = doc.dataRepresentation() {
                    pdfData = updatedData
                }
            }
        }

        // Write to workspace
        let workspace = try ToolWorkspace(context: context)
        let outputURL = try workspace.resolve(relativePath: outputPath, createParentDirectory: true)
        try pdfData.write(to: outputURL, options: .atomic)

        // Count pages by re-opening the rendered PDF
        guard let doc = PDFDocument(data: pdfData) else {
            throw CreatePDFError.renderFailed("Failed to open rendered PDF for verification.")
        }
        let pageCount = doc.pageCount

        let fileSize = Int64(pdfData.count)
        let fileName = (outputPath as NSString).lastPathComponent

        let result = CreatePDFResult(
            success: true,
            outputPath: outputPath,
            fileName: fileName,
            pageCount: pageCount,
            bytes: fileSize,
            mimeType: "application/pdf",
            format: format.rawValue,
            pageSize: pageSize.rawValue
        )
        // Intentionally no asset — avoid server-side PDF processing that may hang.
        return try ToolResultEncoder.executionResult(result)
    }

    // MARK: - Argument Parsing

    private func parseFormat(_ value: JSONValue?) throws -> ContentFormat {
        guard case .string(let f) = value else { return .markdown }
        guard let parsed = ContentFormat(rawValue: f) else {
            throw CreatePDFError.invalidArguments("format must be 'markdown', 'html', or 'text'")
        }
        return parsed
    }

    private func parsePageSize(_ value: JSONValue?) throws -> PageSize {
        guard case .string(let ps) = value else { return .a4 }
        guard let parsed = PageSize(rawValue: ps) else {
            throw CreatePDFError.invalidArguments("page_size must be 'a4', 'letter', or 'legal'")
        }
        return parsed
    }

    private func extractString(_ value: JSONValue?) -> String? {
        guard case .string(let s) = value, !s.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return s
    }

    private func parseFontSize(_ value: JSONValue?) throws -> CGFloat {
        guard let value else { return 11 }
        let size: CGFloat
        switch value {
        case .integer(let i): size = CGFloat(i)
        case .number(let d): size = CGFloat(d)
        default: throw CreatePDFError.invalidArguments("font_size must be a number")
        }
        guard (6...72).contains(size) else {
            throw CreatePDFError.invalidArguments("font_size must be between 6 and 72")
        }
        return size
    }

    // MARK: - Content → AttributedString

    private func buildAttributedString(
        content: String,
        format: ContentFormat,
        fontSize: CGFloat
    ) -> NSAttributedString {
        switch format {
        case .markdown:
            return parseMarkdown(content)
        case .html:
            return parseHTML(content, fontSize: fontSize)
        case .text:
            return makePlainText(content, fontSize: fontSize)
        }
    }

    private func parseMarkdown(_ content: String) -> NSAttributedString {
        // Never throw — fall back to plain text on any parsing failure.
        if let attrString = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return NSAttributedString(attrString)
        }
        return makePlainText(content, fontSize: 11)
    }

    private func parseHTML(_ content: String, fontSize: CGFloat) -> NSAttributedString {
        guard let data = content.data(using: .utf8) else {
            return makePlainText(content, fontSize: fontSize)
        }
        if let attrString = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) {
            return attrString
        }
        return makePlainText(content, fontSize: fontSize)
    }

    private func makePlainText(_ content: String, fontSize: CGFloat) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = fontSize * 0.4
        paragraphStyle.paragraphSpacing = fontSize * 0.8

        #if canImport(UIKit)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let color = UIColor.black
        #elseif canImport(AppKit)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let color = NSColor.black
        #endif

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        return NSAttributedString(string: content, attributes: attributes)
    }
}

// MARK: - Content Format

private enum ContentFormat: String {
    case markdown
    case html
    case text
}

// MARK: - Result

private struct CreatePDFResult: Encodable {
    let success: Bool
    let outputPath: String
    let fileName: String
    let pageCount: Int
    let bytes: Int64
    let mimeType: String
    let format: String
    let pageSize: String

    enum CodingKeys: String, CodingKey {
        case success, bytes, format
        case outputPath = "relative_path"
        case fileName = "file_name"
        case pageCount = "page_count"
        case mimeType = "mime_type"
        case pageSize = "page_size"
    }
}

// MARK: - Errors

public enum CreatePDFError: LocalizedError {
    case invalidArguments(String)
    case emptyContent
    case markdownParseFailed(String)
    case htmlParseFailed(String)
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .emptyContent:
            return "Content must not be empty."
        case .markdownParseFailed(let detail):
            return "Failed to parse Markdown content: \(detail)"
        case .htmlParseFailed(let detail):
            return "Failed to parse HTML content: \(detail)"
        case .renderFailed(let detail):
            return "Failed to render PDF: \(detail)"
        }
    }
}
