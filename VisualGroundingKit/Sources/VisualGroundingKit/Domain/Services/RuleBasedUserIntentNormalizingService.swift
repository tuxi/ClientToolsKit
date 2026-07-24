//
//  RuleBasedUserIntentNormalizingService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 基于规则的用户意图归一化服务。
///
/// 当前职责：
/// - 将用户输入文本归一化为 `NormalizedVisualIntent`
/// - 动作解析统一走 `SubjectMotionPlan`
/// - 镜头 / 风格 / 表情 / 环境动态仍然走轻量规则提取
///
/// 注意：
/// - 这里只输出“结构化意图”
/// - 不负责最终 Prompt 拼接
public struct RuleBasedUserIntentNormalizingService: UserIntentNormalizingService {
    
    public init() {}
    
    public func normalize(
        _ input: UserIntentInput,
        grounding: VisualGroundingPayload,
        language: PromptLanguage,
        task: GenerationTask
    ) async throws -> NormalizedVisualIntent {
        _ = task
        
        guard input.hasUserText, let rawText = input.rawText else {
            return NormalizedVisualIntent(
                subjectMotionTokens: [],
                cameraMotion: nil,
                environmentMotionTokens: [],
                styleTokens: [],
                facialExpression: nil,
                sourceSummary: "empty user input"
            )
        }
        
        switch language {
        case .chinese:
            return normalizeChinese(rawText, grounding: grounding)
        case .english:
            return normalizeEnglish(rawText, grounding: grounding)
        }
    }
}

// MARK: - Chinese

private extension RuleBasedUserIntentNormalizingService {
    
    func normalizeChinese(
        _ text: String,
        grounding: VisualGroundingPayload
    ) -> NormalizedVisualIntent {
        let normalized = normalizeInputText(text.lowercased())
        
        let cameraMotion = extractChineseCameraMotion(from: normalized)
        let facialExpression = extractChineseFacialExpression(from: normalized)
        let styleTokens = dedupTokens(extractChineseStyleTokens(from: normalized))
        let environmentMotionTokens = dedupTokens(extractChineseEnvironmentMotions(from: normalized))
        
        let parsedPlan = SubjectMotionPlanParser.parseChinese(from: normalized)
        let subjectMotionPlan = sanitizePlan(parsedPlan, grounding: grounding)
        let subjectMotionTokens = subjectMotionPlan.map {
            SubjectMotionPlanTokenMapper.makeTokens(from: $0)
        } ?? []
        let dedupedSubjectMotionTokens = dedupTokens(subjectMotionTokens)
        
        let hitSummary = makeHitSummary(
            cameraMotion: cameraMotion,
            subjectMotionTokens: dedupedSubjectMotionTokens,
            environmentMotionTokens: environmentMotionTokens,
            styleTokens: styleTokens,
            facialExpression: facialExpression
        )
        
        let planSummary = makePlanSummary(subjectMotionPlan)
        
        return NormalizedVisualIntent(
            subjectMotionTokens: dedupedSubjectMotionTokens,
            cameraMotion: cameraMotion,
            environmentMotionTokens: environmentMotionTokens,
            styleTokens: styleTokens,
            facialExpression: facialExpression,
            sourceSummary: """
            userInput=\(text)
            plan=\(planSummary)
            hits=\(hitSummary)
            """
        )
    }
}

// MARK: - English

private extension RuleBasedUserIntentNormalizingService {
    
    func normalizeEnglish(
        _ text: String,
        grounding: VisualGroundingPayload
    ) -> NormalizedVisualIntent {
        let normalized = normalizeInputText(text.lowercased())
        
        let cameraMotion = extractEnglishCameraMotion(from: normalized)
        let facialExpression = extractEnglishFacialExpression(from: normalized)
        let styleTokens = dedupTokens(extractEnglishStyleTokens(from: normalized))
        let environmentMotionTokens = dedupTokens(extractEnglishEnvironmentMotions(from: normalized))
        
        let parsedPlan = SubjectMotionPlanParser.parseEnglish(from: normalized)
        let subjectMotionPlan = sanitizePlan(parsedPlan, grounding: grounding)
        let subjectMotionTokens = subjectMotionPlan.map {
            SubjectMotionPlanTokenMapper.makeTokens(from: $0)
        } ?? []
        let dedupedSubjectMotionTokens = dedupTokens(subjectMotionTokens)
        
        let hitSummary = makeHitSummary(
            cameraMotion: cameraMotion,
            subjectMotionTokens: dedupedSubjectMotionTokens,
            environmentMotionTokens: environmentMotionTokens,
            styleTokens: styleTokens,
            facialExpression: facialExpression
        )
        
        let planSummary = makePlanSummary(subjectMotionPlan)
        
        return NormalizedVisualIntent(
            subjectMotionTokens: dedupedSubjectMotionTokens,
            cameraMotion: cameraMotion,
            environmentMotionTokens: environmentMotionTokens,
            styleTokens: styleTokens,
            facialExpression: facialExpression,
            sourceSummary: """
            userInput=\(text)
            plan=\(planSummary)
            hits=\(hitSummary)
            """
        )
    }
}

