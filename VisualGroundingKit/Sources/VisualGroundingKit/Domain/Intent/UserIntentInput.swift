//
//  UserIntentInput.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

/// 用户意图输入。
///
/// 说明：
/// - 用户输入的不是最终 Prompt
/// - 而是“意图输入”
/// - 后续需要与 grounding 和系统约束融合
public struct UserIntentInput: Sendable {
    
    /// 用户原始文本输入。
    ///
    /// 例如：
    /// - 让画面更有电影感，镜头缓慢推进，两个人微笑
    /// - 保持背景不变，人物轻微点头
    public let rawText: String?
    
    /// 是否启用默认自动意图。
    ///
    /// 当用户没有输入时，通常为 true。
    /// 当用户明确手动输入时，也可以保留 true，
    /// 表示允许系统补全低风险默认动态。
    public let enableDefaultIntent: Bool
    
    public init(
        rawText: String? = nil,
        enableDefaultIntent: Bool = true
    ) {
        self.rawText = rawText
        self.enableDefaultIntent = enableDefaultIntent
    }
    
    /// 是否存在有效用户输入
    public var hasUserText: Bool {
        guard let rawText else { return false }
        return !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
