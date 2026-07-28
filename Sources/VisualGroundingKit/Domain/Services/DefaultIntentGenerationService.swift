//
//  DefaultIntentGenerationService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 默认意图生成服务协议。
///
/// 作用：
/// - 当用户没有主动输入意图时
/// - 基于图片 grounding 生成一个“保守、低风险、保真”的默认动态意图
///
/// 注意：
/// 第一版不应该发明剧情，
/// 只应该生成安全的默认动态。
public protocol DefaultIntentGenerationService: Sendable {
    
    /// 基于 grounding 生成默认意图。
    ///
    /// - Parameters:
    ///   - grounding: 图片 grounding 结果
    ///   - task: 当前生成任务类型
    /// - Returns: 归一化后的默认意图
    func generateDefaultIntent(
        from grounding: VisualGroundingPayload,
        task: GenerationTask
    ) async throws -> NormalizedVisualIntent
}
