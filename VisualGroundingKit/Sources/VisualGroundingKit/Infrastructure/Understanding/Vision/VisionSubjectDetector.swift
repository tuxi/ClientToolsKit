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

        if let merged = mergeSubjects(
            faceObservations: rawVision.faces,
            bodyObservations: rawVision.humanBodies,
            classified: classifiedSubject,
            portraitAttributes: portraitAttributes
        ) {
            return [merged]
        }

        return [
            DetectedSubject(
                type: .unknown,
                confidence: 0.2,
                attributes: SubjectAttributes(),
                pose: nil,
                boundingBox: nil,
                segmentationHint: nil
            )
        ]
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

        let rankedMatches = observations.compactMap { observation -> RankedSubjectMatch? in
            guard observation.confidence >= 0.03,
                  let match = mapClassificationToSubject(identifier: observation.identifier) else {
                return nil
            }
            let sourceBoost: Float = observation.source?.hasPrefix("saliency_") == true ? 1.25 : 1
            return RankedSubjectMatch(
                observation: observation,
                type: match.type,
                canonicalLabel: match.canonicalLabel,
                score: observation.confidence * match.subjectWeight * sourceBoost
            )
        }
        .sorted { $0.score > $1.score }

        let candidates = compactCandidates(
            preferred: rankedMatches.map(\.observation),
            fallback: observations
        )

        guard let selected = rankedMatches.first else {
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
            (["coffee mug", "coffee cup", "tea cup", "teacup", "mug", "cup", "tumbler", "drinkware", "drinking glass", "glassware", "glass"], .object, "cup", 1.15),
            (["water bottle", "bottle", "flask"], .object, "bottle", 1.05),
            (["smartphone", "mobile phone", "cellular telephone", "phone"], .object, "phone", 1.05),
            (["laptop", "notebook computer"], .object, "laptop", 1.05),
            (["desktop computer", "computer monitor", "monitor", "computer"], .object, "computer", 1.0),
            (["keyboard"], .object, "keyboard", 1.0),
            (["computer mouse", "mouse"], .object, "mouse", 0.95),
            (["book", "notebook"], .object, "book", 1.0),
            (["handbag", "backpack", "bag"], .object, "bag", 1.0),
            (["shoe", "sneaker", "boot"], .object, "shoe", 1.0),
            (["car", "automobile", "vehicle"], .object, "car", 0.95),
            (["document", "screenshot"], .object, "document", 0.85),
            (["chair", "stool", "sofa", "couch"], .object, "chair", 0.45),
            (["table", "desk"], .object, "table", 0.35),
            (["kitten", "feline", "cat"], .animal, "cat", 1.1),
            (["puppy", "canine", "dog"], .animal, "dog", 1.1),
            (["bird"], .animal, "bird", 1.0),
            (["horse"], .animal, "horse", 1.0),
            (["cow", "cattle"], .animal, "cow", 1.0),
            (["sheep"], .animal, "sheep", 1.0),
            (["person", "people", "human", "portrait"], .person, "person", 0.9)
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
