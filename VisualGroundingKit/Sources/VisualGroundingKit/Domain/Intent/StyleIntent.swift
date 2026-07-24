//
//  StyleIntent.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 风格意图。
///
/// 表达用户希望增强或偏向的风格，而不是图片当前已存在的风格。
public struct StyleIntent: Sendable {
    /// 用户期望的风格倾向
    ///
    /// 例如：
    /// - cinematic
    /// - dreamy
    /// - warm
    public let styleTokens: [String]
    
    public init(styleTokens: [String] = []) {
        self.styleTokens = styleTokens
    }
}
