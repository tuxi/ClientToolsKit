//
//  VisionConfidence.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Vision

/// Vision 分类结果的置信度等级
///
/// 用于将 `VNClassificationObservation.confidence`
/// 映射为更容易控制的离散等级。
enum ConfidenceLevel {
    case strong
    case medium
    case weak
    case ignore
}

/// 将 Vision 分类结果的 confidence 映射为置信度等级。
///
/// 建议策略：
/// - strong: 高可信，直接参与主结论
/// - medium: 中等可信，参与辅助补充
/// - weak: 弱可信，只做轻微补充
/// - ignore: 直接忽略
func confidenceLevel(for confidence: VNConfidence) -> ConfidenceLevel {
    switch confidence {
    case 0.60...:
        return .strong
    case 0.25..<0.60:
        return .medium
    case 0.10..<0.25:
        return .weak
    default:
        return .ignore
    }
}

func rawConfidenceLevel(for confidence: Float) -> ConfidenceLevel {
    switch confidence {
    case 0.60...:
        return .strong
    case 0.25..<0.60:
        return .medium
    case 0.10..<0.25:
        return .weak
    default:
        return .ignore
    }
}
