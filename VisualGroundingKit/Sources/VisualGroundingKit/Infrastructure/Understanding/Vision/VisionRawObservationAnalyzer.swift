//
//  VisionRawObservationAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation
import Vision

public final class VisionRawObservationAnalyzer: RawVisionAnalyzing {
    private let performer: VisionImageRequestPerforming

    public init(performer: VisionImageRequestPerforming = VisionImageRequestPerformer()) {
        self.performer = performer
    }

    public func analyze(in image: VisualImage) async throws -> RawVisionAnalysis {
        async let faces = detectFaces(in: image)
        async let humanBodies = detectBodyPoses(in: image)
        async let recognizedTexts = recognizeTexts(in: image)
        async let classifications = classifyImage(in: image)
        async let saliencyRegions = detectSalientRegions(in: image)

        return RawVisionAnalysis(
            faces: try await faces,
            humanBodies: try await humanBodies,
            recognizedTexts: try await recognizedTexts,
            classifications: try await classifications,
            saliencyRegions: try await saliencyRegions
        )
    }
}

private extension VisionRawObservationAnalyzer {
    func detectFaces(in image: VisualImage) async throws -> [RawFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try performer.perform([request], on: image)
            return (request.results ?? []).map {
                RawFaceObservation(
                    boundingBox: $0.boundingBox,
                    confidence: $0.confidence
                )
            }
        } catch {
            DLLog("人脸检测不可用，降级为空结果:", error.localizedDescription)
            return []
        }
    }

    func detectBodyPoses(in image: VisualImage) async throws -> [RawHumanBodyObservation] {
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try performer.perform([request], on: image)
            return (request.results ?? []).map { observation in
                RawHumanBodyObservation(
                    boundingBox: self.makeBoundingBox(from: observation),
                    confidence: observation.confidence,
                    recognizedPoints: self.makeRecognizedPointDictionary(from: observation)
                )
            }
        } catch {
            DLLog("人体姿态检测不可用，降级为空结果:", error.localizedDescription)
            return []
        }
    }

    func recognizeTexts(in image: VisualImage) async throws -> [RawRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.02

        do {
            try performer.perform([request], on: image)
            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return nil
                }
                return RawRecognizedTextObservation(
                    text: text,
                    boundingBox: observation.boundingBox,
                    confidence: candidate.confidence
                )
            }
        } catch {
            DLLog("OCR 不可用，降级为空结果:", error.localizedDescription)
            return []
        }
    }

    func classifyImage(in image: VisualImage) async throws -> [RawClassificationObservation] {
        let request = VNClassifyImageRequest()
        do {
            try performer.perform([request], on: image)
            return Array((request.results ?? []).prefix(12)).map {
                RawClassificationObservation(
                    identifier: $0.identifier,
                    confidence: $0.confidence,
                    source: "full_image"
                )
            }
        } catch {
            DLLog("图片分类不可用，降级为空结果:", error.localizedDescription)
            return []
        }
    }

    func detectSalientRegions(in image: VisualImage) async throws -> [RawSaliencyRegion] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        do {
            try performer.perform([request], on: image)
            guard let observation = request.results?.first else {
                return []
            }

            let regions = Array((observation.salientObjects ?? []).prefix(3))
            return regions.enumerated().map { index, region in
                let classifications = classifyRegion(
                    region.boundingBox,
                    index: index,
                    in: image
                )
                return RawSaliencyRegion(
                    boundingBox: region.boundingBox,
                    confidence: region.confidence,
                    classifications: classifications
                )
            }
        } catch {
            DLLog("显著区域检测不可用，降级为整图分类:", error.localizedDescription)
            return []
        }
    }

    func classifyRegion(
        _ regionOfInterest: CGRect,
        index: Int,
        in image: VisualImage
    ) -> [RawClassificationObservation] {
        let request = VNClassifyImageRequest()
        request.regionOfInterest = regionOfInterest
        do {
            try performer.perform([request], on: image)
            return Array((request.results ?? []).prefix(8)).map {
                RawClassificationObservation(
                    identifier: $0.identifier,
                    confidence: $0.confidence,
                    source: "saliency_\(index)"
                )
            }
        } catch {
            DLLog("显著区域分类不可用，忽略该区域:", error.localizedDescription)
            return []
        }
    }

    func makeRecognizedPointDictionary(
        from observation: VNHumanBodyPoseObservation
    ) -> [String: CGPoint] {
        guard let points = try? observation.recognizedPoints(.all) else {
            return [:]
        }

        var output: [String: CGPoint] = [:]
        output.reserveCapacity(points.count)

        for (joint, point) in points where point.confidence > 0 {
            output[String(describing: joint)] = CGPoint(x: point.x, y: point.y)
        }

        return output
    }

    func makeBoundingBox(from observation: VNHumanBodyPoseObservation) -> CGRect? {
        let points = makeRecognizedPointDictionary(from: observation).values
        guard !points.isEmpty else {
            return nil
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)

        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0)
        )
    }
}
