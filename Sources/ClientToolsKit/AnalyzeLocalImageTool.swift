import ClientToolProtocol
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import VisualGroundingKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Reads an image from the shared workspace and performs on-device analysis.
/// VisualGroundingKit provides structured visual facts; ImageIO and Vision retain
/// the lightweight metadata and barcode paths.
public struct AnalyzeLocalImageTool: ClientTool {
    public let name = "analyze_local_image"
    public let description = """
分析当前 workspace 中的本地图片。支持图片基础信息、OCR、条码/二维码和 VisualGroundingKit 结构化视觉理解，所有处理均在设备本地完成。
参数：
  - path（必填）：由 capture_photo 等工具返回的 workspace 相对路径
  - mode（可选）："auto"、"basic"、"ocr"、"barcode" 或 "grounding"，默认 "auto"
  - include_debug（可选）：是否返回原始 top-N 分类、显著区域数量等诊断信息，默认 false
说明：
  - auto：基础信息 + VisualGroundingKit + 条码
  - grounding：主体、场景、构图、风格、OCR 和图片质量等结构化结果
"""

    private let groundingService: any ImageUnderstandingService

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的图片相对路径")
                ]),
                "mode": .object([
                    "type": .string("string"),
                    "description": .string("分析模式：auto/basic/ocr/barcode/grounding，默认 auto"),
                    "enum": .array([.string("auto"), .string("basic"), .string("ocr"), .string("barcode"), .string("grounding")]),
                    "default": .string("auto")
                ]),
                "include_debug": .object([
                    "type": .string("boolean"),
                    "description": .string("返回本地视觉诊断信息，默认 false"),
                    "default": .bool(false)
                ])
            ]),
            "required": .array([.string("path")])
        ])
    }

    public init() {
        groundingService = VisualGroundingKitFactory.makeImageUnderstandingService()
    }

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args,
              case .string(let relativePath) = values["path"] else {
            throw AnalyzeLocalImageError.invalidArguments("Missing required string parameter: path")
        }

        let modeString: String
        if case .string(let requestedMode) = values["mode"] {
            modeString = requestedMode
        } else {
            modeString = "auto"
        }
        guard let mode = AnalysisMode(rawValue: modeString) else {
            throw AnalyzeLocalImageError.invalidArguments("mode must be auto, basic, ocr, barcode, or grounding")
        }
        let includeDebug: Bool
        if case .bool(let requestedIncludeDebug) = values["include_debug"] {
            includeDebug = requestedIncludeDebug
        } else {
            includeDebug = false
        }

        let workspace = try ToolWorkspace(context: context)
        let imageURL = try workspace.resolve(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            throw AnalyzeLocalImageError.fileNotFound(relativePath)
        }

        let startedAt = Date()
        let metadata = try Self.readMetadata(from: imageURL)
        var texts: [RecognizedText] = []
        var barcodes: [RecognizedBarcode] = []
        var grounding: VisualGroundingPayload?
        var warnings: [String] = []

        if mode.runsGrounding {
            let groundingResult = try await performGrounding(
                imageURL: imageURL,
                includeDebug: includeDebug
            )
            grounding = groundingResult.payload
            texts = groundingResult.texts
        }

        if mode.runsOCR || mode.runsBarcode {
            do {
                let visionResult = try Self.performVision(
                    imageURL: imageURL,
                    runOCR: mode.runsOCR,
                    runBarcode: mode.runsBarcode
                )
                if mode.runsOCR {
                    texts = visionResult.texts
                }
                barcodes = visionResult.barcodes
            } catch where mode == .auto {
                // Grounding is the primary auto-mode result. Optional barcode
                // detection should not discard it when Vision cannot initialize
                // that request on the current device.
                warnings.append("Barcode analysis unavailable: \(error.localizedDescription)")
            }
        }

        let result = LocalImageAnalysisResult(
            success: true,
            relativePath: relativePath,
            mimeType: metadata.mimeType,
            bytes: metadata.bytes,
            width: metadata.width,
            height: metadata.height,
            orientation: metadata.orientation,
            texts: texts,
            barcodes: barcodes,
            grounding: grounding,
            warnings: warnings,
            localOnly: true,
            engine: mode.runsGrounding
                ? "VisualGroundingKit + Apple Vision + ImageIO"
                : "Apple Vision + ImageIO",
            elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
        return try ToolResultEncoder.executionResult(result)
    }

    private func performGrounding(
        imageURL: URL,
        includeDebug: Bool
    ) async throws -> (payload: VisualGroundingPayload, texts: [RecognizedText]) {
        let image = try Self.loadVisualImage(from: imageURL)
        let asset = InputImageAsset(
            image: image,
            source: .workspace,
            role: .mainSubject
        )
        let descriptor = try await groundingService.analyze(image: asset)
        let payload = DefaultVisualGroundingMapper().map(
            descriptor,
            includeDebug: includeDebug
        )
        let texts = (descriptor.rawVision?.recognizedTexts ?? []).map {
            RecognizedText(text: $0.text, confidence: $0.confidence ?? 0)
        }
        return (payload, texts)
    }

    private static func loadVisualImage(from url: URL) throws -> VisualImage {
        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw AnalyzeLocalImageError.unsupportedImage
        }
        return image
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else {
            throw AnalyzeLocalImageError.unsupportedImage
        }
        return image
        #else
        throw AnalyzeLocalImageError.unsupportedImage
        #endif
    }

    private static func readMetadata(from url: URL) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AnalyzeLocalImageError.unsupportedImage
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            throw AnalyzeLocalImageError.metadataUnavailable
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue
        let mimeType = CGImageSourceGetType(source)
            .flatMap { UTType($0 as String)?.preferredMIMEType }

        return ImageMetadata(
            mimeType: mimeType,
            bytes: bytes,
            width: width,
            height: height,
            orientation: orientation
        )
    }

    private static func performVision(
        imageURL: URL,
        runOCR: Bool,
        runBarcode: Bool
    ) throws -> (texts: [RecognizedText], barcodes: [RecognizedBarcode]) {
        var requests: [VNRequest] = []
        let textRequest = VNRecognizeTextRequest()
        let barcodeRequest = VNDetectBarcodesRequest()

        if runOCR {
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            requests.append(textRequest)
        }
        if runBarcode {
            requests.append(barcodeRequest)
        }

        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        try handler.perform(requests)

        let texts = (textRequest.results ?? []).compactMap { observation -> RecognizedText? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedText(text: candidate.string, confidence: candidate.confidence)
        }
        let barcodes = (barcodeRequest.results ?? []).compactMap { observation -> RecognizedBarcode? in
            guard let payload = observation.payloadStringValue else { return nil }
            return RecognizedBarcode(payload: payload, symbology: observation.symbology.rawValue)
        }
        return (texts, barcodes)
    }
}

