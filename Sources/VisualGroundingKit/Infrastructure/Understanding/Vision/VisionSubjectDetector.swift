//
//  VisionSubjectDetector.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation
import Vision


extension VNFaceObservation: @retroactive @unchecked Sendable {}
extension VNHumanBodyPoseObservation: @retroactive @unchecked Sendable {}


/// 基于 Vision 框架的主体检测器。
///
/// 第三版目标：
/// - 回归“保守事实提取”
/// - 主字段只输出稳定、低风险的信息
/// - 年龄 / 群体构成 / 关系等高风险语义只作为弱提示
/// - 不再让 detector 承担过多语义解释职责
///
/// 当前职责：
/// 1. 判断是否存在人物主体
/// 2. 提取大致主体数量
/// 3. 提取主体整体姿态
/// 4. 提取主体整体边界框
/// 5. 提供少量弱提示，但不保证一定正确
public final class VisionSubjectDetector: SubjectDetecting {
    
    private let performer: VisionImageRequestPerforming
    private let rawVisionAnalyzer: RawVisionAnalyzing
    private let portraitAttributeAnalyzer: PortraitAttributeAnalyzing
    
    /// 创建一个基于 Vision 的主体检测器。
    ///
    /// - Parameter performer: 用于执行 Vision 请求的执行器。
    public init(
        performer: VisionImageRequestPerforming = VisionImageRequestPerformer(),
        rawVisionAnalyzer: RawVisionAnalyzing? = nil,
        portraitAttributeAnalyzer: PortraitAttributeAnalyzing = VisionPortraitAttributeAnalyzer()
    ) {
        self.performer = performer
        self.rawVisionAnalyzer = rawVisionAnalyzer ?? VisionRawObservationAnalyzer(performer: performer)
        self.portraitAttributeAnalyzer = portraitAttributeAnalyzer
    }
    
    /// 检测给定图像中的主要主体。
    ///
    /// 检测策略：
    /// - 运行人脸检测
    /// - 运行人体姿态检测
    /// - 运行图像分类
    /// - 将结果合并为最终主体
    ///
    /// 注意：
    /// 当前输出偏向“生成约束所需的稳定事实”，
    /// 而不是“完整内容理解”。
    public func detect(in image: VisualImage) async throws -> [DetectedSubject] {
        DLLog("开始检测给定图像中的主要主体，图片size：", image.size)
        let rawVision = try await rawVisionAnalyzer.analyze(in: image)
        let portraitAttributes = try await portraitAttributeAnalyzer.analyze(
            image: image,
            rawVision: rawVision
        )
        return try await detect(
            in: image,
            rawVision: rawVision,
            portraitAttributes: portraitAttributes
        )
    }

    public func detect(
        in image: VisualImage,
        rawVision: RawVisionAnalysis,
        portraitAttributes: PortraitAttributeResult?
    ) async throws -> [DetectedSubject] {
        _ = image

        let classifiedSubject = classifyPrimarySubject(
            from: combinedClassifications(from: rawVision)
        )

        // Phase 1: merge face/body data with classification (existing path)
        let mergedPersonSubject = mergeSubjects(
            faceObservations: rawVision.faces,
            bodyObservations: rawVision.humanBodies,
            classified: classifiedSubject,
            portraitAttributes: portraitAttributes
        )

        // Phase 2: produce object subjects from Core ML detection results
        let detectedObjectSubjects = detectFromCoreML(from: rawVision.detectedObjects)

        // Phase 3: merge all subjects
        return mergeAllSubjects(
            personSubject: mergedPersonSubject,
            classificationSubject: classifiedSubject,
            detectedObjects: detectedObjectSubjects
        )
    }

    // MARK: - Core ML Detection to Subjects

    /// Converts Core ML detection results into `DetectedSubject` objects.
    ///
    /// Objects that overlap heavily with an existing face/body bbox are
    /// skipped (they're already covered by the person subject).
    private func detectFromCoreML(
        from detectedObjects: [RawDetectedObject]
    ) -> [DetectedSubject] {
        guard !detectedObjects.isEmpty else { return [] }

        // Deduplicate: keep the highest-confidence detection per label.
        var bestByLabel: [String: RawDetectedObject] = [:]
        for obj in detectedObjects {
            let key = obj.label.lowercased()
            if let existing = bestByLabel[key], existing.confidence >= obj.confidence {
                continue
            }
            bestByLabel[key] = obj
        }

        return bestByLabel.values
            .sorted { $0.confidence > $1.confidence }
            .prefix(8) // Reasonable upper bound per image
            .map { obj in
                // Map COCO label through our classification normalizer
                let match = mapClassificationToSubject(identifier: obj.label)
                let canonicalLabel = match?.canonicalLabel ?? normalizeUnmatchedLabel(obj.label)
                let type = match?.type ?? .object

                return DetectedSubject(
                    type: type,
                    confidence: obj.confidence,
                    classificationLabel: canonicalLabel,
                    classificationSource: "coreml_detector",
                    classificationCandidates: [],
                    attributes: SubjectAttributes(),
                    pose: nil,
                    boundingBox: obj.boundingBox,
                    segmentationHint: nil
                )
            }
    }

