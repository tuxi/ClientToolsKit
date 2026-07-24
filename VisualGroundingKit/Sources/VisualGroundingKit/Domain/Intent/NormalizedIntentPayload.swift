//
//  NormalizedIntentPayload.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 结构化后的用户意图。
///
/// 这是一种“归一化意图层”，
/// 可以来自：
/// - 用户输入解析
/// - 自动生成默认意图
public struct NormalizedIntentPayload: Sendable {
    /// 主体动态意图
    public let subjectMotion: SubjectMotionIntent?
    
    /// 镜头运动意图
    public let cameraMotion: CameraMotionIntent?
    
    /// 环境动态意图
    public let environmentMotion: EnvironmentMotionIntent?
    
    /// 风格意图
    public let styleIntent: StyleIntent?
    
    /// 表情意图
    ///
    /// 例如：
    /// - natural_smile
    public let facialExpression: String?
    
    /// 用户原始文本摘要
    public let sourceSummary: String?
    
    public init(
        subjectMotion: SubjectMotionIntent? = nil,
        cameraMotion: CameraMotionIntent? = nil,
        environmentMotion: EnvironmentMotionIntent? = nil,
        styleIntent: StyleIntent? = nil,
        facialExpression: String? = nil,
        sourceSummary: String? = nil
    ) {
        self.subjectMotion = subjectMotion
        self.cameraMotion = cameraMotion
        self.environmentMotion = environmentMotion
        self.styleIntent = styleIntent
        self.facialExpression = facialExpression
        self.sourceSummary = sourceSummary
    }
}
