//
//  PortraitAttributeAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public struct PortraitAttributeResult: Sendable, Codable, Hashable {
    public let postureType: PortraitPostureType?
    public let portraitFraming: PortraitFramingType?
    public let gender: SubjectGender?
    public let ageLevel: SubjectAgeLevel?

    public init(
        postureType: PortraitPostureType? = nil,
        portraitFraming: PortraitFramingType? = nil,
        gender: SubjectGender? = nil,
        ageLevel: SubjectAgeLevel? = nil
    ) {
        self.postureType = postureType
        self.portraitFraming = portraitFraming
        self.gender = gender
        self.ageLevel = ageLevel
    }
}

public protocol PortraitAttributeAnalyzing: Sendable {
    func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> PortraitAttributeResult
}

public final class MockPortraitAttributeAnalyzer: PortraitAttributeAnalyzing {
    public init() {}

    public func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> PortraitAttributeResult {
        _ = image
        _ = rawVision
        return PortraitAttributeResult()
    }
}
