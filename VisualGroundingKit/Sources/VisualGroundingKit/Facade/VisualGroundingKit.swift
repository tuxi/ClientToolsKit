//
//  VisualGroundingKitFactory.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation

public enum VisualGroundingKitFactory {

    /// Creates the local, analysis-only service used to turn one image into an
    /// `ImageDescriptor`. This entry point intentionally excludes generation
    /// intent normalization and prompt preparation.
    public static func makeImageUnderstandingService() -> any ImageUnderstandingService {
        LocalImageUnderstandingService(
            subjectDetector: VisionSubjectDetector(),
            backgroundAnalyzer: VisionBackgroundAnalyzer(),
            styleAnalyzer: VisionStyleAnalyzer(),
            ocrAnalyzer: VisionOCRAnalyzer(),
            rawVisionAnalyzer: VisionRawObservationAnalyzer(),
            imageFactsAnalyzer: VisionImageFactsAnalyzer(),
            portraitAttributeAnalyzer: VisionPortraitAttributeAnalyzer(),
            backgroundComplexityAnalyzer: VisionBackgroundComplexityAnalyzer(),
            subjectHintAnalyzer: VisionSubjectHintAnalyzer(),
            environmentObjectRefiner: VisionEnvironmentObjectRefiner()
        )
    }
    
    /// 对外默认入口。
    ///
    /// 当前只构建：
    /// - 图片预处理
    /// - 本地视觉理解
    /// - grounding 映射
    /// - 默认意图生成
    /// - 用户意图归一化
    /// - 结构化分析缓存
    public static func makeDefaultUseCase() -> PrepareVisualGenerationUseCase {
        let preprocessor = ImagePreprocessor()
        
        let understandingService = makeImageUnderstandingService()
        
        let analysisCache = InMemoryVisualAnalysisCache()
        let groundingMapper = DefaultVisualGroundingMapper()
        let defaultIntentGenerator = RuleBasedDefaultIntentGenerationService()
        let userIntentNormalizer = RuleBasedUserIntentNormalizingService()
        
        return DefaultGenerateCompositePromptUseCase(
            preprocessor: preprocessor,
            understandingService: understandingService,
            analysisCache: analysisCache,
            groundingMapper: groundingMapper,
            defaultIntentGenerator: defaultIntentGenerator,
            userIntentNormalizer: userIntentNormalizer
        )
    }
    
    /// 无缓存版本。
    ///
    /// 适合调试视觉分析链路时使用，
    /// 避免缓存干扰观察结果。
    public static func makeDefaultUseCaseWithoutCache() -> PrepareVisualGenerationUseCase {
        let preprocessor = ImagePreprocessor()
        
        let understandingService = makeImageUnderstandingService()
        
        let groundingMapper = DefaultVisualGroundingMapper()
        let defaultIntentGenerator = RuleBasedDefaultIntentGenerationService()
        let userIntentNormalizer = RuleBasedUserIntentNormalizingService()
        
        return DefaultGenerateCompositePromptUseCase(
            preprocessor: preprocessor,
            understandingService: understandingService,
            analysisCache: nil,
            groundingMapper: groundingMapper,
            defaultIntentGenerator: defaultIntentGenerator,
            userIntentNormalizer: userIntentNormalizer
        )
    }
}
