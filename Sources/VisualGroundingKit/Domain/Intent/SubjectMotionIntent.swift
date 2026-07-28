//
//  SubjectMotionIntent.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 主体运动意图。
///
/// 表达人物或主体“想怎么动”。
public struct SubjectMotionIntent: Sendable {
    /// 主体动作
    ///
    /// 例如：
    /// - subtle body motion
    /// - natural smile
    /// - head turn
    public let motionTokens: [String]
    
    public init(motionTokens: [String] = []) {
        self.motionTokens = motionTokens
    }
}
