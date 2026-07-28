//
//  VisionOverlayUIPartitionAnalyzer.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public final class VisionOverlayUIPartitionAnalyzer: OverlayUIPartitionAnalyzing {
    public init() {}

    public func partition(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> OverlayUIPartitionResult {
        let size = image.size
        let natural = rawVision.recognizedTexts.compactMap { observation -> RecognizedTextBlock? in
            guard classifyText(observation, canvasSize: size) == .natural else {
                return nil
            }
            return RecognizedTextBlock(text: observation.text, boundingBox: observation.boundingBox)
        }
        let ui = rawVision.recognizedTexts.compactMap { observation -> RecognizedTextBlock? in
            guard classifyText(observation, canvasSize: size) == .ui else {
                return nil
            }
            return RecognizedTextBlock(text: observation.text, boundingBox: observation.boundingBox)
        }

        let hasOverlayUI = !ui.isEmpty
        let hasPhotoContent = !rawVision.faces.isEmpty
            || !rawVision.humanBodies.isEmpty
            || isLikelyPhoto(classifications: rawVision.classifications)

        return OverlayUIPartitionResult(
            naturalTextBlocks: natural,
            uiTextBlocks: ui,
            hasOverlayUI: hasOverlayUI,
            isMixedPhotoWithUI: hasOverlayUI && hasPhotoContent
        )
    }
}

private extension VisionOverlayUIPartitionAnalyzer {
    enum TextLayer {
        case natural
        case ui
    }

    func classifyText(
        _ observation: RawRecognizedTextObservation,
        canvasSize: CGSize
    ) -> TextLayer {
        let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = text.lowercased()
        let box = observation.boundingBox

        let isTopBar = box.minY >= 0.92
        let isBottomBar = box.maxY <= 0.08
        let isEdgeAligned = box.minY >= 0.9
            || box.maxY <= 0.1
            || box.minX <= 0.04
            || box.maxX >= 0.96
        let isTinyText = box.height < 0.035 || box.width < 0.04
        let looksLikeStatusBar = text.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
            || lowercased == "5g"
            || lowercased == "wifi"
            || text.range(of: #"^\d{1,3}%$"#, options: .regularExpression) != nil
        let looksLikeUIButton = (
            text.count <= 8
            && !text.contains(" ")
            && (isEdgeAligned || isTopBar || isBottomBar)
        ) || looksLikeActionLabel(lowercased)
        let isMostlySymbols = symbolRatio(in: text) > 0.45
        let isCanvasTiny = max(canvasSize.width, canvasSize.height) < 10

        if looksLikeStatusBar
            || looksLikeUIButton
            || ((isTopBar || isBottomBar || isEdgeAligned) && isTinyText)
            || isMostlySymbols {
            return .ui
        }

        if isCanvasTiny && text.count <= 4 {
            return .ui
        }

        return .natural
    }

    func looksLikeActionLabel(_ lowercased: String) -> Bool {
        let commonUILabels: Set<String> = [
            "发布", "首页", "我的", "返回", "下一步", "取消", "确定",
            "done", "back", "next", "cancel", "ok", "save", "post", "home", "profile"
        ]
        return commonUILabels.contains(lowercased)
    }

    func isLikelyPhoto(classifications: [RawClassificationObservation]) -> Bool {
        let negativeKeywords = [
            "screenshot", "screen", "menu", "web site", "website", "text", "document", "book jacket"
        ]
        let positiveKeywords = [
            "person", "portrait", "dog", "cat", "animal", "mountain", "beach", "forest", "flower", "car"
        ]

        let identifiers = classifications.map { $0.identifier.lowercased() }

        if identifiers.contains(where: { id in positiveKeywords.contains(where: id.contains) }) {
            return true
        }

        if identifiers.contains(where: { id in negativeKeywords.contains(where: id.contains) }) {
            return false
        }

        return !identifiers.isEmpty
    }

    func symbolRatio(in text: String) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        let symbolCount = text.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.inverted.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }.count

        return Double(symbolCount) / Double(text.count)
    }
}
