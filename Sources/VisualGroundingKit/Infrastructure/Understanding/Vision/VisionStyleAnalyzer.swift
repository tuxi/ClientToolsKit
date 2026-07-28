//
//  VisionStyleAnalyzer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation
import Vision

/// 基于 Vision 图像分类的风格分析器。
///
/// 第二版目标：
/// - 继续保持“规则推断风格”
/// - 修复 continuation 使用路径
/// - 引入 confidence 加权
/// - 通过多标签分数累加，提升风格推断的稳定性
///
/// 当前会尝试推断：
/// - visualStyle：如 realistic / cinematic / natural / outdoor / indoor
/// - mood：如 calm / fresh / peaceful / moody / energetic
/// - colorPalette：如 warm tones / cool tones / natural tones / neutral tones
/// - renderingHint：如 natural light / soft light / high detail / clean background
///
/// 说明：
/// 这仍然不是“审美模型直接输出”的风格结果，而是：
/// Vision 分类标签 + 规则映射 + 置信度加权 的工程实现。
public final class VisionStyleAnalyzer: StyleAnalyzing {
    
    private let performer: VisionImageRequestPerforming
    private let maxObservationCount: Int
    
    /// 初始化风格分析器
    ///
    /// - Parameters:
    ///   - performer: Vision 请求执行器
    ///   - maxObservationCount: 最多参与映射的分类结果数量
    public init(
        performer: VisionImageRequestPerforming = VisionImageRequestPerformer(),
        maxObservationCount: Int = 8
    ) {
        self.performer = performer
        self.maxObservationCount = max(1, maxObservationCount)
    }
    