    /// Merges person, classification, and detection-based subjects into a unified result.
    private func mergeAllSubjects(
        personSubject: DetectedSubject?,
        classificationSubject: DetectedSubject?,
        detectedObjects: [DetectedSubject]
    ) -> [DetectedSubject] {
        var subjects: [DetectedSubject] = []

        // Person subject always comes first if present.
        if let person = personSubject {
            subjects.append(person)
        }

        // Filter out detected objects that overlap with the person bbox.
        let personBox = personSubject?.boundingBox
        var remainingObjects = detectedObjects

        if let personBox {
            remainingObjects = detectedObjects.filter { obj in
                guard let objBox = obj.boundingBox else { return true }
                let iou = computeIoU(personBox, objBox)
                return iou < 0.3 // Keep only if not heavily overlapping with person
            }
        }

        // Filter out "person" label duplicates when a person subject already exists.
        if personSubject != nil {
            remainingObjects = remainingObjects.filter { $0.type != .person }
        }

        subjects.append(contentsOf: remainingObjects)

        // Fallback: if we only have a classification subject (no people, no detections).
        if subjects.isEmpty, let classified = classificationSubject, classified.type != .unknown {
            subjects.append(classified)
        }

        // Ultimate fallback: unknown.
        if subjects.isEmpty {
            if let classified = classificationSubject {
                subjects.append(classified)
            } else {
                subjects.append(
                    DetectedSubject(
                        type: .unknown,
                        confidence: 0.2,
                        attributes: SubjectAttributes(),
                        pose: nil,
                        boundingBox: nil,
                        segmentationHint: nil
                    )
                )
            }
        }

        return subjects
    }

    /// Compute Intersection-over-Union between two normalized bounding boxes.
    private func computeIoU(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let areaA = a.width * a.height
        let areaB = b.width * b.height
        let areaI = intersection.width * intersection.height
        let unionArea = areaA + areaB - areaI
        guard unionArea > 0 else { return 0 }
        return areaI / unionArea
    }
}

// MARK: - Vision 请求

private extension VisionSubjectDetector {
    func mergeSubjects(
        faceObservations: [RawFaceObservation],
        bodyObservations: [RawHumanBodyObservation],
        classified: DetectedSubject?,
        portraitAttributes: PortraitAttributeResult?
    ) -> DetectedSubject? {
        let faceCount = faceObservations.count
        let bodyCount = bodyObservations.count

        if faceCount == 0 && bodyCount == 0 {
            return classified
        }

        if shouldTreatFacesAsBackgroundNoise(
            faces: faceObservations,
            bodyObservations: bodyObservations,
            classified: classified
        ) {
            return classified
        }

        if bodyCount == 0 && faceCount > 0 {
            if hasStrongAnimalEvidence(classified) || hasStrongObjectEvidence(classified) {
                return classified
            }

            let boundingBox = unionBoundingBox(
                faceObservations: faceObservations,
                bodyObservations: bodyObservations
            )

            let accessories: [String] = faceCount > 1 ? ["group portrait"] : []

            return DetectedSubject(
                type: .person,
                confidence: faceObservations.compactMap(\.confidence).max() ?? 0.5,
                attributes: SubjectAttributes(
                    ageGroupHint: nil,
                    ageCompositionHint: inferAgeCompositionHint(faceObservations: faceObservations),
                    accessories: accessories,
                    postureType: portraitAttributes?.postureType?.rawValue,
                    portraitFraming: portraitAttributes?.portraitFraming?.rawValue,
                    gender: portraitAttributes?.gender?.rawValue,
                    ageLevel: portraitAttributes?.ageLevel?.rawValue,
                    subjectCount: faceCount,
                    relationshipHints: faceCount >= 2 ? ["group_pose"] : []
                ),
                pose: nil,
                boundingBox: boundingBox,
                segmentationHint: SegmentationHint(isForegroundClear: false)
            )
        }

        let personCount = max(faceCount, bodyCount)
        guard personCount > 0 else {
            return classified
        }

        let relationshipHints = inferRelationshipHints(
            faceObservations: faceObservations,
            bodyObservations: bodyObservations
        )

        let ageCompositionHint = inferAgeCompositionHint(faceObservations: faceObservations)
        let boundingBox = unionBoundingBox(
            faceObservations: faceObservations,
            bodyObservations: bodyObservations
        )
        let maxConfidence = max(
            faceObservations.compactMap(\.confidence).max() ?? 0,
            bodyObservations.compactMap(\.confidence).max() ?? 0
        )
        let accessories: [String] = personCount > 1 ? ["group portrait"] : []

        return DetectedSubject(
            type: .person,
            confidence: maxConfidence,
            attributes: SubjectAttributes(
                ageGroupHint: nil,
                ageCompositionHint: ageCompositionHint,
                accessories: accessories,
                postureType: portraitAttributes?.postureType?.rawValue,
                portraitFraming: portraitAttributes?.portraitFraming?.rawValue,
                gender: portraitAttributes?.gender?.rawValue,
                ageLevel: portraitAttributes?.ageLevel?.rawValue,
                subjectCount: personCount,
                relationshipHints: relationshipHints
            ),
            pose: makeMergedPoseDescriptor(from: bodyObservations),
            boundingBox: boundingBox,
            segmentationHint: SegmentationHint(isForegroundClear: true)
        )
    }

    func inferRelationshipHints(
        faceObservations: [RawFaceObservation],
        bodyObservations: [RawHumanBodyObservation]
    ) -> [String] {
        var hints: [String] = []

        let personCount = max(faceObservations.count, bodyObservations.count)
        if personCount >= 2 {
            hints.append("group_pose")
        }
        if bodyObservations.count >= 2 {
            hints.append("standing_beside")
        }

        return dedupStrings(hints)
    }

