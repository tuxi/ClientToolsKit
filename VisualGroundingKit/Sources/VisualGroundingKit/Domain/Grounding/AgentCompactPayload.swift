//
//  AgentCompactPayload.swift
//  VisualGroundingKit
//
//  Target payload size: ~4–8 KB for typical Agent Q&A scenarios.
//

import Foundation
import CoreGraphics

/// Agent 问答场景的紧凑视觉分析结果。
///
/// 与 `VisualGroundingPayload` 的区别：
/// - 不输出 motion hints / preservation hints / prompt hints
/// - 不输出空的 style / composition 字段
/// - 分类候选最多 5 个，显著区域最多 3 个
/// - 每个事实标记 `EvidenceLevel`
public struct AgentCompactPayload: Sendable, Codable {

    /// 顶层摘要，包含内容类型判断和置信度。
    public let summary: AnalysisSummary

    /// 主体列表，最多 3 个。
    public let subjects: [AgentSubject]

    /// 场景信息（可能为 nil）。
    public let scene: AgentScene?

    /// OCR 文本块，保留 bounding box 和阅读顺序。
    public let textBlocks: [AgentTextBlock]

    /// 检测到的条码。
    public let barcodes: [AgentBarcode]

    /// 全图与显著区域分类证据，最多 5 条。
    public let evidence: ClassificationEvidence

    /// 图片质量提示。
    public let quality: AgentQuality?

    /// 不确定项列表，供 Agent 自行判断。
    public let uncertainties: [AgentUncertainty]

    public init(
        summary: AnalysisSummary,
        subjects: [AgentSubject] = [],
        scene: AgentScene? = nil,
        textBlocks: [AgentTextBlock] = [],
        barcodes: [AgentBarcode] = [],
        evidence: ClassificationEvidence = .init(),
        quality: AgentQuality? = nil,
        uncertainties: [AgentUncertainty] = []
    ) {
        self.summary = summary
        self.subjects = subjects
        self.scene = scene
        self.textBlocks = textBlocks
        self.barcodes = barcodes
        self.evidence = evidence
        self.quality = quality
        self.uncertainties = uncertainties
    }
}

// MARK: - Analysis Summary

public struct AnalysisSummary: Sendable, Codable {
    /// 内容类型，如 screenshot_ui / portrait_photo / document_page / tabletop_scene / unknown。
    public let contentType: String
    /// 分类置信度。
    public let confidence: Float?
    /// 证据等级：observed（基于 Vision 分类）/ inferred（基于文本密度规则推断）。
    public let evidenceLevel: String

    public init(
        contentType: String,
        confidence: Float? = nil,
        evidenceLevel: String = EvidenceLevel.inferred.rawValue
    ) {
        self.contentType = contentType
        self.confidence = confidence
        self.evidenceLevel = evidenceLevel
    }

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case confidence
        case evidenceLevel = "evidence_level"
    }
}

// MARK: - Agent Subject

public struct AgentSubject: Sendable, Codable {
    /// 主体类型：person / animal / object / unknown。
    public let type: String
    /// 核心标签，优先使用 classification 的规范化名称。
    public let coreLabel: String
    /// 正则化标签。
    public let canonicalLabel: String?
    /// 置信度。
    public let confidence: Float?
    /// 边界框（归一化坐标）。
    public let boundingBox: AgentBoundingBox?
    /// 主体大致数量。
    public let count: Int?
    /// 姿态（仅人物）。
    public let posture: String?
    /// 证据等级。
    public let evidenceLevel: String

    public init(
        type: String,
        coreLabel: String,
        canonicalLabel: String? = nil,
        confidence: Float? = nil,
        boundingBox: AgentBoundingBox? = nil,
        count: Int? = nil,
        posture: String? = nil,
        evidenceLevel: String = EvidenceLevel.observed.rawValue
    ) {
        self.type = type
        self.coreLabel = coreLabel
        self.canonicalLabel = canonicalLabel
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.count = count
        self.posture = posture
        self.evidenceLevel = evidenceLevel
    }

