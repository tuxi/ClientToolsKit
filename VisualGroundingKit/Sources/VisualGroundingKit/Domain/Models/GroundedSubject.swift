//
//  GroundedSubject.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//
import Foundation
import CoreGraphics

/// 图片中检测到的主体信息。
///
/// 这是 Grounding 层中的“客观事实主体模型”，
/// 只描述图片里已经观察到的内容，不包含用户意图。
public struct GroundedSubject: Sendable {
    
    /// 主体类型
    public let type: String
    
    /// 主体数量
    public let count: Int
    
    /// 核心主体描述
    ///
    /// 例如：
    /// - person
    /// - two people
    /// - adult and child
    /// - one adult and two children
    public let coreDescription: String
    
    /// 单主体年龄提示。
    ///
    /// 例如：
    /// - child
    /// - adult
    public let ageGroupHint: String?
    
    /// 多主体年龄构成提示。
    ///
    /// 例如：
    /// - all_children
    /// - mixed_adult_child
    public let ageCompositionHint: String?
    
    /// 主体姿态
    ///
    /// 例如：
    /// - standing
    /// - sitting
    public let posture: String?
    
    /// 主体动作事实
    ///
    /// 例如：
    /// - group pose
    /// - facing camera
    public let actionHint: String?
    
    /// 主体关系事实
    ///
    /// 例如：
    /// - holding_child
    /// - standing_beside
    public let relationshipHints: [String]
    
    /// 外观特征
    public let appearanceTokens: [String]
    
    /// 边界框（归一化坐标）
    public let boundingBoxes: [CGRect]
    
    public init(
        type: String,
        count: Int,
        coreDescription: String,
        ageGroupHint: String? = nil,
        ageCompositionHint: String? = nil,
        posture: String? = nil,
        actionHint: String? = nil,
        relationshipHints: [String] = [],
        appearanceTokens: [String] = [],
        boundingBoxes: [CGRect] = []
    ) {
        self.type = type
        self.count = count
        self.coreDescription = coreDescription
        self.ageGroupHint = ageGroupHint
        self.ageCompositionHint = ageCompositionHint
        self.posture = posture
        self.actionHint = actionHint
        self.relationshipHints = relationshipHints
        self.appearanceTokens = appearanceTokens
        self.boundingBoxes = boundingBoxes
    }
}