private enum AnalysisMode: String {
    case auto
    case basic
    case ocr
    case barcode
    case grounding

    var runsOCR: Bool { self == .ocr }
    var runsBarcode: Bool { self == .auto || self == .barcode }
    var runsGrounding: Bool { self == .auto || self == .grounding }
}

private struct ImageMetadata {
    let mimeType: String?
    let bytes: Int64
    let width: Int?
    let height: Int?
    let orientation: Int?
}

private struct RecognizedText: Encodable {
    let text: String
    let confidence: Float
}

private struct RecognizedBarcode: Encodable {
    let payload: String
    let symbology: String
}

private struct LocalImageAnalysisResult: Encodable {
    let success: Bool
    let relativePath: String
    let mimeType: String?
    let bytes: Int64
    let width: Int?
    let height: Int?
    let orientation: Int?
    let texts: [RecognizedText]
    let barcodes: [RecognizedBarcode]
    let grounding: VisualGroundingPayload?
    let warnings: [String]
    let localOnly: Bool
    let engine: String
    let elapsedMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case success
        case relativePath = "relative_path"
        case mimeType = "mime_type"
        case bytes, width, height, orientation, texts, barcodes, grounding, warnings
        case localOnly = "local_only"
        case engine
        case elapsedMilliseconds = "elapsed_ms"
    }
}

private enum AnalyzeLocalImageError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case unsupportedImage
    case metadataUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .fileNotFound(let path):
            return "Image not found in workspace: \(path)"
        case .unsupportedImage:
            return "The file is not a supported image."
        case .metadataUnavailable:
            return "Unable to read image metadata."
        }
    }
}
