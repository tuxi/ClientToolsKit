//
//  OverlayUIPartitionAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public struct OverlayUIPartitionResult: Sendable, Codable, Hashable {
    public let naturalTextBlocks: [RecognizedTextBlock]
    public let uiTextBlocks: [RecognizedTextBlock]
    public let hasOverlayUI: Bool
    public let isMixedPhotoWithUI: Bool

    public init(
        naturalTextBlocks: [RecognizedTextBlock] = [],
        uiTextBlocks: [RecognizedTextBlock] = [],
        hasOverlayUI: Bool = false,
        isMixedPhotoWithUI: Bool = false
    ) {
        self.naturalTextBlocks = naturalTextBlocks
        self.uiTextBlocks = uiTextBlocks
        self.hasOverlayUI = hasOverlayUI
        self.isMixedPhotoWithUI = isMixedPhotoWithUI
    }
}

public protocol OverlayUIPartitionAnalyzing: Sendable {
    func partition(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> OverlayUIPartitionResult
}

public final class MockOverlayUIPartitionAnalyzer: OverlayUIPartitionAnalyzing {
    public init() {}

    public func partition(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> OverlayUIPartitionResult {
        _ = image
        let natural = rawVision.recognizedTexts.map {
            RecognizedTextBlock(text: $0.text, boundingBox: $0.boundingBox)
        }
        return OverlayUIPartitionResult(naturalTextBlocks: natural)
    }
}
