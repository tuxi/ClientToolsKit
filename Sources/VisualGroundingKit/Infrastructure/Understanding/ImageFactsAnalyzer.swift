//
//  ImageFactsAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public protocol ImageFactsAnalyzing: Sendable {
    func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> ImageFactsDescriptor
}

public final class MockImageFactsAnalyzer: ImageFactsAnalyzing {
    public init() {}

    public func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> ImageFactsDescriptor {
        _ = image
        let natural = rawVision.recognizedTexts.map {
            RecognizedTextBlock(text: $0.text, boundingBox: $0.boundingBox)
        }
        return ImageFactsDescriptor(naturalTextBlocks: natural)
    }
}
