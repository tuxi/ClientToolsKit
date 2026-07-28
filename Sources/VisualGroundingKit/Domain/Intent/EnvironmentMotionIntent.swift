//
//  EnvironmentMotionIntent.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 环境动态意图。
///
/// 表达背景环境希望发生的动态效果。
public struct EnvironmentMotionIntent: Sendable {
    /// 环境动态
    ///
    /// 例如：
    /// - leaves_sway
    /// - cloth_flutter
    /// - light_flicker
    public let motionTokens: [String]
    
    public init(motionTokens: [String] = []) {
        self.motionTokens = motionTokens
    }
}
