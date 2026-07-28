//
//  EnvironmentObjectRefiner.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public struct EnvironmentObjectRefineResult: Sendable, Codable, Hashable {
    public let environmentObjects: [String]
    public let sceneRefHints: [String]

    public init(
        environmentObjects: [String] = [],
        sceneRefHints: [String] = []
    ) {
        self.environmentObjects = environmentObjects
        self.sceneRefHints = sceneRefHints
    }
}

public protocol EnvironmentObjectRefining: Sendable {
    func refine(
        background: BackgroundDescriptor?,
        rawVision: RawVisionAnalysis
    ) async throws -> EnvironmentObjectRefineResult
}

public final class MockEnvironmentObjectRefiner: EnvironmentObjectRefining {
    public init() {}

    public func refine(
        background: BackgroundDescriptor?,
        rawVision: RawVisionAnalysis
    ) async throws -> EnvironmentObjectRefineResult {
        _ = rawVision
        return EnvironmentObjectRefineResult(
            environmentObjects: background?.environmentObjects ?? [],
            sceneRefHints: background?.sceneRefHints ?? []
        )
    }
}