    func inferAgeCompositionHint(
        faceObservations: [RawFaceObservation]
    ) -> String? {
        guard faceObservations.count >= 2 else {
            return nil
        }

        let faceAreas = faceObservations
            .map { $0.boundingBox.width * $0.boundingBox.height }
            .sorted(by: >)

        guard let largest = faceAreas.first,
              let smallest = faceAreas.last,
              smallest > 0 else {
            return nil
        }

        return largest / smallest >= 2.2 ? "mixed_adult_child" : nil
    }

    func unionBoundingBox(
        faceObservations: [RawFaceObservation],
        bodyObservations: [RawHumanBodyObservation]
    ) -> CGRect? {
        let faceBoxes = faceObservations.map(\.boundingBox)
        let bodyBoxes = bodyObservations.compactMap(\.boundingBox)
        let allBoxes = faceBoxes + bodyBoxes
        guard let first = allBoxes.first else { return nil }
        return allBoxes.dropFirst().reduce(first) { $0.union($1) }
    }

    func makeMergedPoseDescriptor(
        from observations: [RawHumanBodyObservation]
    ) -> PoseDescriptor? {
        guard !observations.isEmpty else { return nil }

        if observations.count >= 2 {
            return PoseDescriptor(posture: "standing", action: "group pose")
        }

        return PoseDescriptor(posture: inferSinglePosture(from: observations[0]))
    }

    func inferSinglePosture(
        from observation: RawHumanBodyObservation
    ) -> String? {
        let points = observation.recognizedPoints
        let shoulderY = averageY([points["leftShoulder"], points["rightShoulder"]])
        let hipY = averageY([points["leftHip"], points["rightHip"]])
        let kneeY = averageY([points["leftKnee"], points["rightKnee"]])
        let ankleY = averageY([points["leftAnkle"], points["rightAnkle"]])

        guard let shoulderY, let hipY else {
            return nil
        }

        let torsoHeight = abs(shoulderY - hipY)
        if let kneeY, let ankleY {
            let legHeight = abs(hipY - kneeY) + abs(kneeY - ankleY)
            if legHeight > torsoHeight * 0.9 {
                return "standing"
            }
            if legHeight < torsoHeight * 0.65 {
                return "sitting"
            }
        }
        return nil
    }

    func averageY(_ points: [CGPoint?]) -> CGFloat? {
        let valid = points.compactMap { $0?.y }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / CGFloat(valid.count)
    }

    func totalFaceArea(_ faces: [RawFaceObservation]) -> CGFloat {
        faces.reduce(0) { $0 + ($1.boundingBox.width * $1.boundingBox.height) }
    }

    func largestFaceArea(_ faces: [RawFaceObservation]) -> CGFloat {
        faces.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0
    }

    func shouldTreatFacesAsBackgroundNoise(
        faces: [RawFaceObservation],
        bodyObservations: [RawHumanBodyObservation],
        classified: DetectedSubject?
    ) -> Bool {
        guard !faces.isEmpty else { return false }
        guard bodyObservations.isEmpty else { return false }
        guard hasStrongAnimalEvidence(classified) || hasStrongObjectEvidence(classified) else {
            return false
        }

        let totalArea = totalFaceArea(faces)
        let maxArea = largestFaceArea(faces)
        return totalArea < 0.10 && maxArea < 0.06
    }
}

private extension VisionSubjectDetector {
    
