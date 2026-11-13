import CoreGraphics
import Foundation

#if canImport(Vision)
import Vision
#endif

/// OCR level used by `inspect_ui_image`.
enum UIEvidenceOCRMode: String, Sendable, CaseIterable {
    /// Bounded accurate attempt; falls back to fast when it cannot finish.
    case auto
    /// Bounded accurate attempt with a larger window; still falls back to fast.
    case accurate
    /// Fast recognizer only.
    case fast
}

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

    /// Mode-aware entry point. The default forwards to `analyze(image:)` so
    /// existing providers (and test stubs) keep working unchanged.
    func analyze(image: CGImage, mode: UIEvidenceOCRMode) throws -> UIVisionObservations

    /// Optional one-time warm-up. Hosts should call this at launch so the
    /// accurate recognizer's model load does not land on the first user turn.
    func warmUp()
}

extension UIEvidenceVisionProviding {
    func analyze(image: CGImage, mode: UIEvidenceOCRMode) throws -> UIVisionObservations {
        try analyze(image: image)
    }

    func warmUp() {}
}

enum UIEvidenceVisionError: LocalizedError {
    case unavailable(String)
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .timedOut(let seconds):
            return "Accurate text recognition did not finish within \(String(format: "%.1f", seconds))s."
        }
    }
}

/// Apple Vision implementation: text recognition plus rectangle detection.
///
/// Requests run independently so a rectangle failure does not discard text
/// evidence. Failures are reported as warnings and degrade the evidence.
///
/// The accurate recognizer pays a one-time model-load cost (tens of seconds on
/// some hosts). `auto`/`accurate` bound that wait and degrade to the fast
/// recognizer instead of blocking a tool call; `warmUp()` moves the cost to
/// app launch.
struct AppleUIVisionEvidenceProvider: UIEvidenceVisionProviding {
    /// How long `.auto` waits for the accurate recognizer before degrading.
    let accurateTimeout: TimeInterval

    init(accurateTimeout: TimeInterval = 4.0) {
        self.accurateTimeout = accurateTimeout
    }

    func analyze(image: CGImage) throws -> UIVisionObservations {
        try analyze(image: image, mode: .auto)
    }

