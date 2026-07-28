//
//  VisualPreparationResult.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation

/// 视觉准备结果。
///
/// 这是业务层最适合消费的结果：
/// - visualGrounding：主图结构化视觉结果，给服务端
/// - normalizedIntent：用户输入归一化后的结构化意图
/// - analysisResults：所有输入图片的完整分析结果，便于调试与扩展
public struct VisualPreparationResult: Sendable, Codable {
    
    /// 当前请求所属的生成上下文。
    public let generationContext: GenerationContext?
    
    /// 主图结构化结果，供服务端工作流直接使用
    public let visualGrounding: VisualGroundingPayload

    /// 服务端消费型轻量路由 hints。
    public let promptHints: PromptHintsPayload?
    
    /// 用户输入归一化后的结构化意图
    public let normalizedIntent: NormalizedVisualIntent
    
    /// 所有输入图片的分析结果
    public let analysisResults: [VisualAnalysisResult]
    
    public init(
        generationContext: GenerationContext? = nil,
        visualGrounding: VisualGroundingPayload,
        promptHints: PromptHintsPayload? = nil,
        normalizedIntent: NormalizedVisualIntent,
        analysisResults: [VisualAnalysisResult]
    ) {
        self.generationContext = generationContext
        self.visualGrounding = visualGrounding
        self.promptHints = promptHints
        self.normalizedIntent = normalizedIntent
        self.analysisResults = analysisResults
    }
}

public struct NormalizedVisualIntent: Sendable, Codable {
    
    /// 主体动态倾向
    public let subjectMotionTokens: [String]
    
    /// 镜头动态倾向
    public let cameraMotion: String?
    
    /// 环境动态倾向
    public let environmentMotionTokens: [String]
    
    /// 风格倾向
    public let styleTokens: [String]
    
    /// 表情倾向
    public let facialExpression: String?
    
    /// 调试摘要
    public let sourceSummary: String?
    
    public init(
        subjectMotionTokens: [String] = [],
        cameraMotion: String? = nil,
        environmentMotionTokens: [String] = [],
        styleTokens: [String] = [],
        facialExpression: String? = nil,
        sourceSummary: String? = nil
    ) {
        self.subjectMotionTokens = subjectMotionTokens
        self.cameraMotion = cameraMotion
        self.environmentMotionTokens = environmentMotionTokens
        self.styleTokens = styleTokens
        self.facialExpression = facialExpression
        self.sourceSummary = sourceSummary
    }
}
