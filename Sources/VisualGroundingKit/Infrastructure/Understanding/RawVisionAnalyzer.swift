//
//  RawVisionAnalyzer.swift
//  VisualGroundingKit
//
//  Protocol definition for raw Vision observation analysis.
//  Implementation: VisionRawObservationAnalyzer.
//

import Foundation

public protocol RawVisionAnalyzing: Sendable {
    func analyze(in image: VisualImage, profile: AnalysisProfile) async throws -> RawVisionAnalysis
}

public extension RawVisionAnalyzing {
    func analyze(in image: VisualImage) async throws -> RawVisionAnalysis {
        try await analyze(in: image, profile: .generationGrounding)
    }
}
