//
//  BackgroundComplexityAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation
import CoreGraphics

public protocol BackgroundComplexityAnalyzing: Sendable {
    func analyze(
        image: VisualImage,
        subjectBoxes: [CGRect],
        saliencyRegions: [RawSaliencyRegion]
    ) async throws -> BackgroundType?
}

public final class MockBackgroundComplexityAnalyzer: BackgroundComplexityAnalyzing {
    public init() {}

    public func analyze(
        image: VisualImage,
        subjectBoxes: [CGRect],
        saliencyRegions: [RawSaliencyRegion]
    ) async throws -> BackgroundType? {
        _ = image
        _ = subjectBoxes
        _ = saliencyRegions
        return nil
    }
}
