//
//  SubjectDetector.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public protocol SubjectDetecting: Sendable {
    func detect(in image: VisualImage) async throws -> [DetectedSubject]
    func detect(
        in image: VisualImage,
        rawVision: RawVisionAnalysis,
        portraitAttributes: PortraitAttributeResult?
    ) async throws -> [DetectedSubject]
}

public extension SubjectDetecting {
    func detect(
        in image: VisualImage,
        rawVision: RawVisionAnalysis,
        portraitAttributes: PortraitAttributeResult? = nil
    ) async throws -> [DetectedSubject] {
        _ = rawVision
        _ = portraitAttributes
        return try await detect(in: image)
    }
}

public final class MockSubjectDetector: SubjectDetecting {
    public init() {}
    
    public func detect(in image: VisualImage) async throws -> [DetectedSubject] {
        [
            DetectedSubject(
                type: .person,
                confidence: 0.92,
                attributes: SubjectAttributes(
                    genderHint: "female",
                    ageGroupHint: "young adult",
                    hair: ["long black hair"],
                    clothing: ["white dress"],
                    accessories: [],
                    colors: ["white"],
                    facialExpression: "calm",
                    identityConsistencyKey: nil,
                    postureType: PortraitPostureType.standing.rawValue,
                    portraitFraming: PortraitFramingType.mediumShot.rawValue
                ),
                pose: PoseDescriptor(
                    posture: "standing",
                    action: nil,
                    facing: "front",
                    handState: nil
                ),
                boundingBox: nil,
                segmentationHint: SegmentationHint(isForegroundClear: true)
            )
        ]
    }

    public func detect(
        in image: VisualImage,
        rawVision: RawVisionAnalysis,
        portraitAttributes: PortraitAttributeResult?
    ) async throws -> [DetectedSubject] {
        _ = rawVision
        _ = portraitAttributes
        return try await detect(in: image)
    }
}
