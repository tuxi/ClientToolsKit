//
//  SubjectMotionPlanParser.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

/// SubjectMotionPlan 解析器。
///
/// 作用：
/// - 将用户自然语言中的动作意图解析为 SubjectMotionPlan
/// - 不直接产出 motion tokens
/// - 不负责最终文案表达
///
/// 当前原则：
/// - 先覆盖高频、强确定性表达
/// - 保持简单、可解释、可测试
/// - 中文英文都支持
///
/// 当前支持：
/// - 起始姿态：坐姿 / 站姿
/// - 主动作：起身 / 起舞 / 转身 / 走动
/// - 次动作：点头 / 挥手
/// - 互动：抱孩子 / 轻微互动
/// - 视线：看向镜头
/// - 从 A 到 B：
///   例如“从坐着到起身”“from sitting to dancing”
public enum SubjectMotionPlanParser {
    
    // MARK: - Public
    
    public static func parseChinese(
        from text: String
    ) -> SubjectMotionPlan? {
        let normalized = normalize(text)
        var plan = emptyChinesePlan()
        
        parseChineseStartPose(into: &plan, text: normalized)
        parseChinesePrimaryAction(into: &plan, text: normalized)
        parseChineseSecondaryAction(into: &plan, text: normalized)
        parseChineseInteraction(into: &plan, text: normalized)
        parseChineseGaze(into: &plan, text: normalized)
        
        guard hasMeaningfulContent(plan) else {
            return nil
        }
        
        return plan
    }
    
    public static func parseEnglish(
        from text: String
    ) -> SubjectMotionPlan? {
        let normalized = normalize(text)
        var plan = emptyEnglishPlan()
        
        parseEnglishStartPose(into: &plan, text: normalized)
        parseEnglishPrimaryAction(into: &plan, text: normalized)
        parseEnglishSecondaryAction(into: &plan, text: normalized)
        parseEnglishInteraction(into: &plan, text: normalized)
        parseEnglishGaze(into: &plan, text: normalized)
        
        guard hasMeaningfulContent(plan) else {
            return nil
        }
        
        return plan
    }
}

// MARK: - Chinese Parsing

private extension SubjectMotionPlanParser {
    
    static func emptyChinesePlan() -> SubjectMotionPlan {
        SubjectMotionPlan(
            subjectType: "person",
            subjectCount: 1,
            startPose: nil,
            primaryAction: nil,
            secondaryAction: nil,
            interaction: nil,
            gazeTarget: nil,
            intensity: .subtle,
            styleMode: .creativeSoft
        )
    }
    
    static func parseChineseStartPose(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        // “从 A 到 B”优先
        if text.contains("从"), text.contains("到") {
            if containsAny(text, keywords: [
                "从盘坐", "从坐着", "从坐姿", "从盘腿坐", "从坐在地上"
            ]) {
                plan.startPose = .seated
                return
            }
            
            if containsAny(text, keywords: [
                "从站着", "从站立", "从站姿"
            ]) {
                plan.startPose = .standing
                return
            }
        }
        
        if containsAny(text, keywords: [
            "盘坐", "坐着", "坐姿", "盘腿坐", "坐在地上"
        ]) {
            plan.startPose = .seated
            return
        }
        
        if containsAny(text, keywords: [
            "站着", "站立", "站姿"
        ]) {
            plan.startPose = .standing
            return
        }
    }
    
    static func parseChinesePrimaryAction(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        if containsAny(text, keywords: [
            "起身", "站起", "慢慢站起来", "缓缓起身"
        ]) {
            plan.primaryAction = .standUp
            return
        }
        
        if containsAny(text, keywords: [
            "起舞", "跳舞", "舞动", "翩翩起舞"
        ]) {
            plan.primaryAction = .dance
            return
        }
        
        if containsAny(text, keywords: [
            "转身", "回头", "侧过身", "转过去"
        ]) {
            plan.primaryAction = .turn
            return
        }
        
        if containsAny(text, keywords: [
            "走动", "慢慢走", "向前走", "走起来"
        ]) {
            plan.primaryAction = .walk
            return
        }
    }
    