    /// 检测图片中的人脸观察结果。
    func detectFaces(in image: VisualImage) async throws -> [VNFaceObservation] {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let request = VNDetectFaceRectanglesRequest { request, error in
                    if let error {
                        continuation.resume(
                            throwing: VisionAnalyzerError.requestFailed(error.localizedDescription)
                        )
                        return
                    }
                    
                    let observations = request.results as? [VNFaceObservation] ?? []
                    DLLog("检测到人脸矩形数量: ", observations.count)
                    continuation.resume(returning: observations)
                }
                
                try performer.perform([request], on: image)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 检测图片中的人体姿态观察结果。
    func detectBodyPoses(in image: VisualImage) async throws -> [VNHumanBodyPoseObservation] {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let request = VNDetectHumanBodyPoseRequest { request, error in
                    if let error {
                        continuation.resume(
                            throwing: VisionAnalyzerError.requestFailed(error.localizedDescription)
                        )
                        return
                    }
                    
                    let observations = request.results as? [VNHumanBodyPoseObservation] ?? []
                    DLLog("人体姿势检测结果数量: ", observations.count)
                    continuation.resume(returning: observations)
                }
                
                try performer.perform([request], on: image)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// 图像分类兜底。
    ///
    /// 当没有人脸 / 没有人体时，用来推断是否为动物 / 物体 / 未知主体。
    func classifyPrimarySubject(in image: VisualImage) async throws -> DetectedSubject? {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let request = VNClassifyImageRequest { request, error in
                    if let error {
                        continuation.resume(
                            throwing: VisionAnalyzerError.requestFailed(error.localizedDescription)
                        )
                        return
                    }
                    
                    guard let observations = request.results as? [VNClassificationObservation],
                          let best = observations.first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let identifier = best.identifier.lowercased()
                    let type = self.mapClassificationToSubjectType(identifier: identifier)
                    
                    let subject = DetectedSubject(
                        type: type,
                        confidence: best.confidence,
                        attributes: SubjectAttributes(),
                        pose: nil,
                        boundingBox: nil,
                        segmentationHint: nil
                    )
                    
                    continuation.resume(returning: subject)
                }
                
                try performer.perform([request], on: image)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func classifyPrimarySubject(
        from observations: [RawClassificationObservation]
    ) -> DetectedSubject? {
        guard !observations.isEmpty else {
            return nil
        }

        // Phase 1: rank all observations by a unified scoring function
        let rankedMatches = observations.compactMap { observation -> RankedSubjectMatch? in
            guard observation.confidence >= 0.03 else { return nil }

            let sourceBoost: Float = observation.source?.hasPrefix("saliency_") == true
                || observation.source?.hasPrefix("objectness_") == true
                || observation.source?.hasPrefix("attention_") == true
                ? 1.25 : 1

            // Try canonical mapping first
            if let match = mapClassificationToSubject(identifier: observation.identifier) {
                return RankedSubjectMatch(
                    observation: observation,
                    type: match.type,
                    canonicalLabel: match.canonicalLabel,
                    score: observation.confidence * match.subjectWeight * sourceBoost
                )
            }

            // No mapping matched — don't discard.
            // Best-effort heuristic: parse known subject patterns from the raw identifier.
            if let fallback = classifyUnmatched(observation: observation, sourceBoost: sourceBoost) {
                return fallback
            }

            return nil
        }
        .sorted { $0.score > $1.score }

        let candidates = compactCandidates(
            preferred: rankedMatches.map(\.observation),
            fallback: observations
        )

        guard let selected = rankedMatches.first else {
            // True unknown: every observation was too low-confidence or scene-level
            let best = observations[0]
            return DetectedSubject(
                type: .unknown,
                confidence: best.confidence,
                classificationCandidates: candidates,
                attributes: SubjectAttributes(),
                pose: nil,
                boundingBox: nil,
                segmentationHint: nil
            )
        }

        return DetectedSubject(
            type: selected.type,
            confidence: selected.observation.confidence,
            classificationLabel: selected.canonicalLabel,
            classificationSource: selected.observation.source,
            classificationCandidates: candidates,
            attributes: SubjectAttributes(),
            pose: nil,
            boundingBox: nil,
            segmentationHint: nil
        )
    }

    /// Fallback classification for labels not in the canonical mapping table.
    ///
    /// Returns a `RankedSubjectMatch` if:
    /// - The label looks like a concrete object (not a scene, background, or abstract tag).
    /// - Confidence is above the source-adjusted threshold.
    ///
    /// Otherwise returns nil, and the observation falls back to candidates only.
    private func classifyUnmatched(
        observation: RawClassificationObservation,
        sourceBoost: Float
    ) -> RankedSubjectMatch? {
        let identifier = observation.identifier.lowercased()
        let isFromROI = observation.source?.hasPrefix("objectness_") == true
            || observation.source?.hasPrefix("attention_") == true
            || observation.source?.hasPrefix("saliency_") == true
            || observation.source == "center_crop"

        // Higher bar for full-image labels; ROI labels are more specific.
        let minConfidence: Float = isFromROI ? 0.12 : 0.18
        guard observation.confidence >= minConfidence else { return nil }

        // Reject scene / background / abstract labels that aren't concrete objects.
        guard !isSceneLevelLabel(identifier) else { return nil }

        // Best-effort type inference from label tokens.
        let inferredType = inferSubjectTypeFromLabel(identifier)
        let cleanLabel = normalizeUnmatchedLabel(identifier)

        return RankedSubjectMatch(
            observation: observation,
            type: inferredType,
            canonicalLabel: cleanLabel,
            score: observation.confidence * 0.85 * sourceBoost
        )
    }

    /// Labels that describe a scene, background, or medium rather than a discrete object.
    private func isSceneLevelLabel(_ identifier: String) -> Bool {
        let sceneKeywords: Set<String> = [
            "indoor", "outdoor", "room", "bedroom", "living room", "kitchen",
            "bathroom", "office", "classroom", "restaurant", "cafe", "store",
            "street", "road", "highway", "park", "garden", "beach", "mountain",
            "forest", "field", "desert", "sky", "water", "landscape", "city",
            "building", "house", "wall", "floor", "ceiling", "window", "door",
            "furniture", "shelf", "cabinet", "counter", "curtain", "carpet",
            "screenshot", "webpage", "website", "document", "text", "menu",
            "newspaper", "magazine", "book jacket", "poster", "comic", "diagram",
            "chart", "map", "drawing", "painting", "art", "photo", "pattern",
            "texture", "abstract", "graphic", "logo", "icon", "symbol"
        ]
        let tokens = Set(identifier.split(separator: " ").map(String.init))
        return sceneKeywords.contains(identifier) || !tokens.intersection(sceneKeywords).isEmpty
    }

    /// Simple heuristic to guess subject type from label tokens.
    private func inferSubjectTypeFromLabel(_ identifier: String) -> SubjectType {
        let animalTokens: Set<String> = [
            "cat", "kitten", "dog", "puppy", "bird", "fish", "horse",
            "cow", "sheep", "pig", "rabbit", "hamster", "turtle", "snake",
            "lizard", "frog", "bear", "deer", "squirrel", "fox", "wolf",
            "lion", "tiger", "elephant", "giraffe", "monkey", "ape", "gorilla",
            "whale", "dolphin", "shark", "eagle", "owl", "duck", "chicken"
        ]
        let personTokens: Set<String> = [
            "person", "people", "human", "man", "woman", "child", "baby",
            "boy", "girl", "adult", "teen", "elder", "face", "portrait"
        ]

        let tokens = tokenizeIdentifier(identifier)

        if !tokens.intersection(personTokens).isEmpty { return .person }
        if !tokens.intersection(animalTokens).isEmpty { return .animal }

        // Default: assume object for unmatched labels.
        // The system will adjust based on face/body detection later.
        return .object
    }
}

// MARK: - 主体事实提取

private extension VisionSubjectDetector {
    
    /// 计算更稳定的人物数量。
    ///
    /// 规则：
    /// - 人脸和人体数量都存在时，优先取较大的那个作为保守人数估计
    /// - 若两者都没有，则返回 0
    func resolvePersonCount(
        faceObservations: [VNFaceObservation],
        bodyObservations: [VNHumanBodyPoseObservation]
    ) -> Int {
        max(faceObservations.count, bodyObservations.count)
    }
    
    /// 推断单主体年龄提示。
    ///
    /// 第三版策略：
    /// - 默认不做基于 faceArea 的 child 推断
    /// - 因为这类规则极易把远景成人误判成 child
    /// - 年龄不属于当前生成链路中的必要主字段
    ///
    /// 后续如需恢复，必须基于更强信号，而不是简单面积阈值。
    func inferSingleAgeGroupHint(
        faceObservations: [VNFaceObservation],
        bodyObservations: [VNHumanBodyPoseObservation]
    ) -> String? {
        _ = faceObservations
        _ = bodyObservations
        return nil
    }
    
    /// 推断群体年龄构成。
    ///
    /// 第三版策略：
    /// - 仅作为弱提示字段
    /// - 不再输出 all_children
    /// - 只在“多人且脸尺寸差异显著”时，给出 mixed_adult_child 的弱提示
    /// - 否则一律返回 nil
    ///
    /// 原因：
    /// - mixed / all_children 的误判代价较大
    /// - 当前业务真正需要的是“主体数量稳定”和“主体别跑偏”
    func inferAgeCompositionHint(
        faceObservations: [VNFaceObservation]
    ) -> String? {
        guard faceObservations.count >= 2 else {
            return nil
        }
        
        let faceAreas = faceObservations
            .map { $0.boundingBox.width * $0.boundingBox.height }
            .sorted(by: >)
        
        guard let largest = faceAreas.first,
              let smallest = faceAreas.last,
              smallest > 0 else {
            return nil
        }
        
        let ratio = largest / smallest
        
        if ratio >= 2.2 {
            return "mixed_adult_child"
        }
        
        return nil
    }
    
    /// 推断低风险关系提示。
    ///
    /// 第三版策略：
    /// - 仅保留低风险关系
    /// - 不再输出 holding_child 这类高风险关系结论
    ///
    /// 当前仅保留：
    /// - group_pose
    /// - standing_beside
    func inferRelationshipHints(
        faceObservations: [VNFaceObservation],
        bodyObservations: [VNHumanBodyPoseObservation]
    ) -> [String] {
        var hints: [String] = []
        
        let personCount = resolvePersonCount(
            faceObservations: faceObservations,
            bodyObservations: bodyObservations
        )
        
        if personCount >= 2 {
            hints.append("group_pose")
        }
        
        if bodyObservations.count >= 2 {
            hints.append("standing_beside")
        }
        
        return dedupStrings(hints)
    }
    
    /// 合并多个人脸 / 人体姿态的 bounding box。
    func unionBoundingBox(
        faceObservations: [VNFaceObservation],
        bodyObservations: [VNHumanBodyPoseObservation]
    ) -> CGRect? {
        let faceBoxes = faceObservations.map(\.boundingBox)
        let bodyBoxes = bodyObservations.compactMap { makeBoundingBox(from: $0) }
        let allBoxes = faceBoxes + bodyBoxes
        
        guard let first = allBoxes.first else { return nil }
        
        return allBoxes.dropFirst().reduce(first) { partial, rect in
            partial.union(rect)
        }
    }
    
    /// 字符串数组去重并保持顺序。
    func dedupStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            guard !seen.contains(cleaned) else { continue }
            
            seen.insert(cleaned)
            result.append(cleaned)
        }
        
        return result
    }
}

// MARK: - 合并逻辑

private extension VisionSubjectDetector {
    
