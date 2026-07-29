//
//  VisionRawObservationAnalyzer.swift
//  VisualGroundingKit
//
//  Unified Vision pipeline — one handler for primary requests,
//  one handler for batched ROI classifications.
//

import Foundation
import Vision

// MARK: - Analyzer

public final class VisionRawObservationAnalyzer: RawVisionAnalyzing {
    private let performer: VisionImageRequestPerforming
    private let objectDetector: CoreMLObjectDetector

    public init(
        performer: VisionImageRequestPerforming = VisionImageRequestPerformer(),
        objectDetector: CoreMLObjectDetector = CoreMLObjectDetector()
    ) {
        self.performer = performer
        self.objectDetector = objectDetector
    }

    // MARK: - Unified Analysis

    public func analyze(
        in image: VisualImage,
        profile: AnalysisProfile = .generationGrounding
    ) async throws -> RawVisionAnalysis {

        // --- Phase 1: all primary requests in a single handler ---

        let faceRequest = VNDetectFaceRectanglesRequest()
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let textRequest = makeTextRequest(profile: profile, imageSize: image.size)
        let classifyRequest = VNClassifyImageRequest()
        let objectnessSaliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        let attentionSaliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let barcodeRequest = VNDetectBarcodesRequest()

        // Core ML object detector — conditionally included.
        let detectorRequest: VNCoreMLRequest?
        if CoreMLObjectDetector.shouldRun(profile: profile, contentTypeHint: nil) {
            detectorRequest = try? objectDetector.makeRequest()
        } else {
            detectorRequest = nil
        }

        var primaryRequests: [VNRequest] = [
            faceRequest,
            bodyRequest,
            textRequest,
            classifyRequest,
            objectnessSaliencyRequest,
            attentionSaliencyRequest,
            barcodeRequest
        ]
        if let dr = detectorRequest {
            primaryRequests.append(dr)
        }

        try performer.perform(primaryRequests, on: image)

        // Extract primary results
        let faces = extractFaces(from: faceRequest)
        let humanBodies = extractBodies(from: bodyRequest)
        let recognizedTexts = extractTexts(from: textRequest)
        let fullImageClassifications = extractClassifications(
            from: classifyRequest,
            maxCount: profile == .agentCompact ? 5 : 12,
            source: "full_image"
        )
        let objectnessRegions = extractSaliencyRegions(from: objectnessSaliencyRequest)
        let attentionRegions = extractSaliencyRegions(from: attentionSaliencyRequest)
        let barcodes = extractBarcodes(from: barcodeRequest)

        // Parse Core ML detection results
        let detectedObjects: [RawDetectedObject]
        if let dr = detectorRequest {
            detectedObjects = objectDetector.parseResults(from: dr)
        } else {
            detectedObjects = []
        }

        // Merge and deduplicate saliency regions
        let mergedRawRegions = mergeSaliencyRegions(
            objectness: objectnessRegions,
            attention: attentionRegions,
            maxRegions: 3
        )

        // --- Phase 2: batched ROI classifications in a single handler ---

        var objectnessClassified: [RawSaliencyRegion] = []
        var attentionClassified: [RawSaliencyRegion] = []
        var centerCropClassification: [RawClassificationObservation] = []

        if !mergedRawRegions.isEmpty {
            // Build one classify request per region, all in one handler
            let roiRequests: [VNClassifyImageRequest] = mergedRawRegions.map { box in
                let expandedBox = expandBoundingBox(box, by: 0.12)
                let request = VNClassifyImageRequest()
                request.regionOfInterest = clampROI(expandedBox)
                return request
            }

            if !roiRequests.isEmpty {
                do {
                    try performer.perform(roiRequests, on: image)
                } catch {
                    DLLog("Batched ROI classification error (non-fatal):", error.localizedDescription)
                }
            }

            // Map results back to regions
            let roiResults: [[RawClassificationObservation]] = roiRequests.map { request in
                let raw = request.results ?? []
                return Array(raw.prefix(profile == .agentCompact ? 5 : 8)).map {
                    RawClassificationObservation(
                        identifier: $0.identifier,
                        confidence: $0.confidence,
                        source: "" // filled below
                    )
                }
            }

            // Distribute: alternate objectness/attention, label sources
            for (index, (box, classifications)) in zip(mergedRawRegions, roiResults).enumerated() {
                let sourceLabel: String
                if index < objectnessRegions.count && index < attentionRegions.count {
                    sourceLabel = index.isMultiple(of: 2) ? "objectness_roi_\(index / 2)" : "attention_roi_\(index / 2)"
                } else if index < objectnessRegions.count {
                    sourceLabel = "objectness_roi_\(index)"
                } else {
                    sourceLabel = "attention_roi_\(index - objectnessRegions.count)"
                }

                let labeled = classifications.map { obs in
                    RawClassificationObservation(
                        identifier: obs.identifier,
                        confidence: obs.confidence,
                        source: sourceLabel
                    )
                }

                // Heuristic: objectness regions are first in the merged list
                if index < objectnessRegions.count {
                    objectnessClassified.append(
                        RawSaliencyRegion(
                            boundingBox: box,
                            confidence: objectnessRegions[min(index, objectnessRegions.count - 1)].confidence,
                            classifications: labeled
                        )
                    )
                } else {
                    attentionClassified.append(
                        RawSaliencyRegion(
                            boundingBox: box,
                            confidence: nil,
                            classifications: labeled
                        )
                    )
                }
            }
        } else {
            // Center crop fallback when no saliency regions exist
            centerCropClassification = classifyCenterCrop(in: image, profile: profile)
        }

        // Infer content type hint from full-image classifications
        let contentTypeHint = inferContentTypeHint(from: fullImageClassifications)

        return RawVisionAnalysis(
            faces: faces,
            humanBodies: humanBodies,
            recognizedTexts: recognizedTexts,
            classifications: fullImageClassifications,
            saliencyRegions: objectnessClassified,
            attentionSaliencyRegions: attentionClassified,
            barcodes: barcodes,
            centerCropClassification: centerCropClassification,
            contentTypeHint: contentTypeHint,
            detectedObjects: detectedObjects
        )
    }
}

