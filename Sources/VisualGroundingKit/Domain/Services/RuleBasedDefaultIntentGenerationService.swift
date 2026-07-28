//
//  RuleBasedDefaultIntentGenerationService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation

/// 基于规则的默认意图生成服务。
///
/// 当前定位：
/// - 当用户没有输入时
/// - 根据 `VisualGroundingPayload` 生成一份轻量动态倾向建议
///
/// 注意：
/// - 这不是最终 Prompt
/// - 只是默认动态方向
/// - 服务端或本地 LLM 后续可以继续重写
public struct RuleBasedDefaultIntentGenerationService: DefaultIntentGenerationService {
    
    public enum DefaultIntentStyle: Sendable {
        case safeSubtle
        case creativeSoft
    }
    
    private let defaultIntentStyle: DefaultIntentStyle
    
    public init(defaultIntentStyle: DefaultIntentStyle = .creativeSoft) {
        self.defaultIntentStyle = defaultIntentStyle
    }
    
    public func generateDefaultIntent(
        from grounding: VisualGroundingPayload,
        task: GenerationTask
    ) async throws -> NormalizedVisualIntent {
        switch task {
        case .imageToVideo:
            return generateImageToVideoIntent(from: grounding)
        case .imageToImage:
            return generateImageToImageIntent(from: grounding)
        case .promptPolish:
            return generatePromptPolishIntent(from: grounding)
        case .effectTemplate:
            return generateEffectTemplateIntent(from: grounding)
        }
    }
}

// MARK: - Main

private extension RuleBasedDefaultIntentGenerationService {
    
    func generateImageToVideoIntent(
        from grounding: VisualGroundingPayload
    ) -> NormalizedVisualIntent {
        let subjectMotionTokens = makeDefaultSubjectMotionTokens(from: grounding)
        let cameraMotion = makeDefaultCameraMotion(from: grounding, task: .imageToVideo)
        let environmentMotionTokens = makeDefaultEnvironmentMotion(from: grounding, task: .imageToVideo)
        let facialExpression = makeDefaultFacialExpression(from: grounding)
        let styleTokens = makeDefaultStyleTokens(from: grounding, task: .imageToVideo)
        
        return NormalizedVisualIntent(
            subjectMotionTokens: subjectMotionTokens,
            cameraMotion: cameraMotion,
            environmentMotionTokens: environmentMotionTokens,
            styleTokens: styleTokens,
            facialExpression: facialExpression,
            sourceSummary: makeSourceSummary(
                grounding: grounding,
                task: .imageToVideo,
                subjectMotionTokens: subjectMotionTokens,
                cameraMotion: cameraMotion,
                environmentMotionTokens: environmentMotionTokens,
                styleTokens: styleTokens,
                facialExpression: facialExpression
            )
        )
    }
    
    func generateImageToImageIntent(
        from grounding: VisualGroundingPayload
    ) -> NormalizedVisualIntent {
        let styleTokens = makeDefaultStyleTokens(from: grounding, task: .imageToImage)
        
        return NormalizedVisualIntent(
            styleTokens: styleTokens,
            sourceSummary: makeSourceSummary(
                grounding: grounding,
                task: .imageToImage,
                subjectMotionTokens: [],
                cameraMotion: nil,
                environmentMotionTokens: [],
                styleTokens: styleTokens,
                facialExpression: nil
            )
        )
    }
    
    func generatePromptPolishIntent(
        from grounding: VisualGroundingPayload
    ) -> NormalizedVisualIntent {
        NormalizedVisualIntent(
            sourceSummary: makeSourceSummary(
                grounding: grounding,
                task: .promptPolish,
                subjectMotionTokens: [],
                cameraMotion: nil,
                environmentMotionTokens: [],
                styleTokens: [],
                facialExpression: nil
            )
        )
    }
    
    func generateEffectTemplateIntent(
        from grounding: VisualGroundingPayload
    ) -> NormalizedVisualIntent {
        let styleTokens = makeDefaultStyleTokens(from: grounding, task: .effectTemplate)
        
        return NormalizedVisualIntent(
            styleTokens: styleTokens,
            sourceSummary: makeSourceSummary(
                grounding: grounding,
                task: .effectTemplate,
                subjectMotionTokens: [],
                cameraMotion: nil,
                environmentMotionTokens: [],
                styleTokens: styleTokens,
                facialExpression: nil
            )
        )
    }
}

// MARK: - Subject Motion

private extension RuleBasedDefaultIntentGenerationService {
    
