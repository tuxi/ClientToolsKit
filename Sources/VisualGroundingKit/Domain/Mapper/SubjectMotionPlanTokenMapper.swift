//
//  SubjectMotionPlanTokenMapper.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

/// SubjectMotionPlan -> motion tokens 映射器。
///
/// 作用：
/// - 将结构化 SubjectMotionPlan 落成统一 token
/// - 给后续 SubjectMotionPhraseComposer / PromptCompilation 使用
///
/// 设计原则：
/// - token 生成规则集中在这一层
/// - 不在别处重复拼 token
/// - 不猜主体信息，只消费 plan 已有信息
/// - 强动作优先，弱动作只做必要补足
public enum SubjectMotionPlanTokenMapper {
    
    // MARK: - Public
    
    public static func makeTokens(from plan: SubjectMotionPlan) -> [String] {
        var tokens: [String] = []
        
        tokens.append(contentsOf: makeStartPoseTokens(from: plan))
        tokens.append(contentsOf: makePrimaryActionTokens(from: plan))
        tokens.append(contentsOf: makeSecondaryActionTokens(from: plan))
        tokens.append(contentsOf: makeInteractionTokens(from: plan))
        tokens.append(contentsOf: makeGazeTokens(from: plan))
        tokens.append(contentsOf: makeFallbackMotionTokens(from: plan))
        
        return dedupTokens(tokens)
    }
}

// MARK: - Base Mapping

private extension SubjectMotionPlanTokenMapper {
    
    static func makeStartPoseTokens(from plan: SubjectMotionPlan) -> [String] {
        guard let startPose = plan.startPose else { return [] }
        
        switch startPose {
        case .seated:
            return ["start seated pose"]
        case .standing:
            return ["start standing pose"]
        }
    }
    
    static func makePrimaryActionTokens(from plan: SubjectMotionPlan) -> [String] {
        guard let primaryAction = plan.primaryAction else { return [] }
        
        switch primaryAction {
        case .idle:
            return []
        case .standUp:
            return ["stand up motion"]
        case .dance:
            return ["dance motion"]
        case .turn:
            return ["turning motion"]
        case .walk:
            return ["walking motion"]
        }
    }
    
    static func makeSecondaryActionTokens(from plan: SubjectMotionPlan) -> [String] {
        guard let secondaryAction = plan.secondaryAction else { return [] }
        
        switch secondaryAction {
        case .nod:
            return ["subtle nod"]
        case .wave:
            return ["wave hand"]
        }
    }
    
    static func makeInteractionTokens(from plan: SubjectMotionPlan) -> [String] {
        guard let interaction = plan.interaction else { return [] }
        
        switch interaction {
        case .subtleInteraction:
            if plan.subjectCount >= 2 {
                return ["subtle interaction", "subtle group motion"]
            } else {
                return ["subtle interaction"]
            }
            
        case .holdingChild:
            return ["holding child pose"]
        }
    }
    
    static func makeGazeTokens(from plan: SubjectMotionPlan) -> [String] {
        guard let gazeTarget = plan.gazeTarget else { return [] }
        
        switch gazeTarget {
        case .camera:
            return ["look at camera"]
        case .forward:
            return []
        }
    }
}

// MARK: - Fallback

private extension SubjectMotionPlanTokenMapper {
    
    /// 补默认弱动作。
    ///
    /// 规则：
    /// - 有 primaryAction 时，不再补默认姿态动作
    /// - secondary/gaze/holdingChild 可以补一个轻动作兜底
    /// - subtleInteraction 若已带 group token，不重复补
    /// - 完全无动作时，根据起始姿态和人数补基础弱动作
    static func makeFallbackMotionTokens(from plan: SubjectMotionPlan) -> [String] {
        if hasPrimaryAction(plan) {
            return []
        }
        
        if plan.secondaryAction != nil {
            return fallbackByPlan(plan)
        }
        
        if plan.gazeTarget != nil {
            return fallbackByPlan(plan)
        }
        
        if case .holdingChild? = plan.interaction {
            return fallbackByPlan(plan)
        }
        
        if case .subtleInteraction? = plan.interaction {
            if plan.subjectCount >= 2 {
                return []
            }
            return fallbackByPlan(plan)
        }
        
        return fallbackByPlan(plan)
    }
    
    static func fallbackByPlan(_ plan: SubjectMotionPlan) -> [String] {
        switch plan.startPose {
        case .seated:
            return plan.subjectCount >= 2
                ? ["subtle seated group motion"]
                : ["subtle seated motion"]
                
        case .standing:
            return plan.subjectCount >= 2
                ? ["subtle group motion"]
                : ["subtle standing motion"]
                
        case nil:
            return plan.subjectCount >= 2
                ? ["subtle group motion"]
                : fallbackForUnknownPose(plan)
        }
    }
    
    static func fallbackForUnknownPose(_ plan: SubjectMotionPlan) -> [String] {
        switch plan.subjectType.lowercased() {
        case "animal":
            return ["subtle natural motion"]
        case "person":
            return ["subtle body motion"]
        default:
            return []
        }
    }
}

// MARK: - Helpers

private extension SubjectMotionPlanTokenMapper {
    
    static func hasPrimaryAction(_ plan: SubjectMotionPlan) -> Bool {
        guard let primaryAction = plan.primaryAction else { return false }
        return primaryAction != .idle
    }
    
    static func dedupTokens(_ tokens: [String]) -> [String] {
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