    /// 分析图片风格
    ///
    /// - Parameter image: 输入图片
    /// - Returns: 推断得到的 `StyleDescriptor`；如果无法推断则返回 `nil`
    public func analyze(in image: VisualImage) async throws -> StyleDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let request = VNClassifyImageRequest { request, error in
                    if let error {
                        DLLog("分析到图片的风格失败：", error.localizedDescription)
                        continuation.resume(
                            throwing: VisionAnalyzerError.requestFailed(error.localizedDescription)
                        )
                        return
                    }
                    
                    guard let observations = request.results as? [VNClassificationObservation] else {
                        DLLog("没有分析到图片的风格，request.results 为空")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let topObservations = Array(observations.prefix(self.maxObservationCount))
                    
                    let debugIdentifiers = topObservations.map {
                        "\($0.identifier.lowercased())(\(String(format: "%.2f", $0.confidence)))"
                    }
                    DLLog("分析到图片的风格为: ", debugIdentifiers)
                    
                    var mapped = self.mapObservationsToStyle(topObservations)
                    
                    if mapped.isEffectivelyEmpty {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    mapped.normalize()
                    DLLog("最终映射到图片的风格为: ", mapped)
                    
                    let style = self.makeDescriptor(from: mapped)
                    
                    continuation.resume(returning: style)
                }
                
                try performer.perform([request], on: image)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func analyze(
        in image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> StyleDescriptor? {
        _ = image
        let topObservations = Array(rawVision.classifications.prefix(maxObservationCount))
        guard !topObservations.isEmpty else {
            return nil
        }

        var mapped = mapObservationsToStyle(topObservations)
        guard !mapped.isEffectivelyEmpty else {
            return nil
        }

        mapped.normalize()
        return makeDescriptor(from: mapped)
    }
}

// MARK: - 映射逻辑

private extension VisionStyleAnalyzer {
    
    /// 将 Vision 分类结果映射为风格结构。
    ///
    /// 第二版采用“关键词匹配 + 置信度分档 + 分数累加”的方式。
    func mapObservationsToStyle(_ observations: [VNClassificationObservation]) -> StyleMappingResult {
        var result = StyleMappingResult()
        
        for observation in observations {
            let identifier = observation.identifier.lowercased()
            let level = rawConfidenceLevel(for: observation.confidence)
            
            guard level != .ignore else { continue }
            
            mapVisualStyle(from: identifier, level: level, into: &result)
            mapMood(from: identifier, level: level, into: &result)
            mapColorPalette(from: identifier, level: level, into: &result)
            mapRenderingHint(from: identifier, level: level, into: &result)
        }
        
        return result
    }

    func mapObservationsToStyle(_ observations: [RawClassificationObservation]) -> StyleMappingResult {
        var result = StyleMappingResult()

        for observation in observations {
            let identifier = observation.identifier.lowercased()
            let level = confidenceLevel(for: observation.confidence)

            guard level != .ignore else { continue }

            mapVisualStyle(from: identifier, level: level, into: &result)
            mapMood(from: identifier, level: level, into: &result)
            mapColorPalette(from: identifier, level: level, into: &result)
            mapRenderingHint(from: identifier, level: level, into: &result)
        }

        return result
    }

    func makeDescriptor(from mapped: StyleMappingResult) -> StyleDescriptor {
        StyleDescriptor(
            visualStyle: VisionClassificationMapping.sortedTokens(from: mapped.visualStyleScores, top: 4),
            mood: VisionClassificationMapping.sortedTokens(from: mapped.moodScores, top: 4),
            colorPalette: VisionClassificationMapping.sortedTokens(from: mapped.colorPaletteScores, top: 4),
            renderingHint: VisionClassificationMapping.sortedTokens(from: mapped.renderingHintScores, top: 6)
        )
    }
    
    /// 映射视觉风格
    func mapVisualStyle(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout StyleMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: ["portrait", "person", "face", "selfie"]) {
            VisionClassificationMapping.add("realistic", for: level, into: &result.visualStyleScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunset", "sunrise", "night", "street", "city", "building"]) {
            VisionClassificationMapping.add("cinematic", for: level, into: &result.visualStyleScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: [
            "forest", "mountain", "beach", "garden", "park",
            "outdoor", "sky", "blue_sky", "plant", "shrub", "wood_natural"
        ]) {
            switch level {
            case .strong:
                VisionClassificationMapping.add("natural", score: 1.0, into: &result.visualStyleScores)
                VisionClassificationMapping.add("outdoor", score: 0.9, into: &result.visualStyleScores)
                VisionClassificationMapping.add("realistic", score: 0.7, into: &result.visualStyleScores)
            case .medium:
                VisionClassificationMapping.add("natural", score: 0.7, into: &result.visualStyleScores)
                VisionClassificationMapping.add("outdoor", score: 0.6, into: &result.visualStyleScores)
            case .weak:
                VisionClassificationMapping.add("natural", score: 0.3, into: &result.visualStyleScores)
            case .ignore:
                break
            }
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: [
            "room", "office", "bedroom", "kitchen", "library",
            "classroom", "restaurant", "cafe", "indoor"
        ]) {
            VisionClassificationMapping.add("indoor", for: level, into: &result.visualStyleScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["flower", "rose", "tulip"]) {
            VisionClassificationMapping.add("romantic", for: level, into: &result.visualStyleScores)
            return
        }
    }
    
    /// 映射情绪氛围
    func mapMood(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout StyleMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: [
            "sunset", "sunrise", "garden", "flower", "beach",
            "sky", "blue_sky", "plant", "shrub"
        ]) {
            switch level {
            case .strong:
                VisionClassificationMapping.add("calm", score: 0.9, into: &result.moodScores)
                VisionClassificationMapping.add("fresh", score: 0.8, into: &result.moodScores)
            case .medium:
                VisionClassificationMapping.add("calm", score: 0.6, into: &result.moodScores)
                VisionClassificationMapping.add("fresh", score: 0.5, into: &result.moodScores)
            case .weak:
                VisionClassificationMapping.add("calm", score: 0.2, into: &result.moodScores)
            case .ignore:
                break
            }
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["night", "city", "street", "building"]) {
            VisionClassificationMapping.add("moody", for: level, into: &result.moodScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sport", "running", "jumping", "soccer", "basketball"]) {
            VisionClassificationMapping.add("energetic", for: level, into: &result.moodScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["forest", "mountain", "lake", "outdoor"]) {
            VisionClassificationMapping.add("peaceful", for: level, into: &result.moodScores)
            return
        }
    }
    
    /// 映射色彩倾向
    func mapColorPalette(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout StyleMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunset", "sunrise", "golden", "lamp", "light"]) {
            VisionClassificationMapping.add("warm tones", for: level, into: &result.colorPaletteScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sea", "ocean", "lake", "snow", "ice", "night", "sky", "blue_sky"]) {
            VisionClassificationMapping.add("cool tones", for: level, into: &result.colorPaletteScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: [
            "forest", "garden", "park", "tree", "grass", "flower",
            "plant", "shrub", "wood_natural", "outdoor"
        ]) {
            VisionClassificationMapping.add("natural tones", for: level, into: &result.colorPaletteScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["city", "street", "building", "office", "structure", "fence"]) {
            VisionClassificationMapping.add("neutral tones", for: level, into: &result.colorPaletteScores)
            return
        }
    }
    
    /// 映射渲染提示
    func mapRenderingHint(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout StyleMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: ["portrait", "person", "face"]) {
            switch level {
            case .strong:
                VisionClassificationMapping.add("high detail", score: 1.0, into: &result.renderingHintScores)
                VisionClassificationMapping.add("natural skin texture", score: 0.9, into: &result.renderingHintScores)
            case .medium:
                VisionClassificationMapping.add("high detail", score: 0.6, into: &result.renderingHintScores)
            case .weak:
                VisionClassificationMapping.add("high detail", score: 0.2, into: &result.renderingHintScores)
            case .ignore:
                break
            }
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunset", "sunrise"]) {
            VisionClassificationMapping.add("soft light", for: level, into: &result.renderingHintScores)
            VisionClassificationMapping.add("glow", for: level, into: &result.renderingHintScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["night", "city", "street"]) {
            VisionClassificationMapping.add("night scene", for: level, into: &result.renderingHintScores)
            VisionClassificationMapping.add("contrast lighting", for: level, into: &result.renderingHintScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: [
            "forest", "garden", "mountain", "beach",
            "outdoor", "sky", "blue_sky", "plant", "shrub"
        ]) {
            VisionClassificationMapping.add("natural light", for: level, into: &result.renderingHintScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["fence", "structure", "wood_natural"]) {
            switch level {
            case .strong, .medium:
                VisionClassificationMapping.add("clean background", score: 0.6, into: &result.renderingHintScores)
            case .weak, .ignore:
                break
            }
            return
        }
    }
}

// MARK: - 中间映射结构

private extension VisionStyleAnalyzer {
    
    /// 内部使用的中间映射结构。
    ///
    /// 第二版不再直接用 `Set<String>`，而是用 `[String: Float]`
    /// 记录每个 token 的累计分数，最后按分数排序取前几个结果。
    struct StyleMappingResult: CustomStringConvertible {
        var visualStyleScores: [String: Float] = [:]
        var moodScores: [String: Float] = [:]
        var colorPaletteScores: [String: Float] = [:]
        var renderingHintScores: [String: Float] = [:]
        
        var isEffectivelyEmpty: Bool {
            visualStyleScores.isEmpty &&
            moodScores.isEmpty &&
            colorPaletteScores.isEmpty &&
            renderingHintScores.isEmpty
        }
        
        /// 归一化补全结果。
        mutating func normalize() {
            if visualStyleScores.isEmpty {
                visualStyleScores["realistic"] = 0.3
            }
            
            if visualStyleScores.keys.contains("cinematic"), moodScores.isEmpty {
                moodScores["moody"] = 0.3
            }
            
            if (visualStyleScores.keys.contains("outdoor") || visualStyleScores.keys.contains("natural")),
               colorPaletteScores.isEmpty {
                colorPaletteScores["natural tones"] = 0.3
            }
            
            if renderingHintScores.isEmpty {
                renderingHintScores["high detail"] = 0.3
            }
        }
        
        
        var description: String {
            """
            StyleMappingResult(
              visualStyleScores: \(visualStyleScores),
              moodScores: \(moodScores),
              colorPaletteScores: \(colorPaletteScores),
              renderingHintScores: \(renderingHintScores)
            )
            """
        }
    }
}