    func makeDefaultSubjectMotionTokens(
        from grounding: VisualGroundingPayload
    ) -> [String] {
        if let candidates = grounding.motionHints?.subjectMotionCandidates, !candidates.isEmpty {
            return dedupTokens(candidates)
        }
        
        guard let subject = grounding.subjects.first else {
            return []
        }
        
        switch subject.type {
        case .person:
            var result = ["subtle_body_motion"]
            let posture = resolvedPosture(for: subject)
            if posture == "sitting" || posture == "seated" {
                result.append("seated_micro_motion")
            }
            return dedupTokens(result)
            
        case .animal:
            switch defaultIntentStyle {
            case .safeSubtle:
                return ["pet_micro_motion"]
            case .creativeSoft:
                return ["pet_micro_motion", "subtle_head_motion"]
            }
            
        case .sceneDominant, .object, .unknown:
            return []
        }
    }
}

// MARK: - Camera

private extension RuleBasedDefaultIntentGenerationService {
    
    func makeDefaultCameraMotion(
        from grounding: VisualGroundingPayload,
        task: GenerationTask
    ) -> String? {
        guard task == .imageToVideo else { return nil }
        
        if let candidates = grounding.motionHints?.cameraMotionCandidates, let first = candidates.first {
            return first
        }
        
        switch grounding.contentType.primaryType {
        case .portraitPhoto, .groupPhoto, .petPhoto:
            return "slow_push_in"
        case .landscapePhoto, .outdoorScene:
            return "static"
        case .documentPage, .screenshotUI:
            return "static"
        case .tabletopScene, .objectPhoto:
            return "static"
        default:
            return "static"
        }
    }
}

// MARK: - Environment Motion

private extension RuleBasedDefaultIntentGenerationService {
    
    func makeDefaultEnvironmentMotion(
        from grounding: VisualGroundingPayload,
        task: GenerationTask
    ) -> [String] {
        guard task == .imageToVideo else { return [] }
        
        if let candidates = grounding.motionHints?.environmentMotionCandidates, !candidates.isEmpty {
            return dedupTokens(candidates)
        }
        
        guard let scene = grounding.scene else { return [] }
        
        let objectNames = scene.environmentObjects.map { $0.name.lowercased() }
        var motions: [String] = []
        
        if objectNames.contains(where: { ["river", "water"].contains($0) }) {
            motions.append("water_flow")
        }
        
        if objectNames.contains(where: { ["plants", "shrubs", "trees", "flowers"].contains($0) }) {
            motions.append("leaves_sway")
        }
        
        if objectNames.contains("sky"),
           scene.weather != "rainy",
           scene.weather != "snowy",
           scene.weather != "foggy" {
            motions.append("cloud_drift")
        }
        
        return dedupTokens(motions)
    }
}

// MARK: - Face / Style

private extension RuleBasedDefaultIntentGenerationService {
    
    func makeDefaultFacialExpression(
        from grounding: VisualGroundingPayload
    ) -> String? {
        guard let primarySubject = grounding.subjects.first else { return nil }
        guard primarySubject.type == .person else { return nil }
        return "natural_expression"
    }
    
    func makeDefaultStyleTokens(
        from grounding: VisualGroundingPayload,
        task: GenerationTask
    ) -> [String] {
        _ = task
        return dedupTokens(grounding.style?.visualStyleTokens ?? [])
    }
}

// MARK: - Summary

private extension RuleBasedDefaultIntentGenerationService {
    
    func makeSourceSummary(
        grounding: VisualGroundingPayload,
        task: GenerationTask,
        subjectMotionTokens: [String],
        cameraMotion: String?,
        environmentMotionTokens: [String],
        styleTokens: [String],
        facialExpression: String?
    ) -> String {
        let subject = grounding.subjects.first?.coreLabel ?? "nil"
        let subjectType = grounding.subjects.first?.type.rawValue ?? "nil"
        let subjectCount = grounding.subjects.first?.count ?? 0
        let posture = resolvedPosture(for: grounding.subjects.first) ?? "nil"
        let scene = grounding.scene?.sceneType ?? "nil"
        let lighting = grounding.scene?.lighting ?? "nil"
        let contentType = grounding.contentType.primaryType.rawValue
        
        return """
        task=\(task.rawValue),
        contentType=\(contentType),
        subject=\(subject),
        subjectType=\(subjectType),
        subjectCount=\(subjectCount),
        posture=\(posture),
        scene=\(scene),
        lighting=\(lighting),
        subjectMotion=\(subjectMotionTokens.isEmpty ? "nil" : subjectMotionTokens.joined(separator: "|")),
        cameraMotion=\(cameraMotion ?? "nil"),
        environmentMotion=\(environmentMotionTokens.isEmpty ? "nil" : environmentMotionTokens.joined(separator: "|")),
        style=\(styleTokens.isEmpty ? "nil" : styleTokens.joined(separator: "|")),
        facialExpression=\(facialExpression ?? "nil")
        """
    }
    
    func resolvedPosture(for subject: SubjectPayload?) -> String? {
        subject?.postureType?.lowercased() ?? subject?.posture?.lowercased()
    }
    
    func dedupTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            
            seen.insert(key)
            result.append(cleaned)
        }
        
        return result
    }
}
