import CoreGraphics
import Foundation

#if canImport(Vision)
import Vision
#endif

/// Raw Vision observations consumed by `InspectUIImageTool`.
///
/// Bounding boxes stay in Vision's normalized bottom-left space; the tool
/// converts them to the `ui_evidence.v1` top-left space.
struct UIVisionObservations: Sendable {
    var textBlocks: [UIVisionText] = []
    var rectangles: [UIVisionRectangle] = []
    var warnings: [String] = []
}

struct UIVisionText: Sendable {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

struct UIVisionRectangle: Sendable {
    let boundingBox: CGRect
    let confidence: Float
}

protocol UIEvidenceVisionProviding: Sendable {
    func analyze(image: CGImage) throws -> UIVisionObservations
}

enum UIEvidenceVisionError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

/// Apple Vision implementation: text recognition plus rectangle detection.
///
/// Requests run independently so a rectangle failure does not discard text
/// evidence. Failures are reported as warnings and degrade the evidence.
struct AppleUIVisionEvidenceProvider: UIEvidenceVisionProviding {
    func analyze(image: CGImage) throws -> UIVisionObservations {
        #if canImport(Vision)
        var output = UIVisionObservations()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        let longEdge = CGFloat(max(image.width, image.height))
        textRequest.minimumTextHeight = Float(min(0.02, max(0.001, 14.0 / max(longEdge, 1))))

        do {
            try handler.perform([textRequest])
            output.textBlocks = (textRequest.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return UIVisionText(
                    text: text,
                    boundingBox: observation.boundingBox,
                    confidence: candidate.confidence
                )
            }
        } catch {
            output.warnings.append("Vision text recognition failed: \(error.localizedDescription)")
        }

        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 80
        rectangleRequest.minimumAspectRatio = 0.1
        rectangleRequest.minimumSize = 0.02
        rectangleRequest.minimumConfidence = 0.3
        rectangleRequest.quadratureTolerance = 30

        do {
            try handler.perform([rectangleRequest])
            output.rectangles = (rectangleRequest.results ?? []).map { observation in
                UIVisionRectangle(
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence
                )
            }
        } catch {
            output.warnings.append("Vision rectangle detection failed: \(error.localizedDescription)")
        }

        if output.textBlocks.isEmpty && output.rectangles.isEmpty && !output.warnings.isEmpty {
            throw UIEvidenceVisionError.unavailable(output.warnings.joined(separator: " "))
        }

        return output
        #else
        throw UIEvidenceVisionError.unavailable(
            "Vision framework is not available on this platform, so UI evidence is limited to source identity."
        )
        #endif
    }
}