    static func parseChineseSecondaryAction(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        // 当前保持一个 secondaryAction，优先点头，其次挥手
        if containsAny(text, keywords: [
            "点头", "轻轻点头"
        ]) {
            plan.secondaryAction = .nod
            return
        }
        
        if containsAny(text, keywords: [
            "挥手", "招手", "轻轻挥手"
        ]) {
            plan.secondaryAction = .wave
            return
        }
    }
    
    static func parseChineseInteraction(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        if containsAny(text, keywords: [
            "抱着孩子", "抱小孩", "怀抱孩子", "抱着小孩"
        ]) {
            plan.interaction = .holdingChild
            return
        }
        
        if containsAny(text, keywords: [
            "轻微互动", "自然互动", "轻轻互动"
        ]) {
            plan.interaction = .subtleInteraction
            return
        }
    }
    
    static func parseChineseGaze(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        if containsAny(text, keywords: [
            "看向镜头", "望向镜头", "看着镜头", "望着镜头"
        ]) {
            plan.gazeTarget = .camera
            return
        }
    }
}

// MARK: - English Parsing

private extension SubjectMotionPlanParser {
    
    static func emptyEnglishPlan() -> SubjectMotionPlan {
        SubjectMotionPlan(
            subjectType: "person",
            subjectCount: 1,
            startPose: nil,
            primaryAction: nil,
            secondaryAction: nil,
            interaction: nil,
            gazeTarget: nil,
            intensity: .subtle,
            styleMode: .creativeSoft
        )
    }
    
    static func parseEnglishStartPose(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        // “from A to B” 优先
        if text.contains("from"), text.contains("to") {
            if containsAny(text, keywords: [
                "from sitting", "from seated", "from a seated pose"
            ]) {
                plan.startPose = .seated
                return
            }
            
            if containsAny(text, keywords: [
                "from standing", "from a standing pose"
            ]) {
                plan.startPose = .standing
                return
            }
        }
        
        if containsAny(text, keywords: [
            "sitting", "seated", "seated pose"
        ]) {
            plan.startPose = .seated
            return
        }
        
        if containsAny(text, keywords: [
            "standing", "standing pose"
        ]) {
            plan.startPose = .standing
            return
        }
    }
    
    static func parseEnglishPrimaryAction(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        if containsAny(text, keywords: [
            "stand up", "standing up", "rise up", "rise gently"
        ]) {
            plan.primaryAction = .standUp
            return
        }
        
        if containsAny(text, keywords: [
            "dance", "dancing", "begin to dance"
        ]) {
            plan.primaryAction = .dance
            return
        }
        
        if containsAny(text, keywords: [
            "turn around", "turning", "turn gently"
        ]) {
            plan.primaryAction = .turn
            return
        }
        
        if containsAny(text, keywords: [
            "walk", "walking", "walk forward"
        ]) {
            plan.primaryAction = .walk
            return
        }
    }
    
    static func parseEnglishSecondaryAction(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        if containsAny(text, keywords: [
            "nod", "slight nod", "nod gently"
        ]) {
            plan.secondaryAction = .nod
            return
        }
        
        if containsAny(text, keywords: [
            "wave", "wave hand", "waving", "wave gently"
        ]) {
            plan.secondaryAction = .wave
            return
        }
    }
    
    static func parseEnglishInteraction(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        if containsAny(text, keywords: [
            "holding child", "hold a child", "holding a child", "carry a child"
        ]) {
            plan.interaction = .holdingChild
            return
        }
        
        if containsAny(text, keywords: [
            "subtle interaction", "gentle interaction", "interact gently"
        ]) {
            plan.interaction = .subtleInteraction
            return
        }
    }
    
    static func parseEnglishGaze(
        into plan: inout SubjectMotionPlan,
        text: String
    ) {
        if containsAny(text, keywords: [
            "look at camera", "look at the camera", "looking at camera", "looking at the camera"
        ]) {
            plan.gazeTarget = .camera
            return
        }
    }
}

// MARK: - Helpers

private extension SubjectMotionPlanParser {
    
    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: "：", with: ",")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func containsAny(
        _ text: String,
        keywords: [String]
    ) -> Bool {
        keywords.contains { text.contains($0) }
    }
    
    static func hasMeaningfulContent(_ plan: SubjectMotionPlan) -> Bool {
        plan.startPose != nil ||
        plan.primaryAction != nil ||
        plan.secondaryAction != nil ||
        plan.interaction != nil ||
        plan.gazeTarget != nil
    }
}