    /// 融合人脸、人体姿态和分类结果，生成最终主体。
    ///
    /// 第三版策略：
    /// - 主字段只保留稳定信息：
    ///   - type
    ///   - subjectCount
    ///   - posture
    ///   - boundingBox
    /// - 年龄 / 构成 / 关系只作为弱提示
    /// - 如果无人脸也无人体，则退回分类结果
    func mergeSubjects(
        faceObservations: [VNFaceObservation],
        bodyObservations: [VNHumanBodyPoseObservation],
        classified: DetectedSubject?
    ) -> DetectedSubject? {
        
        let faceCount = faceObservations.count
        let bodyCount = bodyObservations.count
        
        // 1. 完全没人脸、没人姿态：直接退回分类
        if faceCount == 0 && bodyCount == 0 {
            return classified
        }
        
        // 2. 强 animal/object + 只有小脸 + 没有人体姿态
        //    把这些脸视为背景噪声，避免猫图被误判成人
        if shouldTreatFacesAsBackgroundNoise(
            faces: faceObservations,
            bodyObservations: bodyObservations,
            classified: classified
        ) {
            return classified
        }
        
        // 3. 只有人脸，没有人体姿态
        //    只有在没有强 animal/object 证据时，才保守判 person
        if bodyCount == 0 && faceCount > 0 {
            if hasStrongAnimalEvidence(classified) || hasStrongObjectEvidence(classified) {
                return classified
            }
            
            let boundingBox = unionBoundingBox(
                faceObservations: faceObservations,
                bodyObservations: bodyObservations
            )
            
            let accessories: [String] = faceCount > 1 ? ["group portrait"] : []
            
            return DetectedSubject(
                type: .person,
                confidence: faceObservations.map(\.confidence).max() ?? 0.5,
                attributes: SubjectAttributes(
                    ageGroupHint: nil,
                    ageCompositionHint: inferAgeCompositionHint(faceObservations: faceObservations),
                    accessories: accessories,
                    subjectCount: faceCount,
                    relationshipHints: faceCount >= 2 ? ["group_pose"] : []
                ),
                pose: nil,
                boundingBox: boundingBox,
                segmentationHint: SegmentationHint(isForegroundClear: false)
            )
        }
        
        // 4. 只要有人体姿态，才强支持 person
        let personCount = resolvePersonCount(
            faceObservations: faceObservations,
            bodyObservations: bodyObservations
        )
        
        guard personCount > 0 else {
            return classified
        }
        
        let relationshipHints = inferRelationshipHints(
            faceObservations: faceObservations,
            bodyObservations: bodyObservations
        )
        
        let ageGroupHint = inferSingleAgeGroupHint(
            faceObservations: faceObservations,
            bodyObservations: bodyObservations
        )
        
        let ageCompositionHint = inferAgeCompositionHint(
            faceObservations: faceObservations
        )
        
        let pose = makeMergedPoseDescriptor(from: bodyObservations)
        let boundingBox = unionBoundingBox(
            faceObservations: faceObservations,
            bodyObservations: bodyObservations
        )
        
        let maxConfidence = max(
            faceObservations.map(\.confidence).max() ?? 0,
            bodyObservations.map(\.confidence).max() ?? 0
        )
        
        let accessories: [String] = personCount > 1 ? ["group portrait"] : []
        
        return DetectedSubject(
            type: .person,
            confidence: maxConfidence,
            attributes: SubjectAttributes(
                ageGroupHint: ageGroupHint,
                ageCompositionHint: ageCompositionHint,
                accessories: accessories,
                subjectCount: personCount,
                relationshipHints: relationshipHints
            ),
            pose: pose,
            boundingBox: boundingBox,
            segmentationHint: SegmentationHint(isForegroundClear: true)
        )
    }
}

// MARK: - 姿态与分类辅助

private extension VisionSubjectDetector {
    struct SubjectClassificationMatch {
        let type: SubjectType
        let canonicalLabel: String
        let subjectWeight: Float
    }

