//
//  PrepareVisualGenerationUseCase.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation

public protocol PrepareVisualGenerationUseCase: Sendable {
    
    /// 生成视觉结构化准备结果
    ///
    /// 输出仅包含：
    /// - generationContext
    /// - grounding
    /// - normalizedIntent
    /// - analysisResults
    func prepare(
        images: [InputImageAsset],
        userIntent: UserIntentInput,
        generationContext: GenerationContext?
    ) async throws -> VisualPreparationResult
}

public extension PrepareVisualGenerationUseCase {
    
    func prepare(
        images: [InputImageAsset],
        userIntent: UserIntentInput
    ) async throws -> VisualPreparationResult {
        try await prepare(
            images: images,
            userIntent: userIntent,
            generationContext: nil
        )
    }
}
