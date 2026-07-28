//
//  VisualAnalysisResult.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation

/// 单张图片的完整分析结果。
///
/// 作用：
/// - 保留底层原始分析结果 `ImageDescriptor`
/// - 保留对外统一结构化结果 `VisualGroundingPayload`
///
/// 说明：
/// - `descriptor` 更偏底层原始检测结果，适合调试和后续继续增强
/// - `visualGrounding` 是对外统一 schema，适合服务端直接消费
public struct VisualAnalysisResult: Sendable, Codable {
    
    /// 原始图片分析结果
    public let descriptor: ImageDescriptor
    
    /// 统一结构化输出结果
    public let visualGrounding: VisualGroundingPayload
    
    public init(
        descriptor: ImageDescriptor,
        visualGrounding: VisualGroundingPayload
    ) {
        self.descriptor = descriptor
        self.visualGrounding = visualGrounding
    }
}
