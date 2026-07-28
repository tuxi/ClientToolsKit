//
//  CoreMLObjectDetector.swift
//  VisualGroundingKit
//
//  Lazy-loading Core ML object detector for multi-object localization.
//  Uses YOLOv8n via VNCoreMLRequest, integrated into the unified Vision pipeline.
//

import Foundation
import Vision
import CoreML

// MARK: - Error

public enum CoreMLDetectorError: Error, LocalizedError {
    case modelNotFound
    case modelCompilationFailed(String)
    case unsupportedModelOutput

    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "YOLOv8n model not found in bundle. Run the export script to generate it."
        case .modelCompilationFailed(let reason):
            return "Failed to compile Core ML model: \(reason)"
        case .unsupportedModelOutput:
            return "Model output format is not supported. Expected VNRecognizedObjectObservation."
        }
    }
}

// MARK: - Detector

/// Thread-safe, lazy-loading object detector based on YOLOv8n + VNCoreML.
///
/// Uses a lock for thread-safe model caching. Requests are created fresh each
/// time (VNCoreMLRequest is not Sendable).
///
/// ## Usage
///
/// ```swift
/// let detector = CoreMLObjectDetector()
/// let request = try detector.makeRequest()
/// // Add to VNImageRequestHandler and call perform
/// let results = detector.parseResults(from: request)
/// ```
///
/// The model is loaded once on first access and cached for the process lifetime.
public final class CoreMLObjectDetector: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedModel: VNCoreMLModel?
    private var loadError: Error?
    private var loadAttempted = false

    /// Minimum confidence threshold for a detection to be reported.
    public var minimumConfidence: Float = 0.35

    public init() {}

    // MARK: - Model Loading

    /// Returns a cached model or loads it from the bundle.
    ///
    /// - Throws: `CoreMLDetectorError` if the model is missing or fails to compile.
    /// - Note: Load is attempted only once; subsequent calls return the cached result.
    public func loadModel() throws -> VNCoreMLModel {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedModel { return cached }
        if let error = loadError, loadAttempted { throw error }

        loadAttempted = true

        guard let url = resolveModelURL() else {
            let error = CoreMLDetectorError.modelNotFound
            loadError = error
            DLLog("CoreMLObjectDetector: model file not found — object detection unavailable. Run the export script to generate yolov8n.mlpackage in Resources/.")
            throw error
        }

        let compiled: MLModel
        do {
            compiled = try MLModel(contentsOf: url)
        } catch {
            let wrapped = CoreMLDetectorError.modelCompilationFailed(error.localizedDescription)
            loadError = wrapped
            throw wrapped
        }

        let visionModel: VNCoreMLModel
        do {
            visionModel = try VNCoreMLModel(for: compiled)
        } catch {
            let wrapped = CoreMLDetectorError.modelCompilationFailed(error.localizedDescription)
            loadError = wrapped
            throw wrapped
        }

        cachedModel = visionModel
        return visionModel
    }

    /// Returns `true` if the model is available (loaded or loadable).
    public func isAvailable() -> Bool {
        if cachedModel != nil { return true }
        return (try? loadModel()) != nil
    }

    // MARK: - VNCoreMLRequest

    /// Creates a `VNCoreMLRequest` backed by the YOLOv8n model.
    ///
    /// - Returns: A request ready to add to a `VNImageRequestHandler`.
    /// - Throws: If model loading fails.
    public func makeRequest() throws -> VNCoreMLRequest {
        let model = try loadModel()
        let request = VNCoreMLRequest(model: model)
        // YOLOv8n with NMS outputs VNRecognizedObjectObservation natively.
        request.imageCropAndScaleOption = .scaleFill
        return request
    }

    // MARK: - Result Parsing

    /// Parses detection results from a completed `VNCoreMLRequest`.
    ///
    /// - Parameter request: A completed Core ML Vision request.
    /// - Returns: Array of detected objects, sorted by confidence descending.
    public func parseResults(from request: VNCoreMLRequest) -> [RawDetectedObject] {
        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        return observations
            .filter { $0.confidence >= minimumConfidence }
            .compactMap { observation in
                guard let label = observation.labels.first?.identifier else {
                    return nil
                }
                return RawDetectedObject(
                    label: label,
                    confidence: observation.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            .sorted { $0.confidence > $1.confidence }
    }

    /// Resolves the model URL by trying formats in order of preference.
    ///
    /// 1. `.mlmodelc` – Xcode-compiled (fastest, used in host app builds)
    /// 2. `.mlpackage` – raw export (used during SPM development)
    private func resolveModelURL() -> URL? {
        // Xcode-compiled model (host app)
        if let url = Bundle.module.url(forResource: "yolov8n", withExtension: "mlmodelc") {
            return url
        }
        // Raw mlpackage (SPM development)
        if let url = Bundle.module.url(forResource: "yolov8n", withExtension: "mlpackage") {
            return url
        }
        return nil
    }

    /// Whether the detector should run given the analysis context.
    ///
    /// The detector is most useful on natural photos and least useful on screenshots
    /// and heavy-text documents (where COCO objects are unlikely to appear).
    public static func shouldRun(
        profile: AnalysisProfile,
        contentTypeHint: String?
    ) -> Bool {
        switch profile {
        case .agentCompact, .generationGrounding:
            // Skip on screenshots and text-heavy documents.
            return contentTypeHint != "screenshot" && contentTypeHint != "text_heavy"
        case .debug:
            return true
        }
    }
}
