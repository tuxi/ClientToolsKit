#if os(iOS)

import ClientToolProtocol
import Foundation
import PDFKit
import UIKit
@preconcurrency import VisionKit

/// Presents Apple's document camera and saves the corrected pages to the workspace.
public struct ScanDocumentTool: ClientTool {
    public let name = "scan_document"
    public let description = """
展示系统文档扫描界面，自动检测纸张边缘、透视校正并扫描多页文档。可输出 PDF、JPEG 页面或两者。
max_pages 限制最终保存的页数；VisionKit 系统界面不会在达到该页数时自动结束，请在扫描目标页数后点击完成。
如果用户取消扫描，会返回 cancelled=true 且 should_retry=false，不要自动再次调用本工具。
需要当前 scene 的 ClientToolPresentationCoordinator，且宿主 App 必须配置 NSCameraUsageDescription。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "output": .object([
                    "type": .string("string"),
                    "description": .string("输出 pdf、images 或 both，默认 pdf"),
                    "enum": .array([.string("pdf"), .string("images"), .string("both")]),
                    "default": .string("pdf")
                ]),
                "save_path": .object([
                    "type": .string("string"),
                    "description": .string("PDF 的 workspace 相对路径，默认 scans/scan-<时间>.pdf")
                ]),
                "images_directory": .object([
                    "type": .string("string"),
                    "description": .string("JPEG 页面的 workspace 相对目录，默认 scans/scan-<时间>-pages")
                ]),
                "jpeg_quality": .object([
                    "type": .string("number"),
                    "description": .string("JPEG 质量，范围 0.5 到 1，默认 0.9"),
                    "minimum": .number(0.5),
                    "maximum": .number(1),
                    "default": .number(0.9)
                ]),
                "max_pages": .object([
                    "type": .string("integer"),
                    "description": .string("最多保存的页数，默认 50，最大 200。系统扫描界面不会达到此数后自动关闭；多扫描的页面会被丢弃"),
                    "minimum": .integer(1),
                    "maximum": .integer(200),
                    "default": .integer(50)
                ])
            ]),
            "required": .array([])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        let turnCacheKey = Self.turnCacheKey(context: context)
        if let turnCacheKey,
           let cached = await DocumentScanTurnCache.shared.result(for: turnCacheKey) {
            return cached
        }

        let values: [String: JSONValue]
        if case .object(let object) = args {
            values = object
        } else {
            values = [:]
        }
        let output = try DocumentScanOutput(argument: values["output"])
        let jpegQuality = try Self.number(
            values["jpeg_quality"],
            name: "jpeg_quality",
            defaultValue: 0.9
        )
        guard (0.5...1).contains(jpegQuality) else {
            throw ScanDocumentError.invalidArguments("jpeg_quality must be between 0.5 and 1")
        }
        let maxPages = try Self.integer(
            values["max_pages"],
            name: "max_pages",
            defaultValue: 50
        )
        guard (1...200).contains(maxPages) else {
            throw ScanDocumentError.invalidArguments("max_pages must be between 1 and 200")
        }
        guard let usageDescription = Bundle.main.object(
            forInfoDictionaryKey: "NSCameraUsageDescription"
        ) as? String,
              !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScanDocumentError.missingUsageDescription
        }
        guard let presentationCoordinator = context.presentationCoordinator else {
            throw ScanDocumentError.presentationUnavailable
        }

        let timestamp = Self.timestamp()
        let pdfPath: String
        if case .string(let requestedPath) = values["save_path"] {
            pdfPath = requestedPath
        } else {
            pdfPath = "scans/scan-\(timestamp).pdf"
        }
        guard pdfPath.lowercased().hasSuffix(".pdf") else {
            throw ScanDocumentError.invalidArguments("save_path must use the .pdf extension")
        }
        let imagesDirectory: String
        if case .string(let requestedDirectory) = values["images_directory"] {
            imagesDirectory = requestedDirectory
        } else {
            imagesDirectory = "scans/scan-\(timestamp)-pages"
        }

        let captured: CapturedDocument
        do {
            captured = try await DocumentCameraRunner.capture(
                using: presentationCoordinator,
                jpegQuality: jpegQuality,
                createPDF: output.includesPDF,
                maxPages: maxPages
            )
        } catch ScanDocumentError.cancelled {
            let result = try ToolResultEncoder.executionResult(
                CancelledDocumentScanResult(
                    success: false,
                    cancelled: true,
                    shouldRetry: false,
                    message: "The user cancelled document scanning. Do not call scan_document again unless the user explicitly asks."
                ),
                assets: []
            )
            if let turnCacheKey {
                await DocumentScanTurnCache.shared.store(result, for: turnCacheKey)
            }
            return result
        }

        let workspace = try ToolWorkspace(context: context)
        var assets: [AgentAssetRef] = []
        var pageResults: [ScannedDocumentPageResult] = []
        if output.includesImages {
            for (index, page) in captured.pages.enumerated() {
                let pageNumber = index + 1
                let relativePath = "\(imagesDirectory)/\(String(format: "page-%04d.jpg", pageNumber))"
                let url = try workspace.resolve(
                    relativePath: relativePath,
                    createParentDirectory: true
                )
                try page.jpegData.write(to: url, options: .atomic)
                pageResults.append(ScannedDocumentPageResult(
                    pageNumber: pageNumber,
                    relativePath: relativePath,
                    width: page.width,
                    height: page.height,
                    bytes: Int64(page.jpegData.count)
                ))
                assets.append(AgentAssetRef(
                    id: "\(context.callID)-scan-page-\(pageNumber)",
                    kind: "image",
                    displayName: url.lastPathComponent,
                    workspaceID: context.workspaceID,
                    workspaceRelativePath: relativePath,
                    absolutePath: url.path,
                    mimeType: "image/jpeg",
                    sourceTurnID: context.turnID,
                    sourceCallID: context.callID,
                    metadata: ["page_number": .integer(pageNumber)]
                ))
            }
        }

        var pdfResult: ScannedDocumentPDFResult?
        if output.includesPDF {
            guard let pdfData = captured.pdfData else {
                throw ScanDocumentError.pdfEncodingFailed
            }
            let url = try workspace.resolve(relativePath: pdfPath, createParentDirectory: true)
            try pdfData.write(to: url, options: .atomic)
            pdfResult = ScannedDocumentPDFResult(
                relativePath: pdfPath,
                bytes: Int64(pdfData.count)
            )
            assets.insert(AgentAssetRef(
                id: "\(context.callID)-scan-pdf",
                kind: "file",
                displayName: url.lastPathComponent,
                workspaceID: context.workspaceID,
                workspaceRelativePath: pdfPath,
                absolutePath: url.path,
                mimeType: "application/pdf",
                sourceTurnID: context.turnID,
                sourceCallID: context.callID,
                metadata: ["page_count": .integer(captured.pages.count)]
            ), at: 0)
        }

        let result = try ToolResultEncoder.executionResult(
            ScannedDocumentResult(
                success: true,
                pageCount: captured.pages.count,
                capturedPageCount: captured.capturedPageCount,
                discardedPageCount: captured.capturedPageCount - captured.pages.count,
                truncated: captured.capturedPageCount > captured.pages.count,
                message: captured.capturedPageCount > captured.pages.count
                    ? "Document scanning completed successfully. Saved the first \(captured.pages.count) pages and discarded \(captured.capturedPageCount - captured.pages.count) extra pages. max_pages is a limit, not a required page count. Do not call scan_document again in this turn."
                    : "Document scanning completed successfully and the PDF/images are already saved. max_pages is a limit, not a required page count. Do not call scan_document again in this turn.",
                pdf: pdfResult,
                pages: pageResults
            ),
            assets: assets
        )
        if let turnCacheKey {
            await DocumentScanTurnCache.shared.store(result, for: turnCacheKey)
        }
        return result
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func turnCacheKey(
        context: ClientToolExecutionContext
    ) -> String? {
        guard !context.sessionID.isEmpty, !context.turnID.isEmpty else { return nil }
        return context.sessionID + "\u{0}" + context.turnID
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
        default: throw ScanDocumentError.invalidArguments("\(name) must be a number")
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
        default: throw ScanDocumentError.invalidArguments("\(name) must be an integer")
        }
    }
}

@MainActor
private enum DocumentCameraRunner {
    static func capture(
        using presentationCoordinator: any ClientToolPresentationCoordinator,
        jpegQuality: Double,
        createPDF: Bool,
        maxPages: Int
    ) async throws -> CapturedDocument {
        guard VNDocumentCameraViewController.isSupported else {
            throw ScanDocumentError.scannerUnavailable
        }
        let controller = VNDocumentCameraViewController()
        let delegate = DocumentCameraDelegate(
            jpegQuality: jpegQuality,
            createPDF: createPDF,
            maxPages: maxPages
        )
        controller.delegate = delegate
        try await presentationCoordinator.present(controller, animated: true)

        let captured: CapturedDocument
        do {
            captured = try await withTaskCancellationHandler {
                try await delegate.waitForResult()
            } onCancel: {
                Task { @MainActor in
                    delegate.cancel()
                }
            }
        } catch {
            await presentationCoordinator.dismiss(controller, animated: true)
            throw error
        }
        await presentationCoordinator.dismiss(controller, animated: true)
        return captured
    }
}

@MainActor
private final class DocumentCameraDelegate:
    NSObject,
    @MainActor VNDocumentCameraViewControllerDelegate
{
    private let jpegQuality: Double
    private let createPDF: Bool
    private let maxPages: Int
    private var continuation: CheckedContinuation<CapturedDocument, Error>?
    private var result: Result<CapturedDocument, Error>?

    init(jpegQuality: Double, createPDF: Bool, maxPages: Int) {
        self.jpegQuality = jpegQuality
        self.createPDF = createPDF
        self.maxPages = maxPages
    }

    func waitForResult() async throws -> CapturedDocument {
        if let result {
            self.result = nil
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        do {
            finish(.success(try capturedDocument(from: scan)))
        } catch {
            finish(.failure(error))
        }
    }

    func documentCameraViewControllerDidCancel(
        _ controller: VNDocumentCameraViewController
    ) {
        finish(.failure(ScanDocumentError.cancelled))
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        finish(.failure(ScanDocumentError.captureFailed(error.localizedDescription)))
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func capturedDocument(
        from scan: VNDocumentCameraScan
    ) throws -> CapturedDocument {
        let savedPageCount = min(scan.pageCount, maxPages)
        var pages: [CapturedDocumentPage] = []
        pages.reserveCapacity(savedPageCount)
        let pdfDocument = createPDF ? PDFDocument() : nil
        for index in 0..<savedPageCount {
            let image = scan.imageOfPage(at: index)
            guard let jpegData = image.jpegData(compressionQuality: jpegQuality) else {
                throw ScanDocumentError.imageEncodingFailed(index + 1)
            }
            pages.append(CapturedDocumentPage(
                jpegData: jpegData,
                width: Int(image.size.width * image.scale),
                height: Int(image.size.height * image.scale)
            ))
            if let pdfDocument {
                guard let pdfPage = PDFPage(image: image) else {
                    throw ScanDocumentError.pdfEncodingFailed
                }
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }
        }
        guard !pages.isEmpty else {
            throw ScanDocumentError.emptyScan
        }
        return CapturedDocument(
            pages: pages,
            pdfData: pdfDocument?.dataRepresentation(),
            capturedPageCount: scan.pageCount
        )
    }

    private func finish(_ result: Result<CapturedDocument, Error>) {
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            self.result = result
        }
    }
}

private enum DocumentScanOutput: String {
    case pdf
    case images
    case both

    init(argument: JSONValue?) throws {
        guard let argument else {
            self = .pdf
            return
        }
        guard case .string(let value) = argument, let output = Self(rawValue: value) else {
            throw ScanDocumentError.invalidArguments("output must be pdf, images, or both")
        }
        self = output
    }

    var includesPDF: Bool { self == .pdf || self == .both }
    var includesImages: Bool { self == .images || self == .both }
}

private struct CapturedDocument: Sendable {
    let pages: [CapturedDocumentPage]
    let pdfData: Data?
    let capturedPageCount: Int
}

private struct CapturedDocumentPage: Sendable {
    let jpegData: Data
    let width: Int
    let height: Int
}

/// A model may issue another scan call after a successful result (for example,
/// by mistaking max_pages for an exact target). A user message maps to one turn,
/// so replaying that turn's first result is both idempotent and prevents a second
/// camera presentation. A later explicit user request has a new turn ID.
private actor DocumentScanTurnCache {
    static let shared = DocumentScanTurnCache()

    private let capacity = 64
    private var results: [String: ClientToolExecutionResult] = [:]
    private var insertionOrder: [String] = []

    func result(for key: String) -> ClientToolExecutionResult? {
        results[key]
    }

    func store(_ result: ClientToolExecutionResult, for key: String) {
        guard results[key] == nil else { return }
        results[key] = result
        insertionOrder.append(key)
        if insertionOrder.count > capacity {
            results.removeValue(forKey: insertionOrder.removeFirst())
        }
    }
}

private struct ScannedDocumentResult: Encodable {
    let success: Bool
    let pageCount: Int
    let capturedPageCount: Int
    let discardedPageCount: Int
    let truncated: Bool
    let message: String?
    let pdf: ScannedDocumentPDFResult?
    let pages: [ScannedDocumentPageResult]

    enum CodingKeys: String, CodingKey {
        case success, truncated, message, pdf, pages
        case pageCount = "page_count"
        case capturedPageCount = "captured_page_count"
        case discardedPageCount = "discarded_page_count"
    }
}

private struct CancelledDocumentScanResult: Encodable {
    let success: Bool
    let cancelled: Bool
    let shouldRetry: Bool
    let message: String

    enum CodingKeys: String, CodingKey {
        case success, cancelled, message
        case shouldRetry = "should_retry"
    }
}

private struct ScannedDocumentPDFResult: Encodable {
    let relativePath: String
    let bytes: Int64

    enum CodingKeys: String, CodingKey {
        case bytes
        case relativePath = "relative_path"
    }
}

private struct ScannedDocumentPageResult: Encodable {
    let pageNumber: Int
    let relativePath: String
    let width: Int
    let height: Int
    let bytes: Int64

    enum CodingKeys: String, CodingKey {
        case width, height, bytes
        case pageNumber = "page_number"
        case relativePath = "relative_path"
    }
}

public enum ScanDocumentError: LocalizedError {
    case invalidArguments(String)
    case missingUsageDescription
    case presentationUnavailable
    case scannerUnavailable
    case cancelled
    case captureFailed(String)
    case emptyScan
    case imageEncodingFailed(Int)
    case pdfEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return "Invalid arguments: \(message)"
        case .missingUsageDescription:
            return "The host App Info.plist must define a non-empty NSCameraUsageDescription value."
        case .presentationUnavailable:
            return "Document scanning requires an active ClientToolPresentationCoordinator."
        case .scannerUnavailable: return "Document scanning is unavailable on this device."
        case .cancelled: return "Document scanning was cancelled."
        case .captureFailed(let message): return "Document scanning failed: \(message)"
        case .emptyScan: return "The document scan contains no pages."
        case .imageEncodingFailed(let page): return "Failed to encode scanned page \(page)."
        case .pdfEncodingFailed: return "Failed to create a PDF from the scanned pages."
        }
    }
}

#endif
