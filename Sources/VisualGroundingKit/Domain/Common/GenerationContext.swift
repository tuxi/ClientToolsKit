//
//  GenerationContext.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

/// 当前视觉结构化请求所服务的生成上下文。
///
/// 由调用侧显式传入，用于把任务类型与工具模式透传给服务端。
public struct GenerationContext: Sendable, Hashable, Codable {
    
    public let task: GenerationTask
    public let toolRouteKey: String?
    public let toolModeKey: String?
    public let toolModeTitle: String?
    public let workflowName: String?
    
    public init(
        task: GenerationTask,
        toolRouteKey: String? = nil,
        toolModeKey: String? = nil,
        toolModeTitle: String? = nil,
        workflowName: String? = nil
    ) {
        self.task = task
        self.toolRouteKey = toolRouteKey
        self.toolModeKey = toolModeKey
        self.toolModeTitle = toolModeTitle
        self.workflowName = workflowName
    }
}
