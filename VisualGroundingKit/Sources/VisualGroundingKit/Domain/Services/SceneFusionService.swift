//
//  SceneFusionService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public protocol SceneFusionService: Sendable {
    func fuse(_ descriptors: [ImageDescriptor], intent: GenerationIntent) async throws -> CompositeScenePlan
}
