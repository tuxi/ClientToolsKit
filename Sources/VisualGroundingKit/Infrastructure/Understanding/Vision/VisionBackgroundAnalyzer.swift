//
//  VisionBackgroundAnalyzer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation
import Vision

/// 一个基于 Vision 的背景分析器，用于从单张图像中推断粗略的场景信息。
///
/// 第二版目标：
/// - 继续保持“规则推断背景”
/// - 引入 confidence 加权
/// - 通过多标签分数累加，提高背景推断稳定性
/// - 生成更适合 Prompt 的背景语义
///
/// 当前输出包括：
/// - `sceneType`
/// - `locationTags`
/// - `environmentObjects`
/// - `lighting`
/// - `timeOfDay`
/// - `weather`
///
/// 说明：
/// 这仍然不是“真正的场景理解模型”，而是：
/// Vision 分类标签 + 规则映射 + 置信度加权 的工程实现。
public final class VisionBackgroundAnalyzer: BackgroundAnalyzing {
    
    private let performer: VisionImageRequestPerforming
    private let maxObservationCount: Int
    
    /// 创建一个基于 Vision 的背景分析器。
    ///
    /// - Parameters:
    ///   - performer: 用于执行 Vision 请求的执行器
    ///   - maxObservationCount: 参与背景推断的最大分类结果数量
    public init(
        performer: VisionImageRequestPerforming = VisionImageRequestPerformer(),
        maxObservationCount: Int = 8
    ) {
        self.performer = performer
        self.maxObservationCount = max(1, maxObservationCount)
    }
    
    /// 从图像中分析与背景相关的场景语义。
    ///
    /// - Parameter image: 待分析的输入图像
    /// - Returns: 如果分析成功，返回 `BackgroundDescriptor`；否则返回 `nil`
    public func analyze(in image: VisualImage) async throws -> BackgroundDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let request = VNClassifyImageRequest { request, error in
                    if let error {
                        DLLog("分析到图片的背景失败：", error.localizedDescription)
                        continuation.resume(
                            throwing: VisionAnalyzerError.requestFailed(error.localizedDescription)
                        )
                        return
                    }
                    
                    guard let observations = request.results as? [VNClassificationObservation] else {
                        DLLog("没有分析到图片的背景，request.results 为空")
                        continuation.resume(returning: nil)
                        return
                    }
         
                    let topObservations = Array(observations.prefix(self.maxObservationCount))
                    let debugIdentifiers = topObservations.map {
                        "\($0.identifier.lowercased())(\(String(format: "%.2f", $0.confidence)))"
                    }
                    DLLog("分析到图片的背景为: ", debugIdentifiers)

                    var mapped = self.mapObservationsToBackground(topObservations)
                    
                    if mapped.isEffectivelyEmpty {
                        continuation.resume(returning: nil)
                        return
                    }

                    mapped.normalize()
                    DLLog("最终映射到图片的背景为: ", mapped)

                    let descriptor = self.makeDescriptor(from: mapped)

                    continuation.resume(returning: descriptor)
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
    ) async throws -> BackgroundDescriptor? {
        _ = image
        let topObservations = Array(rawVision.classifications.prefix(maxObservationCount))
        guard !topObservations.isEmpty else {
            return nil
        }

        var mapped = mapObservationsToBackground(topObservations)
        guard !mapped.isEffectivelyEmpty else {
            return nil
        }

        mapped.normalize()
        return makeDescriptor(from: mapped)
    }
}

// MARK: - 映射逻辑

private extension VisionBackgroundAnalyzer {
    
    /// 将 Vision 分类结果映射为背景结构。
    ///
    /// 第二版采用“关键词匹配 + 置信度分档 + 分数累加”的方式。
    func mapObservationsToBackground(_ observations: [VNClassificationObservation]) -> BackgroundMappingResult {
        var result = BackgroundMappingResult()
        
        for observation in observations {
            let identifier = observation.identifier.lowercased()
            let level = rawConfidenceLevel(for: observation.confidence)
            
            guard level != .ignore else { continue }
            
            mapScene(from: identifier, level: level, into: &result)
            mapLighting(from: identifier, level: level, into: &result)
            mapTimeOfDay(from: identifier, level: level, into: &result)
            mapWeather(from: identifier, level: level, into: &result)
            mapEnvironmentObject(from: identifier, level: level, into: &result)
        }
        
        return result
    }

    func mapObservationsToBackground(_ observations: [RawClassificationObservation]) -> BackgroundMappingResult {
        var result = BackgroundMappingResult()

        for observation in observations {
            let identifier = observation.identifier.lowercased()
            let level = confidenceLevel(for: observation.confidence)

            guard level != .ignore else { continue }

            mapScene(from: identifier, level: level, into: &result)
            mapLighting(from: identifier, level: level, into: &result)
            mapTimeOfDay(from: identifier, level: level, into: &result)
            mapWeather(from: identifier, level: level, into: &result)
            mapEnvironmentObject(from: identifier, level: level, into: &result)
        }

        return result
    }

