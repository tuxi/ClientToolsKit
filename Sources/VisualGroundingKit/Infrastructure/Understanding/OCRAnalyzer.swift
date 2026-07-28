//
//  OCRAnalyzer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//


import Foundation

public protocol OCRAnalyzing: Sendable {
    func recognize(in image: VisualImage) async throws -> [RecognizedTextBlock]
    func recognize(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> [RecognizedTextBlock]
}

public extension OCRAnalyzing {
    func recognize(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> [RecognizedTextBlock] {
        _ = rawVision
        return try await recognize(in: image)
    }
}

public final class MockOCRAnalyzer: OCRAnalyzing {
    public init() {}
    
    public func recognize(in image: VisualImage) async throws -> [RecognizedTextBlock] {
        []
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
