//
//  RawVisionAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public protocol RawVisionAnalyzing: Sendable {
    func analyze(in image: VisualImage) async throws -> RawVisionAnalysis
}

public final class MockRawVisionAnalyzer: RawVisionAnalyzing {
    public init() {}

    public func analyze(in image: VisualImage) async throws -> RawVisionAnalysis {
        _ = image
        return RawVisionAnalysis()
    }
}
