//
//  DefaultGenerateCompositePromptUseCase.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

/// 轻量视觉生成准备用例。
///
/// 当前职责：
/// 1. 图片预处理
/// 2. 图片结构化分析
/// 3. 映射统一视觉输出结构
/// 4. 选择主图结构化结果
/// 5. 用户输入归一化 / 默认意图生成
///
/// 不再负责：
/// - Prompt 生成
/// - Prompt 编译
/// - Scene Fusion
/// - Prompt 缓存
public final class DefaultGenerateCompositePromptUseCase: PrepareVisualGenerationUseCase {
    
    private let preprocessor: ImagePreprocessing
    private let understandingService: ImageUnderstandingService
    private let analysisCache: VisualAnalysisCaching?
    
    private let groundingMapper: VisualGroundingMapping
    private let defaultIntentGenerator: DefaultIntentGenerationService
    private let userIntentNormalizer: UserIntentNormalizingService
    
    public init(
        preprocessor: ImagePreprocessing,
        understandingService: ImageUnderstandingService,
        analysisCache: VisualAnalysisCaching? = nil,
        groundingMapper: VisualGroundingMapping = DefaultVisualGroundingMapper(),
        defaultIntentGenerator: DefaultIntentGenerationService = RuleBasedDefaultIntentGenerationService(),
        userIntentNormalizer: UserIntentNormalizingService = RuleBasedUserIntentNormalizingService()
    ) {
        self.preprocessor = preprocessor
        self.understandingService = understandingService
        self.analysisCache = analysisCache
        self.groundingMapper = groundingMapper
        self.defaultIntentGenerator = defaultIntentGenerator
        self.userIntentNormalizer = userIntentNormalizer
    }
    
    public func prepare(
        images: [InputImageAsset],
        userIntent: UserIntentInput,
        generationContext: GenerationContext? = nil
    ) async throws -> VisualPreparationResult {
        guard !images.isEmpty else {
            throw VisualGroundingError.emptyImages
        }
        
        let normalizedAssets = try await normalizeAssets(images)
        let analysisResults = try await analyzeAssets(normalizedAssets)
        
        let primaryGrounding = resolvePrimaryGrounding(
            from: analysisResults,
            normalizedAssets: normalizedAssets
        )
        
        DLLog("主 Grounding 选择完成:", primaryGrounding.debug?.analyzerSummary ?? "nil")
        
        let resolvedGenerationContext = resolveGenerationContext(
            generationContext,
            grounding: primaryGrounding
        )
        
        let normalizedIntent = try await resolveNormalizedIntent(
            userIntent: userIntent,
            grounding: primaryGrounding,
            generationContext: resolvedGenerationContext
        )
        
        return VisualPreparationResult(
            generationContext: resolvedGenerationContext,
            visualGrounding: primaryGrounding,
            promptHints: primaryGrounding.promptHints,
            normalizedIntent: normalizedIntent,
            analysisResults: analysisResults
        )
    }
}

// MARK: - Private Workflow

private extension DefaultGenerateCompositePromptUseCase {
    
    func normalizeAssets(_ images: [InputImageAsset]) async throws -> [InputImageAsset] {
        var normalizedAssets: [InputImageAsset] = []
        normalizedAssets.reserveCapacity(images.count)
        
        for asset in images {
            let normalizedImage = try await preprocessor.normalize(asset.image)
            normalizedAssets.append(
                InputImageAsset(
                    id: asset.id,
                    image: normalizedImage,
                    source: asset.source,
                    role: asset.role
                )
            )
        }
        
        return normalizedAssets
    }
    
    func analyzeAssets(_ assets: [InputImageAsset]) async throws -> [VisualAnalysisResult] {
        var results: [VisualAnalysisResult] = []
        results.reserveCapacity(assets.count)
        
        for asset in assets {
            let cacheKey = makeDescriptorCacheKey(for: asset)
            let descriptor: ImageDescriptor
            
            if let analysisCache,
               let cachedDescriptor = await analysisCache.descriptor(for: cacheKey) {
                DLLog("命中图片分析缓存:", cacheKey)
                descriptor = cachedDescriptor
            } else {
                DLLog("未命中图片分析缓存，开始分析:", cacheKey)
                descriptor = try await understandingService.analyze(image: asset)
                
                if let analysisCache {
                    await analysisCache.saveDescriptor(descriptor, for: cacheKey)
                }
            }
            
            let visualGrounding = groundingMapper.map(descriptor)
            DLLog("Visual Grounding 映射完成:", visualGrounding.debug?.analyzerSummary ?? "nil")
            
            results.append(
                VisualAnalysisResult(
                    descriptor: descriptor,
                    visualGrounding: visualGrounding
                )
            )
        }
        
        return results
    }
    
    func resolvePrimaryGrounding(
        from results: [VisualAnalysisResult],
        normalizedAssets: [InputImageAsset]
    ) -> VisualGroundingPayload {
        guard !results.isEmpty else {
            return VisualGroundingPayload(
                assetRole: InputImageAsset.ImageRole.mainSubject.rawValue,
                contentType: ContentTypePayload(primaryType: .unknown)
            )
        }
        
        if let mainIndex = normalizedAssets.firstIndex(where: { $0.role == .mainSubject }),
           results.indices.contains(mainIndex) {
            return results[mainIndex].visualGrounding
        }
        
        return results[0].visualGrounding
    }
    
    func resolveNormalizedIntent(
        userIntent: UserIntentInput,
        grounding: VisualGroundingPayload,
        generationContext: GenerationContext
    ) async throws -> NormalizedVisualIntent {
        let task = generationContext.task
        
        if userIntent.hasUserText {
            DLLog("检测到用户输入意图，开始归一化:", userIntent.rawText ?? "")
            
            let normalized = try await userIntentNormalizer.normalize(
                userIntent,
                grounding: grounding,
                language: .chinese,
                task: task
            )
            
            DLLog("用户意图归一化完成:", normalized.sourceSummary ?? "nil")
            return normalized
        }
        
        if userIntent.enableDefaultIntent {
            DLLog("未检测到用户输入，开始生成默认意图")
            
            let normalized = try await defaultIntentGenerator.generateDefaultIntent(
                from: grounding,
                task: task
            )
            
            DLLog("默认意图生成完成:", normalized.sourceSummary ?? "nil")
            return normalized
        }
        
        let emptyIntent = NormalizedVisualIntent(
            sourceSummary: "no user intent and default intent disabled"
        )
        
        DLLog("未启用默认意图，使用空意图")
        return emptyIntent
    }
}

// MARK: - Cache Key

private extension DefaultGenerateCompositePromptUseCase {
    
    func makeDescriptorCacheKey(for asset: InputImageAsset) -> String {
        let hash = asset.image.contentHash() ?? UUID().uuidString
        return "descriptor:\(hash):\(String(describing: asset.role))"
    }
}

// MARK: - Task Resolve

private extension DefaultGenerateCompositePromptUseCase {
    
    func resolveGenerationContext(
        _ generationContext: GenerationContext?,
        grounding: VisualGroundingPayload
    ) -> GenerationContext {
        guard let generationContext else {
            return GenerationContext(task: resolveGenerationTask(from: grounding))
        }
        
        return generationContext
    }
    
    func resolveGenerationTask(from grounding: VisualGroundingPayload) -> GenerationTask {
        _ = grounding
        return .imageToVideo
    }
}
