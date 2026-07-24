//
//  VisionPortraitAttributeAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public final class VisionPortraitAttributeAnalyzer: PortraitAttributeAnalyzing {
    public init() {}

    public func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> PortraitAttributeResult {
        let posture = inferPosture(from: rawVision.humanBodies)
        let framing = inferFraming(image: image, rawVision: rawVision)

        return PortraitAttributeResult(
            postureType: posture,
            portraitFraming: framing
        )
    }
}

private extension VisionPortraitAttributeAnalyzer {
    func inferPosture(from bodies: [RawHumanBodyObservation]) -> PortraitPostureType? {
        guard let body = bodies.first else {
            return nil
        }

        let points = body.recognizedPoints
        let shoulderY = averageY([points["leftShoulder"], points["rightShoulder"]])
        let hipY = averageY([points["leftHip"], points["rightHip"]])
        let kneeY = averageY([points["leftKnee"], points["rightKnee"]])
        let ankleY = averageY([points["leftAnkle"], points["rightAnkle"]])

        guard let shoulderY, let hipY else {
            return .static
        }

        let torsoHeight = abs(shoulderY - hipY)
        if let kneeY, let ankleY {
            let legHeight = abs(hipY - kneeY) + abs(kneeY - ankleY)
            if legHeight > torsoHeight * 0.9 {
                return .standing
            }
            if legHeight < torsoHeight * 0.65 {
                return .sitting
            }
        }

        return .static
    }

    func inferFraming(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) -> PortraitFramingType? {
        _ = image
        let largestFaceArea = rawVision.faces.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0
        let largestBodyArea = rawVision.humanBodies.compactMap(\.boundingBox).map { $0.width * $0.height }.max() ?? 0

        if largestFaceArea >= 0.10 {
            return .closeUp
        }
        if largestBodyArea >= 0.28 || largestFaceArea >= 0.05 {
            return .mediumShot
        }
        if largestBodyArea > 0 {
            return .fullBody
        }
        return nil
    }

    func averageY(_ points: [CGPoint?]) -> CGFloat? {
        let valid = points.compactMap { $0?.y }
        guard !valid.isEmpty else {
            return nil
        }
        return valid.reduce(0, +) / CGFloat(valid.count)
    }
}
