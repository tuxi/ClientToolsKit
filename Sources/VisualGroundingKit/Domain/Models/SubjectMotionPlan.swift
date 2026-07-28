//
//  SubjectMotionPlan.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

/// 主体动作计划。
///
/// 作用：
/// - 作为 Grounding / UserIntent 与 motion tokens 之间的中间语义层
/// - 不直接面向最终 Prompt 文本
/// - 不直接承担自然语言表达
///
/// 设计目标：
/// - 比 motion token 更结构化
/// - 比完整 DSL 更轻量
/// - 能表达“主体基本信息 + 起始姿态 + 目标动作 + 辅助动作 / 互动 / 视线”
///
/// 当前原则：
/// - Grounding 决定事实
/// - Factory 决定默认 plan
/// - Mapper 只负责把 plan 落成 token
/// - Composer 只负责把 token 组合成自然语言
public struct SubjectMotionPlan: Sendable, Hashable {
    
    /// 主体类型，例如 person / animal / object
    public var subjectType: String
    
    /// 主体数量
    public var subjectCount: Int
    
    /// 起始姿态
    public var startPose: SubjectStartPose?
    
    /// 主动作
    public var primaryAction: SubjectPrimaryAction?
    
    /// 次动作
    public var secondaryAction: SubjectSecondaryAction?
    
    /// 互动方式
    public var interaction: SubjectInteractionMode?
    
    /// 视线目标
    public var gazeTarget: SubjectGazeTarget?
    
    /// 动作强度
    public var intensity: SubjectMotionIntensity
    
    /// 默认动作模式
    public var styleMode: SubjectMotionStyleMode
    
    public init(
        subjectType: String,
        subjectCount: Int = 1,
        startPose: SubjectStartPose? = nil,
        primaryAction: SubjectPrimaryAction? = nil,
        secondaryAction: SubjectSecondaryAction? = nil,
        interaction: SubjectInteractionMode? = nil,
        gazeTarget: SubjectGazeTarget? = nil,
        intensity: SubjectMotionIntensity = .subtle,
        styleMode: SubjectMotionStyleMode = .safeSubtle
    ) {
        self.subjectType = subjectType
        self.subjectCount = max(subjectCount, 1)
        self.startPose = startPose
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.interaction = interaction
        self.gazeTarget = gazeTarget
        self.intensity = intensity
        self.styleMode = styleMode
    }
}
