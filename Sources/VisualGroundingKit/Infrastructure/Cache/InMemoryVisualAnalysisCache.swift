//
//  InMemoryPromptCache.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public actor InMemoryVisualAnalysisCache: VisualAnalysisCaching {
    // 当前阶段仅缓存 ImageDescriptor。
    // VisualGroundingPayload 是 descriptor 的纯映射结果，
    // 因此不单独缓存，后续如 grounding 构建逻辑变复杂再考虑独立缓存。
    private var descriptorStore: [String: ImageDescriptor] = [:]
    private var promptStore: [String: VisualPreparationResult] = [:]
    
    public init() {}
    
    public func descriptor(for key: String) async -> ImageDescriptor? {
        descriptorStore[key]
    }
    
    public func saveDescriptor(_ descriptor: ImageDescriptor, for key: String) async {
        descriptorStore[key] = descriptor
    }
    
    public func promptBundle(for key: String) async -> VisualPreparationResult? {
        promptStore[key]
    }
    
    public func savePromptBundle(_ bundle: VisualPreparationResult, for key: String) async {
        promptStore[key] = bundle
    }
}