    func analyze(image: CGImage, mode: UIEvidenceOCRMode) throws -> UIVisionObservations {
        #if canImport(Vision)
        var output = UIVisionObservations()

        switch mode {
        case .fast:
            do {
                output.textBlocks = try Self.recognizeFast(image)
            } catch {
                output.warnings.append("Vision text recognition failed: \(error.localizedDescription)")
            }
        case .auto:
            if Self.isAccurateWarm() {
                switch Self.recognizeAccurateWithRetry(image, deadline: accurateTimeout) {
                case .success(let blocks):
                    output.textBlocks = blocks
                    Self.markAccurateWarm(true)
                case .failure(let error):
                    if Self.isTimeout(error) {
                        output.warnings.append(
                            "Accurate text recognition did not finish in time; no fast fallback while it is loading."
                        )
                        Self.markAccurateWarm(false)
                    } else {
                        do {
                            output.textBlocks = try Self.recognizeFast(image)
                            output.warnings.append(
                                "Accurate text recognition failed (\(error.localizedDescription)); used fast recognition instead."
                            )
                            Self.markAccurateWarm(false)
                        } catch {
                            output.warnings.append("Vision text recognition failed: \(error.localizedDescription)")
                        }
                    }
                }
            } else {
                // Starting an accurate request here would make the fast request
                // queue behind the one-time model load. Use fast now; the host's
                // warmUp() is what enables accurate OCR.
                do {
                    output.textBlocks = try Self.recognizeFast(image)
                } catch {
                    output.warnings.append("Vision text recognition failed: \(error.localizedDescription)")
                }
                output.warnings.append(
                    "Accurate text recognition is not warm; used fast recognition for this call. Call warmUp() at launch to enable accurate OCR."
                )
            }
        case .accurate:
            if Self.isAccurateWarm() {
                let deadline = max(accurateTimeout, 20.0)
                switch Self.recognizeAccurateWithRetry(image, deadline: deadline) {
                case .success(let blocks):
                    output.textBlocks = blocks
                    Self.markAccurateWarm(true)
                case .failure(let error):
                    if Self.isTimeout(error) {
                        // The recognizer is still loading; a fast request would
                        // queue behind it, so return without text this turn.
                        output.warnings.append(
                            "Accurate text recognition did not finish within \(String(format: "%.1f", deadline))s; no fast fallback while it is loading."
                        )
                        Self.markAccurateWarm(false)
                    } else {
                        do {
                            output.textBlocks = try Self.recognizeFast(image)
                            output.warnings.append(
                                "Accurate text recognition failed (\(error.localizedDescription)); used fast recognition instead."
                            )
                            Self.markAccurateWarm(false)
                        } catch {
                            output.warnings.append("Vision text recognition failed: \(error.localizedDescription)")
                        }
                    }
                }
            } else {
                // Not warm (cold launch or the model was unloaded after idle):
                // an accurate attempt would block or time out. Use fast now.
                do {
                    output.textBlocks = try Self.recognizeFast(image)
                } catch {
                    output.warnings.append("Vision text recognition failed: \(error.localizedDescription)")
                }
                output.warnings.append(
                    "Accurate text recognition is not warm; used fast recognition for this call. Call warmUp() at launch or on foreground to enable accurate OCR."
                )
            }
        }

        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 80
        rectangleRequest.minimumAspectRatio = 0.1
        rectangleRequest.minimumSize = 0.02
        rectangleRequest.minimumConfidence = 0.3
        rectangleRequest.quadratureTolerance = 30

        do {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
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

    /// Warm the accurate recognizer off the caller's thread. The first accurate
    /// request in a process loads the model (measured 70–80 s on macOS 27);
    /// doing it at launch keeps the first user turn warm.
    func warmUp() {
        Self.beginWarmUp()
    }

    static func isAccurateWarm() -> Bool {
        warmLock.lock()
        defer { warmLock.unlock() }
        guard let at = accurateWarmAt else { return false }
        return Date().timeIntervalSince(at) <= warmTTL
    }

    // MARK: - Internals

    private struct SendableImage: @unchecked Sendable {
        let image: CGImage
    }

    private final class TextRecognitionBox: @unchecked Sendable {
        var blocks: [UIVisionText]?
        var error: Error?
    }

    private static let warmLock = NSLock()
    private nonisolated(unsafe) static var accurateWarmAt: Date?
    private nonisolated(unsafe) static var warmUpInFlight = false
    private static let warmTTL: TimeInterval = 180
    private static let warmQueue = DispatchQueue(
        label: "ClientToolsKit.UIEvidenceVision.warmUp",
        qos: .utility
    )

    private static func beginWarmUp() {
        #if canImport(Vision)
        warmLock.lock()
        let warm = accurateWarmAt.map { Date().timeIntervalSince($0) <= warmTTL } ?? false
        if warm || warmUpInFlight {
            warmLock.unlock()
            return
        }
        warmUpInFlight = true
        warmLock.unlock()

        warmQueue.async {
            defer {
                warmLock.lock()
                warmUpInFlight = false
                warmLock.unlock()
            }
            guard let image = warmImage() else { return }
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            do {
                try handler.perform([request])
                markAccurateWarm(true)
            } catch {
                markAccurateWarm(false)
            }
        }
        #endif
    }

    private static func isTimeout(_ error: Error) -> Bool {
        guard let visionError = error as? UIEvidenceVisionError else { return false }
        if case .timedOut = visionError { return true }
        return false
    }

    private static func markAccurateWarm(_ value: Bool) {
        warmLock.lock()
        accurateWarmAt = value ? Date() : nil
        warmLock.unlock()
    }

    private static func minimumTextHeight(for image: CGImage) -> Float {
        let longEdge = CGFloat(max(image.width, image.height))
        return Float(min(0.02, max(0.001, 14.0 / max(longEdge, 1))))
    }

    private static func recognizeFast(_ image: CGImage) throws -> [UIVisionText] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = minimumTextHeight(for: image)
        try handler.perform([request])
        return mapTextResults(request)
    }

    private static func recognizeAccurateWithRetry(
        _ image: CGImage,
        deadline: TimeInterval
    ) -> Result<[UIVisionText], Error> {
        let first = recognizeAccurate(image, deadline: deadline)
        if case .success = first {
            return first
        }
        // One retry with a fresh handler/request: the accurate execution
        // provider can fail once and succeed on a rebuild. A timeout is not
        // retried — that would double the latency budget.
        if case .failure(let error) = first,
           let visionError = error as? UIEvidenceVisionError,
           case .timedOut = visionError {
            return first
        }
        return recognizeAccurate(image, deadline: deadline)
    }

    private static func recognizeAccurate(
        _ image: CGImage,
        deadline: TimeInterval
    ) -> Result<[UIVisionText], Error> {
        let box = TextRecognitionBox()
        let semaphore = DispatchSemaphore(value: 0)
        let boxed = SendableImage(image: image)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let handler = VNImageRequestHandler(cgImage: boxed.image, options: [:])
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                request.minimumTextHeight = minimumTextHeight(for: boxed.image)
                try handler.perform([request])
                box.blocks = mapTextResults(request)
                // Even if the caller timed out, a successful load means the
                // model is now warm for the next call.
                markAccurateWarm(true)
            } catch {
                box.error = error
                markAccurateWarm(false)
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + deadline) == .timedOut {
            return .failure(UIEvidenceVisionError.timedOut(deadline))
        }
        if let blocks = box.blocks {
            return .success(blocks)
        }
        return .failure(box.error ?? UIEvidenceVisionError.unavailable("Vision text recognition failed."))
    }

    private static func warmImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 64,
            height: 32,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 8, y: 8, width: 24, height: 8))
        return context.makeImage()
    }

    #if canImport(Vision)
    private static func mapTextResults(_ request: VNRecognizeTextRequest) -> [UIVisionText] {
        (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return UIVisionText(
                text: text,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }
    #endif
}
