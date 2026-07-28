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
    /// objectness-based saliency regions with per-region classifications.
    public let saliencyRegions: [RawSaliencyRegion]
    /// attention-based saliency regions with per-region classifications.
    public let attentionSaliencyRegions: [RawSaliencyRegion]
    /// detected barcodes / QR codes.
    public let barcodes: [RawBarcodeObservation]
    /// center-crop fallback classification when no saliency regions exist.
    public let centerCropClassification: [RawClassificationObservation]
    /// high-level content type hint from Vision classifications, e.g. "screenshot", "document", "photo".
    public let contentTypeHint: String?
    /// Core ML object detector results — bounding boxes with labels and confidence.
    public let detectedObjects: [RawDetectedObject]

    public init(
        faces: [RawFaceObservation] = [],
        humanBodies: [RawHumanBodyObservation] = [],
        recognizedTexts: [RawRecognizedTextObservation] = [],
        classifications: [RawClassificationObservation] = [],
        saliencyRegions: [RawSaliencyRegion] = [],
        attentionSaliencyRegions: [RawSaliencyRegion] = [],
        barcodes: [RawBarcodeObservation] = [],
        centerCropClassification: [RawClassificationObservation] = [],
        contentTypeHint: String? = nil,
        detectedObjects: [RawDetectedObject] = []
    ) {
        self.faces = faces
        self.humanBodies = humanBodies
        self.recognizedTexts = recognizedTexts
        self.classifications = classifications
        self.saliencyRegions = saliencyRegions
        self.attentionSaliencyRegions = attentionSaliencyRegions
        self.barcodes = barcodes
        self.centerCropClassification = centerCropClassification
        self.contentTypeHint = contentTypeHint
        self.detectedObjects = detectedObjects
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

public struct RawBarcodeObservation: Sendable, Codable, Hashable {
    public let payload: String
    public let symbology: String
    public let boundingBox: CGRect

    public init(
        payload: String,
        symbology: String,
        boundingBox: CGRect
    ) {
        self.payload = payload
        self.symbology = symbology
        self.boundingBox = boundingBox
    }
}

/// A single object detected by the Core ML object detector.
///
/// Differs from classification observations in that each entry carries both
/// a label and a precise bounding box — no separate "where is it" pass needed.
public struct RawDetectedObject: Sendable, Codable, Hashable {
    /// Human-readable label, e.g. "cup", "laptop", "keyboard".
    public let label: String
    /// Detection confidence [0, 1].
    public let confidence: Float
    /// Normalized bounding box in [0, 1] coordinate space.
    public let boundingBox: CGRect

    public init(
        label: String,
        confidence: Float,
        boundingBox: CGRect
    ) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}