// MARK: - Phase 1 Extractors

private extension VisionRawObservationAnalyzer {

    func extractFaces(from request: VNDetectFaceRectanglesRequest) -> [RawFaceObservation] {
        (request.results ?? []).map {
            RawFaceObservation(boundingBox: $0.boundingBox, confidence: $0.confidence)
        }
    }

    func extractBodies(from request: VNDetectHumanBodyPoseRequest) -> [RawHumanBodyObservation] {
        (request.results ?? []).map { observation in
            RawHumanBodyObservation(
                boundingBox: makeBoundingBox(from: observation),
                confidence: observation.confidence,
                recognizedPoints: makeRecognizedPointDictionary(from: observation)
            )
        }
    }

    func extractTexts(from request: VNRecognizeTextRequest) -> [RawRecognizedTextObservation] {
        (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return RawRecognizedTextObservation(
                text: text,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }

    func extractClassifications(
        from request: VNClassifyImageRequest,
        maxCount: Int,
        source: String
    ) -> [RawClassificationObservation] {
        Array((request.results ?? []).prefix(maxCount)).map {
            RawClassificationObservation(
                identifier: $0.identifier,
                confidence: $0.confidence,
                source: source
            )
        }
    }

    func extractSaliencyRegions(
        from request: VNGenerateObjectnessBasedSaliencyImageRequest
    ) -> [RawSaliencyRegion] {
        guard let observation = request.results?.first else { return [] }
        return (observation.salientObjects ?? []).map { region in
            RawSaliencyRegion(
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                classifications: []
            )
        }
    }

    func extractSaliencyRegions(
        from request: VNGenerateAttentionBasedSaliencyImageRequest
    ) -> [RawSaliencyRegion] {
        guard let observation = request.results?.first else { return [] }
        return (observation.salientObjects ?? []).map { region in
            RawSaliencyRegion(
                boundingBox: region.boundingBox,
                confidence: region.confidence,
                classifications: []
            )
        }
    }

    func extractBarcodes(from request: VNDetectBarcodesRequest) -> [RawBarcodeObservation] {
        (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue else { return nil }
            return RawBarcodeObservation(
                payload: payload,
                symbology: observation.symbology.rawValue,
                boundingBox: observation.boundingBox
            )
        }
    }
}

// MARK: - Saliency Region Merging

private extension VisionRawObservationAnalyzer {

    /// Minimum IoU to consider two saliency regions as overlapping.
    private static let saliencyIoUThreshold: CGFloat = 0.45

    func mergeSaliencyRegions(
        objectness: [RawSaliencyRegion],
        attention: [RawSaliencyRegion],
        maxRegions: Int
    ) -> [CGRect] {
        var boxes: [CGRect] = []

        // Prioritize objectness boxes first, then attention
        for region in objectness where region.confidence ?? 0 > 0.1 {
            boxes.append(region.boundingBox)
        }
        for region in attention where region.confidence ?? 0 > 0.1 {
            boxes.append(region.boundingBox)
        }

        guard !boxes.isEmpty else { return [] }

        // Deduplicate by IoU
        var merged: [CGRect] = []
        for box in boxes {
            let overlaps = merged.contains { iou($0, box) >= Self.saliencyIoUThreshold }
            if !overlaps {
                merged.append(box)
                if merged.count >= maxRegions { break }
            }
        }

        return merged
    }

    func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let unionArea = a.width * a.height + b.width * b.height - intersection.width * intersection.height
        guard unionArea > 0 else { return 0 }
        return (intersection.width * intersection.height) / unionArea
    }
}

// MARK: - ROI Helpers

private extension VisionRawObservationAnalyzer {

