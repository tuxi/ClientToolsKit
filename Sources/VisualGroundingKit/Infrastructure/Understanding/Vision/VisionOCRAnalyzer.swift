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
                // Lower threshold for the standalone path — screenshots and docs are
                // the most common use case when not going through the unified pipeline.
                request.minimumTextHeight = 0.010

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