    struct RankedSubjectMatch {
        let observation: RawClassificationObservation
        let type: SubjectType
        let canonicalLabel: String
        let score: Float
    }

    func combinedClassifications(
        from rawVision: RawVisionAnalysis
    ) -> [RawClassificationObservation] {
        let all = rawVision.saliencyRegions.flatMap(\.classifications) + rawVision.classifications
        var bestByIdentifier: [String: RawClassificationObservation] = [:]

        for observation in all {
            let key = normalizedIdentifier(observation.identifier)
            let current = bestByIdentifier[key]
            let currentScore = current.map(weightedObservationScore(_:)) ?? -1
            if weightedObservationScore(observation) > currentScore {
                bestByIdentifier[key] = observation
            }
        }

        return bestByIdentifier.values.sorted {
            weightedObservationScore($0) > weightedObservationScore($1)
        }
    }

    func weightedObservationScore(_ observation: RawClassificationObservation) -> Float {
        let sourceBoost: Float = observation.source?.hasPrefix("saliency_") == true ? 1.15 : 1
        return observation.confidence * sourceBoost
    }

    func compactCandidates(
        preferred: [RawClassificationObservation],
        fallback: [RawClassificationObservation]
    ) -> [RawClassificationObservation] {
        var seen = Set<String>()
        var output: [RawClassificationObservation] = []

        for observation in preferred + fallback {
            let key = normalizedIdentifier(observation.identifier)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(observation)
            if output.count == 5 { break }
        }
        return output
    }