    func makeDescriptor(from mapped: BackgroundMappingResult) -> BackgroundDescriptor {
        BackgroundDescriptor(
            sceneType: mapped.bestSceneType(),
            locationTags: VisionClassificationMapping.sortedTokens(from: mapped.locationTagScores, top: 4),
            environmentObjects: VisionClassificationMapping.sortedTokens(from: mapped.environmentObjectScores, top: 6),
            weather: mapped.bestWeather(),
            lighting: mapped.bestLighting(),
            timeOfDay: mapped.bestTimeOfDay()
        )
    }
    
    /// 映射场景类型和位置标签
    func mapScene(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout BackgroundMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: ["beach", "seashore", "coast", "shore", "ocean", "sea"]) {
            VisionClassificationMapping.add("beach", for: level, into: &result.sceneTypeScores)
            VisionClassificationMapping.add("beach", for: level, into: &result.locationTagScores)
            VisionClassificationMapping.add("seaside", for: level, into: &result.locationTagScores)
            VisionClassificationMapping.add("outdoor", for: level, into: &result.locationTagScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["forest", "woodland", "jungle", "rainforest"]) {
            VisionClassificationMapping.add("forest", for: level, into: &result.sceneTypeScores)
            VisionClassificationMapping.add("forest", for: level, into: &result.locationTagScores)
            VisionClassificationMapping.add("outdoor", for: level, into: &result.locationTagScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["mountain", "alp", "cliff", "valley"]) {
            VisionClassificationMapping.add("mountain", for: level, into: &result.sceneTypeScores)
            VisionClassificationMapping.add("mountain", for: level, into: &result.locationTagScores)
            VisionClassificationMapping.add("outdoor", for: level, into: &result.locationTagScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["park", "garden", "botanical garden"]) {
            VisionClassificationMapping.add("garden", for: level, into: &result.sceneTypeScores)
            VisionClassificationMapping.add("garden", for: level, into: &result.locationTagScores)
            VisionClassificationMapping.add("outdoor", for: level, into: &result.locationTagScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["street", "city", "downtown", "road", "crosswalk", "building", "skyscraper"]) {
            VisionClassificationMapping.add("city street", for: level, into: &result.sceneTypeScores)
            VisionClassificationMapping.add("city", for: level, into: &result.locationTagScores)
            VisionClassificationMapping.add("street", for: level, into: &result.locationTagScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: [
            "office", "classroom", "library", "living room",
            "bedroom", "kitchen", "restaurant", "cafe",
            "coffee shop", "indoor"
        ]) {
            VisionClassificationMapping.add("indoor", for: level, into: &result.sceneTypeScores)
            VisionClassificationMapping.add("indoor", for: level, into: &result.locationTagScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["outdoor", "sky", "blue_sky", "plant", "shrub", "wood_natural", "fence"]) {
            switch level {
            case .strong:
                VisionClassificationMapping.add("outdoor natural scene", score: 1.0, into: &result.sceneTypeScores)
                VisionClassificationMapping.add("outdoor", score: 0.9, into: &result.locationTagScores)
                VisionClassificationMapping.add("natural", score: 0.7, into: &result.locationTagScores)
            case .medium:
                VisionClassificationMapping.add("outdoor natural scene", score: 0.7, into: &result.sceneTypeScores)
                VisionClassificationMapping.add("outdoor", score: 0.6, into: &result.locationTagScores)
                VisionClassificationMapping.add("natural", score: 0.5, into: &result.locationTagScores)
            case .weak:
                VisionClassificationMapping.add("outdoor", score: 0.2, into: &result.locationTagScores)
            case .ignore:
                break
            }
            return
        }
    }
    
    /// 映射光照
    func mapLighting(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout BackgroundMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: ["night", "dark", "dim"]) {
            VisionClassificationMapping.add("dim light", for: level, into: &result.lightingScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunset", "sunrise", "golden"]) {
            VisionClassificationMapping.add("warm light", for: level, into: &result.lightingScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunny", "daylight", "bright"]) {
            VisionClassificationMapping.add("bright natural light", for: level, into: &result.lightingScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["indoor", "office", "room"]) {
            VisionClassificationMapping.add("soft indoor light", for: level, into: &result.lightingScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sky", "blue_sky", "outdoor"]) {
            VisionClassificationMapping.add("natural light", for: level, into: &result.lightingScores)
            return
        }
    }
    
    /// 映射时间段
    func mapTimeOfDay(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout BackgroundMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunrise", "dawn", "morning"]) {
            VisionClassificationMapping.add("morning", for: level, into: &result.timeOfDayScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunset", "dusk", "evening"]) {
            VisionClassificationMapping.add("sunset", for: level, into: &result.timeOfDayScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["night"]) {
            VisionClassificationMapping.add("night", for: level, into: &result.timeOfDayScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["daylight", "daytime", "sunny", "blue_sky"]) {
            VisionClassificationMapping.add("daytime", for: level, into: &result.timeOfDayScores)
            return
        }
    }
    
    /// 映射天气
    func mapWeather(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout BackgroundMappingResult
    ) {
        if VisionClassificationMapping.containsAny(identifier, keywords: ["snow", "blizzard", "ice"]) {
            VisionClassificationMapping.add("snowy", for: level, into: &result.weatherScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["rain", "storm", "thunderstorm"]) {
            VisionClassificationMapping.add("rainy", for: level, into: &result.weatherScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["fog", "mist"]) {
            VisionClassificationMapping.add("foggy", for: level, into: &result.weatherScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["sunny", "clear", "blue_sky"]) {
            VisionClassificationMapping.add("clear", for: level, into: &result.weatherScores)
            return
        }
        
        if VisionClassificationMapping.containsAny(identifier, keywords: ["cloud", "overcast"]) {
            VisionClassificationMapping.add("cloudy", for: level, into: &result.weatherScores)
            return
        }
    }
    
    /// 映射环境物体
    func mapEnvironmentObject(
        from identifier: String,
        level: ConfidenceLevel,
        into result: inout BackgroundMappingResult
    ) {
        let mappings: [(keywords: [String], token: String)] = [
            (["tree", "palm", "pine"], "trees"),
            (["flower", "rose", "tulip", "daisy"], "flowers"),
            (["plant"], "plants"),
            (["shrub"], "shrubs"),
            (["chair", "sofa", "couch"], "furniture"),
            (["table", "desk"], "table"),
            (["car", "bus", "truck"], "vehicles"),
            (["lamp", "light"], "lights"),
            (["bridge"], "bridge"),
            (["river", "lake", "waterfall"], "water"),
            (["building", "tower", "skyscraper", "structure"], "structures"),
            (["fence"], "fence"),
            (["wood_natural"], "wood elements"),
            (["sky", "blue_sky"], "sky")
        ]
        
        for mapping in mappings where VisionClassificationMapping.containsAny(identifier, keywords: mapping.keywords) {
            VisionClassificationMapping.add(mapping.token, for: level, into: &result.environmentObjectScores)
        }
    }
    
}

// MARK: - 内部映射结果集

private extension VisionBackgroundAnalyzer {
    
    /// 内部使用的中间结果结构。
    ///
    /// 第二版使用 `[String: Float]` 保存每个 token 的累计分数，
    /// 最终再根据分数排序，输出最合适的背景结果。
    struct BackgroundMappingResult: CustomStringConvertible {
        var sceneTypeScores: [String: Float] = [:]
        var locationTagScores: [String: Float] = [:]
        var environmentObjectScores: [String: Float] = [:]
        var weatherScores: [String: Float] = [:]
        var lightingScores: [String: Float] = [:]
        var timeOfDayScores: [String: Float] = [:]
        
        var isEffectivelyEmpty: Bool {
            sceneTypeScores.isEmpty &&
            locationTagScores.isEmpty &&
            environmentObjectScores.isEmpty &&
            weatherScores.isEmpty &&
            lightingScores.isEmpty &&
            timeOfDayScores.isEmpty
        }
        
        /// 归一化补全结果
        mutating func normalize() {
            if sceneTypeScores.isEmpty {
                if locationTagScores.keys.contains("beach") {
                    sceneTypeScores["beach"] = 0.3
                } else if locationTagScores.keys.contains("forest") {
                    sceneTypeScores["forest"] = 0.3
                } else if locationTagScores.keys.contains("garden") {
                    sceneTypeScores["garden"] = 0.3
                } else if locationTagScores.keys.contains("city") || locationTagScores.keys.contains("street") {
                    sceneTypeScores["city street"] = 0.3
                } else if locationTagScores.keys.contains("indoor") {
                    sceneTypeScores["indoor"] = 0.3
                } else if locationTagScores.keys.contains("outdoor") {
                    sceneTypeScores["outdoor natural scene"] = 0.3
                }
            }
            
            if lightingScores.isEmpty, let timeOfDay = VisionClassificationMapping.best(from: timeOfDayScores) {
                switch timeOfDay {
                case "sunset":
                    lightingScores["warm light"] = 0.3
                case "night":
                    lightingScores["dim light"] = 0.3
                case "morning", "daytime":
                    lightingScores["natural light"] = 0.3
                default:
                    break
                }
            }
            
            if weatherScores.isEmpty, let timeOfDay = VisionClassificationMapping.best(from: timeOfDayScores), timeOfDay == "sunset" || timeOfDay == "daytime" {
                weatherScores["clear"] = 0.3
            }
        }
        
        func bestSceneType() -> String? {
            VisionClassificationMapping.best(from: sceneTypeScores)
        }
        
        func bestWeather() -> String? {
            VisionClassificationMapping.best(from: weatherScores)
        }
        
        func bestLighting() -> String? {
            VisionClassificationMapping.best(from: lightingScores)
        }
        
        func bestTimeOfDay() -> String? {
            VisionClassificationMapping.best(from: timeOfDayScores)
        }
        

        var description: String {
            """
            BackgroundMappingResult(
              sceneTypeScores: \(sceneTypeScores),
              locationTagScores: \(locationTagScores),
              environmentObjectScores: \(environmentObjectScores),
              weatherScores: \(weatherScores),
              lightingScores: \(lightingScores),
              timeOfDayScores: \(timeOfDayScores)
            )
            """
        }
    }
}