// MARK: - Plan Sanitize

private extension RuleBasedUserIntentNormalizingService {
    
    func sanitizePlan(
        _ plan: SubjectMotionPlan?,
        grounding: VisualGroundingPayload
    ) -> SubjectMotionPlan? {
        guard var plan else { return nil }
        
        let primarySubject = grounding.subjects.first
        let subjectType = primarySubject?.type.rawValue ?? "unknown"
        let subjectCount = max(primarySubject?.count ?? 1, 1)
        
        plan.subjectType = subjectType
        plan.subjectCount = subjectCount
        
        switch subjectType {
        case "person":
            return sanitizePersonPlan(plan, grounding: grounding)
        case "animal":
            return sanitizeAnimalPlan(plan, grounding: grounding)
        case "object", "sceneDominant", "unknown":
            return nil
        default:
            return nil
        }
    }
    
    func sanitizePersonPlan(
        _ plan: SubjectMotionPlan,
        grounding: VisualGroundingPayload
    ) -> SubjectMotionPlan? {
        var sanitized = plan
        let subjectCount = grounding.subjects.first?.count ?? 1
        
        sanitized.subjectType = "person"
        sanitized.subjectCount = max(subjectCount, 1)
        
        if sanitized.subjectCount >= 2,
           sanitized.interaction == .holdingChild {
            sanitized.interaction = nil
        }
        
        return hasMeaningfulMotionPlanContent(sanitized) ? sanitized : nil
    }
    
    func sanitizeAnimalPlan(
        _ plan: SubjectMotionPlan,
        grounding: VisualGroundingPayload
    ) -> SubjectMotionPlan? {
        var sanitized = plan
        
        sanitized.subjectType = "animal"
        sanitized.subjectCount = max(grounding.subjects.first?.count ?? 1, 1)
        
        // 动物场景下，去掉明显人物专属动作
        sanitized.startPose = nil
        sanitized.primaryAction = nil
        sanitized.secondaryAction = nil
        sanitized.interaction = nil
        sanitized.gazeTarget = nil
        
        return hasMeaningfulMotionPlanContent(sanitized) ? sanitized : nil
    }
    
    func hasMeaningfulMotionPlanContent(_ plan: SubjectMotionPlan) -> Bool {
        plan.startPose != nil ||
        plan.primaryAction != nil ||
        plan.secondaryAction != nil ||
        plan.interaction != nil ||
        plan.gazeTarget != nil
    }
}

// MARK: - Chinese Extractors

private extension RuleBasedUserIntentNormalizingService {
    
    func extractChineseCameraMotion(from text: String) -> String? {
        if containsAny(text, keywords: ["镜头缓慢推进", "缓慢推进", "慢慢推进", "镜头推进", "推近"]) {
            return "slow_push_in"
        }
        
        if containsAny(text, keywords: ["镜头拉远", "缓慢拉远", "慢慢拉远", "拉远"]) {
            return "slow_pull_out"
        }
        
        if containsAny(text, keywords: ["镜头平移", "横向平移", "慢慢平移", "左右平移"]) {
            return "pan"
        }
        
        if containsAny(text, keywords: ["静止镜头", "固定镜头", "镜头不要动", "镜头静止"]) {
            return "static"
        }
        
        return nil
    }
    
    func extractChineseStyleTokens(from text: String) -> [String] {
        var result: [String] = []
        
        if containsAny(text, keywords: ["电影感", "更有电影感", "电影氛围"]) {
            result.append("cinematic")
        }
        if containsAny(text, keywords: ["温馨", "温暖", "暖一点"]) {
            result.append("warm")
        }
        if containsAny(text, keywords: ["梦幻", "梦境感"]) {
            result.append("dreamy")
        }
        if containsAny(text, keywords: ["写实", "更真实", "真实感"]) {
            result.append("realistic")
        }
        if containsAny(text, keywords: ["浪漫"]) {
            result.append("romantic")
        }
        
        return result
    }
    