    func mapClassificationToSubject(identifier: String) -> SubjectClassificationMatch? {
        let mappings: [(aliases: [String], type: SubjectType, label: String, weight: Float)] = [
            // --- drinkware ---
            (["coffee mug", "coffee cup", "tea cup", "teacup", "mug", "cup", "tumbler", "drinkware", "drinking glass", "glassware", "glass", "wine glass", "beer glass", "goblet"], .object, "cup", 1.15),
            (["water bottle", "bottle", "flask", "wine bottle", "beer bottle"], .object, "bottle", 1.05),
            (["bowl", "dish", "plate"], .object, "dish", 0.95),

            // --- electronics ---
            (["smartphone", "mobile phone", "cellular telephone", "phone", "cellphone", "iphone"], .object, "phone", 1.05),
            (["laptop", "notebook computer"], .object, "laptop", 1.05),
            (["desktop computer", "computer monitor", "monitor", "computer", "display", "screen", "tv", "television", "television set"], .object, "computer", 1.0),
            (["keyboard", "computer keyboard", "keypad"], .object, "keyboard", 1.0),
            (["computer mouse", "mouse"], .object, "mouse", 0.95),
            (["remote control", "remote"], .object, "remote", 0.9),
            (["headphones", "headset", "earphones", "earbuds"], .object, "headphones", 0.9),
            (["camera", "digital camera", "video camera", "camcorder"], .object, "camera", 0.9),
            (["speaker", "loudspeaker", "audio speaker"], .object, "speaker", 0.85),
            (["watch", "wristwatch", "clock", "digital clock", "alarm clock"], .object, "clock", 0.85),

            // --- furniture ---
            (["chair", "stool", "sofa", "couch", "armchair", "bench", "seat"], .object, "chair", 0.45),
            (["table", "desk", "coffee table", "dining table", "nightstand"], .object, "table", 0.35),
            (["bed", "mattress"], .object, "bed", 0.4),
            (["lamp", "table lamp", "floor lamp", "desk lamp", "light"], .object, "lamp", 0.35),

            // --- stationery / office ---
            (["book", "notebook"], .object, "book", 1.0),
            (["document", "paper", "envelope"], .object, "document", 0.85),
            (["pen", "pencil", "marker"], .object, "pen", 0.7),
            (["scissors"], .object, "scissors", 0.8),

            // --- personal items ---
            (["handbag", "backpack", "bag", "purse", "suitcase", "luggage", "briefcase"], .object, "bag", 1.0),
            (["shoe", "sneaker", "boot", "footwear"], .object, "shoe", 1.0),
            (["glasses", "sunglasses", "eyeglasses", "spectacles"], .object, "glasses", 0.9),
            (["umbrella"], .object, "umbrella", 0.85),
            (["hat", "cap", "helmet"], .object, "hat", 0.8),
            (["clothing", "clothes", "apparel", "dress", "shirt", "jacket", "coat", "sweater", "t-shirt", "pants", "jeans", "skirt"], .object, "clothing", 0.7),

            // --- kitchen / food ---
            (["knife", "fork", "spoon", "cutlery", "chopsticks"], .object, "utensil", 0.8),
            (["apple", "banana", "orange", "fruit"], .object, "fruit", 0.85),
            (["pizza", "sandwich", "hamburger", "burger", "hot dog", "food", "meal", "cake", "bread", "pastry", "dessert", "cookie", "donut"], .object, "food", 0.75),
            (["coffee", "tea", "beverage", "drink", "juice", "soda", "espresso", "latte", "cappuccino"], .object, "beverage", 0.55),

            // --- sports / outdoors ---
            (["ball", "sports ball", "soccer ball", "basketball", "baseball", "tennis ball", "football", "volleyball"], .object, "ball", 0.9),
            (["bicycle", "bike", "motorcycle", "scooter"], .object, "bicycle", 0.85),
            (["skateboard", "surfboard", "snowboard", "skis"], .object, "sports_equipment", 0.8),
            (["racket", "tennis racket", "baseball bat", "golf club"], .object, "sports_equipment", 0.8),

            // --- vehicles ---
            (["car", "automobile", "vehicle", "truck", "bus", "van", "taxi", "suv"], .object, "car", 0.95),
            (["airplane", "aeroplane", "plane", "aircraft", "jet"], .object, "airplane", 0.9),
            (["boat", "ship", "sailboat", "vessel", "kayak", "canoe"], .object, "boat", 0.85),
            (["train", "railway", "subway", "locomotive"], .object, "train", 0.85),

            // --- plants ---
            (["potted plant", "plant", "flower", "flowerpot", "vase", "bouquet"], .object, "plant", 0.7),

            // --- instruments ---
            (["guitar", "piano", "violin", "drum", "musical instrument", "saxophone", "trumpet", "flute"], .object, "instrument", 0.85),

            // --- animals ---
            (["kitten", "feline", "cat"], .animal, "cat", 1.1),
            (["puppy", "canine", "dog"], .animal, "dog", 1.1),
            (["bird"], .animal, "bird", 1.0),
            (["horse"], .animal, "horse", 1.0),
            (["cow", "cattle"], .animal, "cow", 1.0),
            (["sheep"], .animal, "sheep", 1.0),
            (["fish"], .animal, "fish", 0.9),
            (["rabbit", "bunny"], .animal, "rabbit", 0.95),
            (["bear"], .animal, "bear", 0.9),
            (["butterfly", "insect"], .animal, "insect", 0.8),

            // --- people ---
            (["person", "people", "human", "portrait", "face"], .person, "person", 0.9),
        ]

        for mapping in mappings where matchesAny(identifier, aliases: mapping.aliases) {
            return SubjectClassificationMatch(
                type: mapping.type,
                canonicalLabel: mapping.label,
                subjectWeight: mapping.weight
            )
        }
        return nil
    }

    func matchesAny(_ identifier: String, aliases: [String]) -> Bool {
        let normalized = normalizedIdentifier(identifier)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        return aliases.contains { alias in
            let normalizedAlias = normalizedIdentifier(alias)
            return normalizedAlias.contains(" ")
                ? normalized.contains(normalizedAlias)
                : tokens.contains(normalizedAlias)
        }
    }

