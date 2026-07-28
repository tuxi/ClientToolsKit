//
//  AnalysisProfile.swift
//  VisualGroundingKit
//

import Foundation

/// 分析模式，控制 Vision 请求集合、输出字段和 payload 大小。
///
/// - `agentCompact`：面向 Agent 问答场景，只输出核心事实，JSON 约 4–8 KB。
/// - `generationGrounding`：完整视频/图像生成 grounding，包含 motion hints、preservation hints 等。
/// - `debug`：类似 generationGrounding，但额外输出所有原始 Vision observations。
public enum AnalysisProfile: Sendable, Hashable, Codable {
    case agentCompact
    case generationGrounding
    case debug
}

/// 证据等级，标记每个结果的可靠程度。
///
/// - `observed`：由 Vision/OCR/条码等传感器直接产出的事实。
/// - `inferred`：基于规则推断的结论（如"这是截图"、"这是充值页面"）。
/// - `uncertain`：低置信度或候选间差异不大的结果。
public enum EvidenceLevel: String, Sendable, Hashable, Codable {
    case observed
    case inferred
    case uncertain
}