    func extractChineseFacialExpression(from text: String) -> String? {
        if containsAny(text, keywords: ["自然微笑", "微笑", "笑起来", "轻轻微笑"]) {
            return "natural_smile"
        }
        
        if containsAny(text, keywords: ["自然表情", "表情自然", "神情自然"]) {
            return "natural_expression"
        }
        
        return nil
    }
    
    func extractChineseEnvironmentMotions(from text: String) -> [String] {
        var result: [String] = []
        
        if containsAny(text, keywords: ["树叶飘动", "树叶摆动", "叶子摆动", "植物轻晃"]) {
            result.append("leaves_sway")
        }
        
        if containsAny(text, keywords: ["云朵流动", "云层移动", "云慢慢飘动"]) {
            result.append("clouds_drift")
        }
        
        if containsAny(text, keywords: ["阳光闪动", "光影变化", "阳光洒落", "光线轻微变化"]) {
            result.append("light_flicker")
        }
        
        return result
    }
}

// MARK: - English Extractors

private extension RuleBasedUserIntentNormalizingService {
    
    func extractEnglishCameraMotion(from text: String) -> String? {
        if containsAny(text, keywords: ["slow push in", "camera push in", "slowly push in"]) {
            return "slow_push_in"
        }
        
        if containsAny(text, keywords: ["slow pull out", "camera pull out"]) {
            return "slow_pull_out"
        }
        
        if containsAny(text, keywords: ["camera pan", "pan"]) {
            return "pan"
        }
        
        if containsAny(text, keywords: ["static camera", "fixed camera"]) {
            return "static"
        }
        
        return nil
    }
    
    func extractEnglishStyleTokens(from text: String) -> [String] {
        var result: [String] = []
        
        if containsAny(text, keywords: ["cinematic"]) {
            result.append("cinematic")
        }
        if containsAny(text, keywords: ["warm"]) {
            result.append("warm")
        }
        if containsAny(text, keywords: ["dreamy"]) {
            result.append("dreamy")
        }
        if containsAny(text, keywords: ["realistic"]) {
            result.append("realistic")
        }
        if containsAny(text, keywords: ["romantic"]) {
            result.append("romantic")
        }
        
        return result
    }
    
    func extractEnglishFacialExpression(from text: String) -> String? {
        if containsAny(text, keywords: ["natural smile", "smile", "smiling"]) {
            return "natural_smile"
        }
        
        if containsAny(text, keywords: ["natural expression"]) {
            return "natural_expression"
        }
        
        return nil
    }
    
    func extractEnglishEnvironmentMotions(from text: String) -> [String] {
        var result: [String] = []
        
        if containsAny(text, keywords: ["leaves sway", "leaf motion", "plants moving"]) {
            result.append("leaves_sway")
        }
        
        if containsAny(text, keywords: ["clouds moving", "cloud drift", "clouds drifting"]) {
            result.append("clouds_drift")
        }
        
        if containsAny(text, keywords: ["light flicker", "sunlight changing", "subtle light changes"]) {
            result.append("light_flicker")
        }
        
        return result
    }
}

// MARK: - Helpers

private extension RuleBasedUserIntentNormalizingService {
    
    func normalizeInputText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: "：", with: ",")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
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
    
    func makeHitSummary(
        cameraMotion: String?,
        subjectMotionTokens: [String],
        environmentMotionTokens: [String],
        styleTokens: [String],
        facialExpression: String?
    ) -> String {
        """
        camera=\(cameraMotion ?? "nil"),
        subject=\(subjectMotionTokens.isEmpty ? "nil" : subjectMotionTokens.joined(separator: "|")),
        environment=\(environmentMotionTokens.isEmpty ? "nil" : environmentMotionTokens.joined(separator: "|")),
        style=\(styleTokens.isEmpty ? "nil" : styleTokens.joined(separator: "|")),
        facial=\(facialExpression ?? "nil")
        """
    }
    
    func makePlanSummary(_ plan: SubjectMotionPlan?) -> String {
        guard let plan else { return "nil" }
        
        return """
        subjectType=\(plan.subjectType),
        subjectCount=\(plan.subjectCount),
        startPose=\(String(describing: plan.startPose)),
        primaryAction=\(String(describing: plan.primaryAction)),
        secondaryAction=\(String(describing: plan.secondaryAction)),
        interaction=\(String(describing: plan.interaction)),
        gazeTarget=\(String(describing: plan.gazeTarget)),
        intensity=\(plan.intensity),
        styleMode=\(plan.styleMode)
        """
    }
}