    func normalizedIdentifier(_ identifier: String) -> String {
        identifier
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func tokenizeIdentifier(_ identifier: String) -> Set<String> {
        Set(
            identifier
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map(String.init)
        )
    }

    /// Normalize an unmatched Vision label into a concise, human-readable form.
    func normalizeUnmatchedLabel(_ identifier: String) -> String {
        let normalized = normalizedIdentifier(identifier)

        // Remove common noise suffixes
        let noiseSuffixes = [" scene", " background", " indoor", " outdoor", " close up", " close-up"]
        var cleaned = normalized
        for suffix in noiseSuffixes where cleaned.hasSuffix(suffix) {
            cleaned = String(cleaned.dropLast(suffix.count))
        }

        return cleaned
    }

    func mapClassificationToSubjectType(identifier: String) -> SubjectType {
        mapClassificationToSubject(identifier: identifier)?.type ?? .unknown
    }
    
    func makeMergedPoseDescriptor(
        from observations: [VNHumanBodyPoseObservation]
    ) -> PoseDescriptor? {
        guard !observations.isEmpty else { return nil }
        
        if observations.count >= 2 {
            return PoseDescriptor(
                posture: "standing",
                action: "group pose",
                facing: nil,
                handState: nil
            )
        }
        
        let posture = inferSinglePosture(from: observations[0])
        
        return PoseDescriptor(
            posture: posture,
            action: nil,
            facing: nil,
            handState: nil
        )
    }
    
    func inferSinglePosture(
        from observation: VNHumanBodyPoseObservation
    ) -> String? {
        do {
            let points = try observation.recognizedPoints(.all)
            
            let leftShoulder = validPoint(points[.leftShoulder])
            let rightShoulder = validPoint(points[.rightShoulder])
            let leftHip = validPoint(points[.leftHip])
            let rightHip = validPoint(points[.rightHip])
            let leftKnee = validPoint(points[.leftKnee])
            let rightKnee = validPoint(points[.rightKnee])
            let leftAnkle = validPoint(points[.leftAnkle])
            let rightAnkle = validPoint(points[.rightAnkle])
            
            let shoulderY = averageY([leftShoulder, rightShoulder])
            let hipY = averageY([leftHip, rightHip])
            let kneeY = averageY([leftKnee, rightKnee])
            let ankleY = averageY([leftAnkle, rightAnkle])
            
            guard let shoulderY, let hipY else {
                return nil
            }
            
            let torsoHeight = abs(shoulderY - hipY)
            
            if let kneeY, let ankleY {
                let upperLegHeight = abs(hipY - kneeY)
                let lowerLegHeight = abs(kneeY - ankleY)
                let legHeight = upperLegHeight + lowerLegHeight
                
                if legHeight > torsoHeight * 0.9 {
                    return "standing"
                }
                
                if legHeight < torsoHeight * 0.65 {
                    return "sitting"
                }
            }
            
            if let kneeY {
                let hipToKnee = abs(hipY - kneeY)
                
                if hipToKnee < torsoHeight * 0.55 {
                    return "sitting"
                }
                
                if hipToKnee > torsoHeight * 0.85 {
                    return "standing"
                }
            }
            
            return nil
        } catch {
            return nil
        }
    }
    
    func validPoint(_ point: VNRecognizedPoint?) -> VNRecognizedPoint? {
        guard let point, point.confidence >= 0.25 else {
            return nil
        }
        return point
    }
    
    func averageY(_ points: [VNRecognizedPoint?]) -> CGFloat? {
        let valid = points.compactMap { $0?.location.y }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / CGFloat(valid.count)
    }
    
    func makeBoundingBox(from observation: VNHumanBodyPoseObservation) -> CGRect? {
        do {
            let recognizedPoints = try observation.recognizedPoints(.all)
            let validPoints = recognizedPoints.values.filter { $0.confidence > 0.1 }
            
            guard !validPoints.isEmpty else { return nil }
            
            let xs = validPoints.map(\.location.x)
            let ys = validPoints.map(\.location.y)
            
            guard let minX = xs.min(),
                  let maxX = xs.max(),
                  let minY = ys.min(),
                  let maxY = ys.max() else {
                return nil
            }
            
            return CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Face Noise / Classification Heuristics

private extension VisionSubjectDetector {
    
    func totalFaceArea(_ faces: [VNFaceObservation]) -> CGFloat {
        faces.reduce(0) { $0 + ($1.boundingBox.width * $1.boundingBox.height) }
    }
    
    func largestFaceArea(_ faces: [VNFaceObservation]) -> CGFloat {
        faces.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0
    }
    
    func hasStrongAnimalEvidence(_ classified: DetectedSubject?) -> Bool {
        guard let classified else { return false }
        return classified.type == .animal && classified.confidence >= 0.75
    }
    
    func hasStrongObjectEvidence(_ classified: DetectedSubject?) -> Bool {
        guard let classified else { return false }
        return classified.type == .object && classified.confidence >= 0.75
    }
    
    func shouldTreatFacesAsBackgroundNoise(
        faces: [VNFaceObservation],
        bodyObservations: [VNHumanBodyPoseObservation],
        classified: DetectedSubject?
    ) -> Bool {
        guard !faces.isEmpty else { return false }
        guard bodyObservations.isEmpty else { return false }
        guard hasStrongAnimalEvidence(classified) || hasStrongObjectEvidence(classified) else {
            return false
        }
        
        let totalArea = totalFaceArea(faces)
        let maxArea = largestFaceArea(faces)
        
        // 只有一些很小的人脸时，更像背景中的路人/头像/截图元素
        if totalArea < 0.10 && maxArea < 0.06 {
            return true
        }
        
        return false
    }
}
