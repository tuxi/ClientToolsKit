//
//  StyleAnalyzer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public protocol StyleAnalyzing: Sendable {
    func analyze(in image: VisualImage) async throws -> StyleDescriptor?
    func analyze(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> StyleDescriptor?
}

public extension StyleAnalyzing {
    func analyze(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> StyleDescriptor? {
        _ = rawVision
        return try await analyze(in: image)
    }
}

public final class MockStyleAnalyzer: StyleAnalyzing {
    public init() {}
    
    public func analyze(in image: VisualImage) async throws -> StyleDescriptor? {
        StyleDescriptor(
            visualStyle: ["cinematic", "realistic"],
            mood: ["dreamy"],
            colorPalette: ["warm tones"],
            renderingHint: ["high detail"]
        )
    }

    public func analyze(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> StyleDescriptor? {
        _ = image
        _ = rawVision
        return try await analyze(in: image)
    }
}
