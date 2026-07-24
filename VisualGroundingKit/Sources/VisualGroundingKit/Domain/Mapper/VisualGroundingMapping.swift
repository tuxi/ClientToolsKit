//
//  VisualGroundingMapping.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 将底层图片分析结果映射为统一视觉结构化输出
public protocol VisualGroundingMapping: Sendable {
    
    /// 将图片分析描述符映射为 Grounding Payload。
    ///
    /// - Parameter descriptor: 第一阶段图片分析结果
    /// - Returns: VisualGroundingPayload grounding 统一结果
    func map(_ descriptor: ImageDescriptor) -> VisualGroundingPayload
}
