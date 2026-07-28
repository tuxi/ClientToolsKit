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
/// VisualGroundingKit provides structured visual facts via a unified Vision pipeline;
/// no duplicate `VNImageRequestHandler` instances are created.
public struct AnalyzeLocalImageTool: ClientTool {
    public let name = "analyze_local_image"
    public let description = """
分析当前 workspace 中的本地图片。支持图片基础信息、OCR、条码/二维码和 VisualGroundingKit 结构化视觉理解，所有处理均在设备本地完成。
参数：
  - path（必填）：由 capture_photo 等工具返回的 workspace 相对路径
  - mode（可选）："auto"、"basic"、"ocr"、"barcode" 或 "grounding"，默认 "auto"
  - profile（可选）："agent_compact"、"generation_grounding" 或 "debug"，默认 "agent_compact"
  - include_debug（可选）：是否返回原始诊断信息，默认 false
说明：
  - auto：基础信息 + 紧凑视觉理解（OCR、条码、分类、主体），推荐 Agent 调用
  - grounding：完整 VisualGroundingKit 输出，包含 motion/preservation/prompt hints
  - ocr / barcode：仅执行对应 Vision 请求
  - basic：仅返回图片元数据
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
                "profile": .object([
                    "type": .string("string"),
                    "description": .string("分析剖面：agent_compact/generation_grounding/debug，默认 agent_compact"),
                    "enum": .array([.string("agent_compact"), .string("generation_grounding"), .string("debug")]),
                    "default": .string("agent_compact")
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

        let profile: AnalysisProfile
        if case .string(let requestedProfile) = values["profile"] {
            switch requestedProfile {
            case "agent_compact": profile = .agentCompact
            case "debug": profile = .debug
            default: profile = .generationGrounding
            }
        } else {
            profile = .agentCompact
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
        var compactPayload: AgentCompactPayload?
        let warnings: [String] = []

        // --- Unified pipeline: all modes except basic go through one analysis path ---

        if mode == .basic {
            // Metadata only — no Vision work at all.
        } else if mode == .ocr || mode == .barcode {
            // Lightweight path: run only the requested Vision requests.
            // Does NOT trigger the full grounding pipeline.
            let visionResult = try Self.performLightweightVision(
                imageURL: imageURL,
                runOCR: mode == .ocr,
                runBarcode: mode == .barcode
            )
            texts = visionResult.texts
            barcodes = visionResult.barcodes
        } else {
            // auto / grounding: full VisualGroundingKit pipeline.
            // OCR and barcodes come from the unified rawVision — no second handler.
            let groundingResult = try await performGrounding(
                imageURL: imageURL,
                profile: profile,
                includeDebug: includeDebug
            )
            grounding = groundingResult.payload
            texts = groundingResult.texts
            barcodes = groundingResult.barcodes

            if profile == .agentCompact {
                compactPayload = Self.buildAgentCompactPayload(
                    from: groundingResult,
                    texts: texts,
                    barcodes: barcodes,
                    metadata: metadata
                )
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
            grounding: profile == .agentCompact ? nil : grounding,
            compact: compactPayload,
            warnings: warnings,
            localOnly: true,
            engine: engineLabel(mode: mode, profile: profile),
            elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
        return try ToolResultEncoder.executionResult(result)
    }

    // MARK: - Grounding (unified pipeline)

    private func performGrounding(
        imageURL: URL,
        profile: AnalysisProfile,
        includeDebug: Bool
    ) async throws -> GroundingOutput {
        let image = try Self.loadVisualImage(from: imageURL)
        let asset = InputImageAsset(
            image: image,
            source: .workspace,
            role: .mainSubject
        )
        let descriptor = try await groundingService.analyze(image: asset)

        // Map with the requested profile
        let mapper = DefaultVisualGroundingMapper()
        let payload = mapper.map(descriptor, includeDebug: includeDebug || profile == .debug, profile: profile)

        // Extract OCR texts from the descriptor (already produced by unified Vision pipeline)
        let texts = (descriptor.rawVision?.recognizedTexts ?? []).map {
            RecognizedText(
                text: $0.text,
                confidence: $0.confidence ?? 0,
                boundingBox: $0.boundingBox
            )
        }

        // Extract barcodes from rawVision (also from the unified pipeline)
        let barcodes = (descriptor.rawVision?.barcodes ?? []).map {
            RecognizedBarcode(
                payload: $0.payload,
                symbology: $0.symbology,
                boundingBox: $0.boundingBox
            )
        }

        return GroundingOutput(payload: payload, texts: texts, barcodes: barcodes, descriptor: descriptor)
    }

    /// Build a compact agent payload from the grounding output.
    private static func buildAgentCompactPayload(
        from grounding: GroundingOutput,
        texts: [RecognizedText],
        barcodes: [RecognizedBarcode],
        metadata: ImageMetadata
    ) -> AgentCompactPayload {
        let payload = grounding.payload
        let descriptor = grounding.descriptor
        let rawVision = descriptor.rawVision

        // Summary
        let summary = AnalysisSummary(
            contentType: payload.contentType.primaryType.rawValue,
            confidence: payload.contentType.confidence,
            evidenceLevel: payload.contentType.confidence != nil
                ? EvidenceLevel.observed.rawValue
                : EvidenceLevel.inferred.rawValue
        )

        // Subjects (compact): merge payload subjects with raw detected objects.
        // Person subjects from payload come first, then Core ML detected objects.
        // Limit: up to 5 total in compact mode.
        var agentSubjects: [AgentSubject] = payload.subjects.prefix(5).map { subj in
            AgentSubject(
                type: subj.type.rawValue,
                coreLabel: subj.coreLabel,
                canonicalLabel: subj.canonicalLabel,
                confidence: subj.confidence,
                boundingBox: subj.boundingBoxes.first.map(AgentBoundingBox.init(from:)),
                count: subj.count > 1 ? subj.count : nil,
                posture: subj.posture ?? subj.postureType,
                evidenceLevel: subj.type == .unknown
                    ? EvidenceLevel.uncertain.rawValue
                    : EvidenceLevel.observed.rawValue
            )
        }

        // Supplement with raw detected objects not already represented in payload subjects.
        if let detected = rawVision?.detectedObjects, !detected.isEmpty {
            let existingLabels = Set(payload.subjects.compactMap { $0.canonicalLabel }.map { $0.lowercased() })
            for obj in detected.prefix(5) {
                guard agentSubjects.count < 5 else { break }
                if existingLabels.contains(obj.label.lowercased()) { continue }
                agentSubjects.append(
                    AgentSubject(
                        type: "object",
                        coreLabel: obj.label,
                        canonicalLabel: obj.label,
                        confidence: obj.confidence,
                        boundingBox: AgentBoundingBox(
                            x: obj.boundingBox.origin.x,
                            y: obj.boundingBox.origin.y,
                            width: obj.boundingBox.size.width,
                            height: obj.boundingBox.size.height
                        ),
                        count: nil,
                        posture: nil,
                        evidenceLevel: EvidenceLevel.observed.rawValue
                    )
                )
            }
        }

        let subjects = agentSubjects

        // Scene (compact)
        let scene: AgentScene?
        if let s = payload.scene {
            scene = AgentScene(
                sceneType: s.sceneType ?? s.subSceneType,
                environmentObjects: s.environmentObjects.prefix(10).map(\.name),
                lighting: s.lighting,
                evidenceLevel: EvidenceLevel.inferred.rawValue
            )
        } else {
            scene = nil
        }

        // Text blocks (compact: keep bounding boxes, confidence, and reading order)
        let textBlocks: [AgentTextBlock] = texts.enumerated().map { index, t in
            AgentTextBlock(
                text: t.text,
                boundingBox: t.boundingBox.map {
                    AgentBoundingBox(x: $0.origin.x, y: $0.origin.y, width: $0.size.width, height: $0.size.height)
                },
                confidence: t.confidence,
                order: index
            )
        }

        // Barcodes (compact)
        let agentBarcodes: [AgentBarcode] = barcodes.map {
            AgentBarcode(
                payload: $0.payload,
                symbology: $0.symbology,
                boundingBox: $0.boundingBox.map {
                    AgentBoundingBox(x: $0.origin.x, y: $0.origin.y, width: $0.size.width, height: $0.size.height)
                }
            )
        }

        // Evidence
        let allClassifications = rawVision.map { raw in
            raw.saliencyRegions.flatMap(\.classifications)
            + raw.attentionSaliencyRegions.flatMap(\.classifications)
            + raw.classifications
        } ?? []
        let evidence = ClassificationEvidence(
            classifications: allClassifications
                .sorted { $0.confidence > $1.confidence }
                .prefix(5)
                .map { ClassificationCandidatePayload(label: $0.identifier, confidence: $0.confidence, source: $0.source) },
            saliencyRegionCount: (rawVision?.saliencyRegions.count ?? 0) + (rawVision?.attentionSaliencyRegions.count ?? 0)
        )

        // Quality
        let quality: AgentQuality?
        if let q = descriptor.quality {
            quality = AgentQuality(isBlurry: q.isBlurry, exposure: q.exposure)
        } else {
            quality = nil
        }

        // Uncertainties
        var uncertainties: [AgentUncertainty] = []
        if payload.subjects.contains(where: { $0.type == .unknown }) {
            let unknownLabels = allClassifications.prefix(3).map(\.identifier)
            uncertainties.append(AgentUncertainty(
                description: "Primary subject could not be confidently identified",
                relatedLabels: unknownLabels,
                reason: "No classification matched known object categories with sufficient confidence"
            ))
        }
        if let scene = payload.scene, scene.sceneType == nil, scene.environmentObjects.isEmpty {
            uncertainties.append(AgentUncertainty(
                description: "Scene context is ambiguous",
                relatedLabels: [],
                reason: "No dominant scene or environment objects detected"
            ))
        }

        return AgentCompactPayload(
            summary: summary,
            subjects: subjects,
            scene: scene,
            textBlocks: textBlocks,
            barcodes: agentBarcodes,
            evidence: evidence,
            quality: quality,
            uncertainties: uncertainties
        )
    }

    // MARK: - Lightweight Vision (ocr / barcode only, no grounding)

    private static func performLightweightVision(
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
            textRequest.automaticallyDetectsLanguage = true
            textRequest.minimumTextHeight = 0.010
            requests.append(textRequest)
        }
        if runBarcode {
            requests.append(barcodeRequest)
        }

        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        try handler.perform(requests)

        let texts = (textRequest.results ?? []).compactMap { observation -> RecognizedText? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedText(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
        let barcodes = (barcodeRequest.results ?? []).compactMap { observation -> RecognizedBarcode? in
            guard let payload = observation.payloadStringValue else { return nil }
            return RecognizedBarcode(
                payload: payload,
                symbology: observation.symbology.rawValue,
                boundingBox: observation.boundingBox
            )
        }
        return (texts, barcodes)
    }

    // MARK: - Helpers

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

    private func engineLabel(mode: AnalysisMode, profile: AnalysisProfile) -> String {
        let profileLabel: String
        switch profile {
        case .agentCompact: profileLabel = "AgentCompact"
        case .generationGrounding: profileLabel = "Grounding"
        case .debug: profileLabel = "Debug"
        }
        switch mode {
        case .basic:
            return "ImageIO"
        case .ocr, .barcode:
            return "Apple Vision"
        case .auto, .grounding:
            return "VisualGroundingKit (\(profileLabel)) + Apple Vision + ImageIO"
        }
    }
}

// MARK: - Supporting Types

private struct GroundingOutput {
    let payload: VisualGroundingPayload
    let texts: [RecognizedText]
    let barcodes: [RecognizedBarcode]
    let descriptor: ImageDescriptor
}

private enum AnalysisMode: String {
    case auto
    case basic
    case ocr
    case barcode
    case grounding
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
    let boundingBox: CGRect?

    init(text: String, confidence: Float, boundingBox: CGRect? = nil) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(confidence, forKey: .confidence)
        if let bbox = boundingBox {
            try container.encode(
                ["x": bbox.origin.x, "y": bbox.origin.y, "width": bbox.size.width, "height": bbox.size.height],
                forKey: .boundingBox
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case text, confidence
        case boundingBox = "bounding_box"
    }
}

private struct RecognizedBarcode: Encodable {
    let payload: String
    let symbology: String
    let boundingBox: CGRect?

    init(payload: String, symbology: String, boundingBox: CGRect? = nil) {
        self.payload = payload
        self.symbology = symbology
        self.boundingBox = boundingBox
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload, forKey: .payload)
        try container.encode(symbology, forKey: .symbology)
        if let bbox = boundingBox {
            try container.encode(
                ["x": bbox.origin.x, "y": bbox.origin.y, "width": bbox.size.width, "height": bbox.size.height],
                forKey: .boundingBox
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case payload, symbology
        case boundingBox = "bounding_box"
    }
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
    let compact: AgentCompactPayload?
    let warnings: [String]
    let localOnly: Bool
    let engine: String
    let elapsedMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case success
        case relativePath = "relative_path"
        case mimeType = "mime_type"
        case bytes, width, height, orientation, texts, barcodes, grounding, compact, warnings
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