    /// Expand bounding box outward by `ratio` (e.g. 0.12 → 12% each side).
    func expandBoundingBox(_ box: CGRect, by ratio: CGFloat) -> CGRect {
        let dw = box.width * ratio
        let dh = box.height * ratio
        return CGRect(
            x: box.origin.x - dw,
            y: box.origin.y - dh,
            width: box.width + 2 * dw,
            height: box.height + 2 * dh
        )
    }

    /// Clamp ROI to [0, 1] coordinate space.
    func clampROI(_ rect: CGRect) -> CGRect {
        let x = max(0, rect.origin.x)
        let y = max(0, rect.origin.y)
        let w = min(1 - x, max(0, rect.size.width))
        let h = min(1 - y, max(0, rect.size.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Center crop classification fallback.
    func classifyCenterCrop(
        in image: VisualImage,
        profile: AnalysisProfile
    ) -> [RawClassificationObservation] {
        // Center 60% of the image
        let centerROI = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let request = VNClassifyImageRequest()
        request.regionOfInterest = centerROI
        do {
            try performer.perform([request], on: image)
            let maxCount = profile == .agentCompact ? 5 : 8
            return Array((request.results ?? []).prefix(maxCount)).map {
                RawClassificationObservation(
                    identifier: $0.identifier,
                    confidence: $0.confidence,
                    source: "center_crop"
                )
            }
        } catch {
            DLLog("Center crop classification unavailable:", error.localizedDescription)
            return []
        }
    }

    /// Infer a high-level content type hint from full-image classifications.
    func inferContentTypeHint(from classifications: [RawClassificationObservation]) -> String? {
        let identifiers = Set(classifications.map { $0.identifier.lowercased() })

        // Screenshot-like
        let screenKeywords = ["screenshot", "webpage", "website", "menu", "document", "ui", "interface"]
        if identifiers.contains(where: { id in screenKeywords.contains { id.contains($0) } }) {
            return "screenshot"
        }

        // Text/document heavy
        let textKeywords = ["text", "document", "book jacket", "newspaper", "magazine"]
        if identifiers.contains(where: { id in textKeywords.contains { id.contains($0) } }) {
            return "text_heavy"
        }

        // Outdoor
        let outdoorKeywords = ["outdoor", "landscape", "nature", "mountain", "beach", "forest", "garden", "sky", "sea"]
        let outdoorHits = identifiers.filter { id in outdoorKeywords.contains { id.contains($0) } }
        if outdoorHits.count >= 2 {
            return "photo"
        }

        // Indoor
        let indoorKeywords = ["indoor", "room", "bedroom", "living room", "kitchen", "office"]
        if identifiers.contains(where: { id in indoorKeywords.contains { id.contains($0) } }) {
            return "photo"
        }

        return nil
    }
}

// MARK: - OCR Configuration

private extension VisionRawObservationAnalyzer {

    func makeTextRequest(
        profile: AnalysisProfile,
        imageSize: CGSize
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        // Dynamic minimum text height: adapts to image pixel dimensions so
        // text that is ~14 px tall is detectable on very large images
        // (e.g. scanned newspapers at 8192 px) while keeping noise low
        // on normal-sized photos.
        let longEdge = max(imageSize.width, imageSize.height)
        let baseAbsoluteHeight: CGFloat = 14  // ~14 px = roughly 10 pt text
        let dynamicRatio = baseAbsoluteHeight / max(longEdge, 1)
        // Clamp: no lower than 0.001 (1 in 1000 px), no higher than 0.02.
        let ratio = min(0.02, max(0.001, dynamicRatio))

        switch profile {
        case .agentCompact:
            // Agent path uses dynamic ratio for screenshots and documents.
            request.minimumTextHeight = Float(ratio)
        case .generationGrounding, .debug:
            // Generation path also benefits from dynamic sizing for photos.
            request.minimumTextHeight = Float(max(ratio, 0.012))
        }

        return request
    }
}

// MARK: - Body Pose Helpers

private extension VisionRawObservationAnalyzer {

    func makeRecognizedPointDictionary(
        from observation: VNHumanBodyPoseObservation
    ) -> [String: CGPoint] {
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }
        var output: [String: CGPoint] = [:]
        output.reserveCapacity(points.count)
        for (joint, point) in points where point.confidence > 0 {
            output[String(describing: joint)] = CGPoint(x: point.x, y: point.y)
        }
        return output
    }

    func makeBoundingBox(from observation: VNHumanBodyPoseObservation) -> CGRect? {
        let points = makeRecognizedPointDictionary(from: observation).values
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(
            x: minX, y: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0)
        )
    }
}

// MARK: - Mock

public final class MockRawVisionAnalyzer: RawVisionAnalyzing {
    public init() {}

    public func analyze(in image: VisualImage) async throws -> RawVisionAnalysis {
        _ = image
        return RawVisionAnalysis()
    }

    public func analyze(
        in image: VisualImage,
        profile: AnalysisProfile
    ) async throws -> RawVisionAnalysis {
        _ = image
        _ = profile
        return RawVisionAnalysis()
    }
}