    enum CodingKeys: String, CodingKey {
        case type
        case coreLabel = "core_label"
        case canonicalLabel = "canonical_label"
        case confidence
        case boundingBox = "bounding_box"
        case count
        case posture
        case evidenceLevel = "evidence_level"
    }
}

public struct AgentBoundingBox: Sendable, Codable {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from payload: BoundingBoxPayload) {
        self.x = payload.x
        self.y = payload.y
        self.width = payload.width
        self.height = payload.height
    }
}

// MARK: - Agent Scene

public struct AgentScene: Sendable, Codable {
    /// 场景类型标签。
    public let sceneType: String?
    /// 环境物体名称列表。
    public let environmentObjects: [String]
    /// 光照描述。
    public let lighting: String?
    /// 证据等级。
    public let evidenceLevel: String

    public init(
        sceneType: String? = nil,
        environmentObjects: [String] = [],
        lighting: String? = nil,
        evidenceLevel: String = EvidenceLevel.observed.rawValue
    ) {
        self.sceneType = sceneType
        self.environmentObjects = environmentObjects
        self.lighting = lighting
        self.evidenceLevel = evidenceLevel
    }

    enum CodingKeys: String, CodingKey {
        case sceneType = "scene_type"
        case environmentObjects = "environment_objects"
        case lighting
        case evidenceLevel = "evidence_level"
    }
}

// MARK: - Agent Text Block

public struct AgentTextBlock: Sendable, Codable {
    /// 识别文本。
    public let text: String
    /// 文本边界框（归一化坐标）。
    public let boundingBox: AgentBoundingBox?
    /// OCR 置信度。
    public let confidence: Float?
    /// 阅读顺序索引。
    public let order: Int?

    public init(
        text: String,
        boundingBox: AgentBoundingBox? = nil,
        confidence: Float? = nil,
        order: Int? = nil
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.order = order
    }

    enum CodingKeys: String, CodingKey {
        case text
        case boundingBox = "bounding_box"
        case confidence
        case order
    }
}

// MARK: - Agent Barcode

public struct AgentBarcode: Sendable, Codable {
    /// 条码/二维码内容。
    public let payload: String
    /// 条码类型。
    public let symbology: String
    /// 边界框（归一化坐标）。
    public let boundingBox: AgentBoundingBox?

    public init(
        payload: String,
        symbology: String,
        boundingBox: AgentBoundingBox? = nil
    ) {
        self.payload = payload
        self.symbology = symbology
        self.boundingBox = boundingBox
    }

    enum CodingKeys: String, CodingKey {
        case payload
        case symbology
        case boundingBox = "bounding_box"
    }
}

// MARK: - Classification Evidence

public struct ClassificationEvidence: Sendable, Codable {
    /// 分类候选项，最多 5 个。
    public let classifications: [ClassificationCandidatePayload]
    /// 显著区域数量。
    public let saliencyRegionCount: Int

    public init(
        classifications: [ClassificationCandidatePayload] = [],
        saliencyRegionCount: Int = 0
    ) {
        self.classifications = classifications
        self.saliencyRegionCount = saliencyRegionCount
    }

    enum CodingKeys: String, CodingKey {
        case classifications
        case saliencyRegionCount = "saliency_region_count"
    }
}

// MARK: - Agent Quality

public struct AgentQuality: Sendable, Codable {
    /// 是否模糊。
    public let isBlurry: Bool?
    /// 曝光提示。
    public let exposure: String?

    public init(isBlurry: Bool? = nil, exposure: String? = nil) {
        self.isBlurry = isBlurry
        self.exposure = exposure
    }

    enum CodingKeys: String, CodingKey {
        case isBlurry = "is_blurry"
        case exposure
    }
}

// MARK: - Agent Uncertainty

public struct AgentUncertainty: Sendable, Codable {
    /// 不确定项描述。
    public let description: String
    /// 相关分类标签。
    public let relatedLabels: [String]
    /// 不确定原因。
    public let reason: String

    public init(
        description: String,
        relatedLabels: [String] = [],
        reason: String
    ) {
        self.description = description
        self.relatedLabels = relatedLabels
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case description
        case relatedLabels = "related_labels"
        case reason
    }
}
