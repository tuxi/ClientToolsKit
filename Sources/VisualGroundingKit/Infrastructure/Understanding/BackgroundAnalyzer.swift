//
//  BackgroundAnalyzer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation
import Vision

public protocol BackgroundAnalyzing: Sendable {
    func analyze(in image: VisualImage) async throws -> BackgroundDescriptor?
    func analyze(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> BackgroundDescriptor?
}

public extension BackgroundAnalyzing {
    func analyze(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> BackgroundDescriptor? {
        _ = rawVision
        return try await analyze(in: image)
    }
}

public final class MockBackgroundAnalyzer: BackgroundAnalyzing {
    public init() {}
    
    public func analyze(in image: VisualImage) async throws -> BackgroundDescriptor? {
        BackgroundDescriptor(
            sceneType: "garden",
            locationTags: ["sunset garden"],
            environmentObjects: ["flowers"],
            weather: "clear",
            lighting: "warm light",
            timeOfDay: "sunset"
        )
    }

    public func analyze(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> BackgroundDescriptor? {
        _ = image
        _ = rawVision
        return try await analyze(in: image)
    }
}
