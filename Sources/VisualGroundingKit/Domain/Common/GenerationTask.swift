//
//  GenerationTask.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

/// 生成任务类型。
///
/// 用于标识当前请求最终服务于哪一种生成任务。
/// 后续可以用于：
/// - 区分默认约束策略
/// - 区分后端工作流
/// - 区分 Prompt 编译模板
public enum GenerationTask: String, Sendable, Hashable, Codable {
    /// 图生视频
    case imageToVideo
    
    /// 图生图
    case imageToImage
    
    /// 提示词润色
    case promptPolish
    
    /// 特效模板
    case effectTemplate
}
