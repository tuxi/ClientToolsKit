//
//  ImageQualityMeasurer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public protocol ImageQualityMeasuring: Sendable {
    func brightness(of image: VisualImage) async throws -> ImageBrightnessLevel?
    func sharpness(of image: VisualImage) async throws -> ImageSharpnessLevel?
}

public final class MockImageQualityMeasurer: ImageQualityMeasuring {
    public init() {}

    public func brightness(of image: VisualImage) async throws -> ImageBrightnessLevel? {
        _ = image
        return nil
    }

    public func sharpness(of image: VisualImage) async throws -> ImageSharpnessLevel? {
        _ = image
        return nil
    }
}
