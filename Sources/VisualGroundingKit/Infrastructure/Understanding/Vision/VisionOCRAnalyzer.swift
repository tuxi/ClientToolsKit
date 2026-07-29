//
//  VisionOCRAnalyzer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Vision
import CoreGraphics

public final class VisionOCRAnalyzer: OCRAnalyzing {
    private let performer: VisionImageRequestPerforming

    public init(performer: VisionImageRequestPerforming = VisionImageRequestPerformer()) {
        self.performer = performer
    }

    public func recognize(in image: VisualImage) async throws -> [RecognizedTextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            do {
                var output: [RecognizedTextBlock] = []

                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: VisionAnalyzerError.requestFailed(error.localizedDescription))
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: [])
                        return
                    }

                    output = observations.compactMap { observation in
                        guard let candidate = observation.topCandidates(1).first else {
                            return nil
                        }

                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }

                        return RecognizedTextBlock(
                            text: text,
                            boundingBox: observation.boundingBox
                        )
                    }

                    continuation.resume(returning: output)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                // Dynamic minimum text height: adapts to image pixel dimensions.
                let longEdge = max(image.size.width, image.size.height)
                let dynamicRatio = min(0.02, max(0.001, 14.0 / max(longEdge, 1)))
                request.minimumTextHeight = Float(dynamicRatio)

                try performer.perform([request], on: image)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func recognize(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> [RecognizedTextBlock] {
        _ = image
        return rawVision.recognizedTexts.map {
            RecognizedTextBlock(text: $0.text, boundingBox: $0.boundingBox)
        }
    }
}
