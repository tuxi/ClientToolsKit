//
//  UserIntentNormalizingService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 用户意图归一化服务。
///
/// 作用：
/// - 将用户自然语言输入
/// - 转换为结构化的 `NormalizedIntentPayload`
///
/// 第一版目标：
/// - 先用规则做基础解析
/// - 不追求复杂 NLP
/// - 优先识别镜头、表情、风格、环境动态等常见意图
public protocol UserIntentNormalizingService: Sendable {
    
    /// 将用户输入归一化为结构化意图。
    ///
    /// - Parameters:
    ///   - input: 用户原始输入
    ///   - grounding: 图片 grounding 结果，可用于辅助解析
    ///   - language: 当前语言
    ///   - task: 当前任务类型
    /// - Returns: 结构化意图
    func normalize(
        _ input: UserIntentInput,
        grounding: VisualGroundingPayload,
        language: PromptLanguage,
        task: GenerationTask
    ) async throws -> NormalizedVisualIntent
}
