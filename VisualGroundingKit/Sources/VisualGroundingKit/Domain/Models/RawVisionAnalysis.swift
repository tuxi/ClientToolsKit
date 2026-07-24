//
//  RawVisionAnalysis.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation
import CoreGraphics

public struct RawVisionAnalysis: Sendable, Codable, Hashable {
    public let faces: [RawFaceObservation]
    public let humanBodies: [RawHumanBodyObservation]
    public let recognizedTexts: [RawRecognizedTextObservation]
    public let classifications: [RawClassificationObservation]
    public let saliencyRegions: [RawSaliencyRegion]

    public init(
        faces: [RawFaceObservation] = [],
        humanBodies: [RawHumanBodyObservation] = [],
        recognizedTexts: [RawRecognizedTextObservation] = [],
        classifications: [RawClassificationObservation] = [],
        saliencyRegions: [RawSaliencyRegion] = []
    ) {
        self.faces = faces
        self.humanBodies = humanBodies
        self.recognizedTexts = recognizedTexts
        self.classifications = classifications
        self.saliencyRegions = saliencyRegions
    }
}

public struct RawFaceObservation: Sendable, Codable, Hashable {
    public let boundingBox: CGRect
    public let confidence: Float?

    public init(
        boundingBox: CGRect,
        confidence: Float? = nil
    ) {
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

public struct RawHumanBodyObservation: Sendable, Codable, Hashable {
    public let boundingBox: CGRect?
    public let confidence: Float?
    public let recognizedPoints: [String: CGPoint]

    public init(
        boundingBox: CGRect? = nil,
        confidence: Float? = nil,
        recognizedPoints: [String: CGPoint] = [:]
    ) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.recognizedPoints = recognizedPoints
    }
}

public struct RawRecognizedTextObservation: Sendable, Codable, Hashable {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float?

    public init(
        text: String,
        boundingBox: CGRect,
        confidence: Float? = nil
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

public struct RawClassificationObservation: Sendable, Codable, Hashable {
    public let identifier: String
    public let confidence: Float
    public let source: String?

    public init(
        identifier: String,
        confidence: Float,
        source: String? = nil
    ) {
        self.identifier = identifier
        self.confidence = confidence
        self.source = source
    }
}

public struct RawSaliencyRegion: Sendable, Codable, Hashable {
    public let boundingBox: CGRect
    public let confidence: Float?
    public let classifications: [RawClassificationObservation]

    public init(
        boundingBox: CGRect,
        confidence: Float? = nil,
        classifications: [RawClassificationObservation] = []
    ) {
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.classifications = classifications
    }
}
