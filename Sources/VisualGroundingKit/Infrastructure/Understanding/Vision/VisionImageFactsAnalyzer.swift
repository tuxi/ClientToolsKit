//
//  VisionImageFactsAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public final class VisionImageFactsAnalyzer: ImageFactsAnalyzing {
    private let qualityMeasurer: ImageQualityMeasuring
    private let overlayPartitionAnalyzer: OverlayUIPartitionAnalyzing

    public init(
        qualityMeasurer: ImageQualityMeasuring = CoreImageQualityMeasurer(),
        overlayPartitionAnalyzer: OverlayUIPartitionAnalyzing = VisionOverlayUIPartitionAnalyzer()
    ) {
        self.qualityMeasurer = qualityMeasurer
        self.overlayPartitionAnalyzer = overlayPartitionAnalyzer
    }

    public func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> ImageFactsDescriptor {
        // NSImage 在 macOS 15 SDK 中不是 Sendable，同一引用被传入多个并发子任务时
        // 会触发 "Sending 'image' risks causing data races"（macOS 26 SDK 中 NSImage
        // 已标记为 Sendable，无此报错）。三个下游方法均只读图片（转 CGImage 取像素/
        // 读 size），符合"构造后不可变"约定，故用 nonisolated(unsafe) 关闭该检查，
        // 行为约定与 InputImageAsset 一致。
        nonisolated(unsafe) let image = image
        async let brightness = qualityMeasurer.brightness(of: image)
        async let sharpness = qualityMeasurer.sharpness(of: image)
        async let overlay = overlayPartitionAnalyzer.partition(image: image, rawVision: rawVision)

        let overlayResult = try await overlay

        return ImageFactsDescriptor(
            environmentType: inferEnvironmentType(from: rawVision.classifications),
            imageBrightness: try await brightness,
            imageSharpness: try await sharpness,
            hasOverlayUI: overlayResult.hasOverlayUI,
            isMixedPhotoWithUI: overlayResult.isMixedPhotoWithUI,
            naturalTextBlocks: overlayResult.naturalTextBlocks,
            uiTextBlocks: overlayResult.uiTextBlocks
        )
    }
}

private extension VisionImageFactsAnalyzer {
    func inferEnvironmentType(
        from classifications: [RawClassificationObservation]
    ) -> EnvironmentType? {
        let identifiers = classifications.map { $0.identifier.lowercased() }
        guard !identifiers.isEmpty else {
            return nil
        }

        if identifiers.contains(where: { containsAny($0, keywords: ["bedroom", "living room", "kitchen", "bathroom"]) }) {
            return .room
        }

        if identifiers.contains(where: { containsAny($0, keywords: ["office", "classroom", "library", "restaurant", "cafe", "indoor"]) }) {
            return .indoor
        }

        if identifiers.contains(where: { containsAny($0, keywords: ["forest", "mountain", "beach", "river", "lake", "garden", "tree"]) }) {
            return .natural
        }

        if identifiers.contains(where: { containsAny($0, keywords: ["city", "street", "road", "building", "skyscraper", "bridge"]) }) {
            return .urban
        }

        if identifiers.contains(where: { containsAny($0, keywords: ["wall", "studio", "background", "plain"]) }) {
            return .plain
        }

        if identifiers.contains(where: { containsAny($0, keywords: ["outdoor", "sky", "field", "park"]) }) {
            return .outdoor
        }

        return nil
    }

    func containsAny(_ text: String, keywords: [String]) -> Bool {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = Set(
            text
                .split(whereSeparator: { scalar in
                    scalar.unicodeScalars.allSatisfy(separators.contains)
                })
                .map { $0.lowercased() }
        )

        return keywords.contains { keyword in
            let lowered = keyword.lowercased()
            if lowered.contains(" ") {
                return text.contains(lowered)
            }
            return tokens.contains(lowered)
        }
    }
}
