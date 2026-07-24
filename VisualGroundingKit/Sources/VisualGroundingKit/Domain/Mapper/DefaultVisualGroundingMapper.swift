//
//  DefaultVisualGroundingMapper.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation
import CoreGraphics

/// 默认视觉结构化映射器。
///
/// 作用：
/// - 将底层 `ImageDescriptor`
/// - 映射为对外统一输出的 `VisualGroundingPayload`
///
/// 设计原则：
/// - 面向服务端可消费的结构化事实
/// - 不在客户端拼接最终 Prompt
/// - 不做过强语义脑补
/// - 优先保留可验证、可解释、可扩展的字段
public struct DefaultVisualGroundingMapper: VisualGroundingMapping {
    
    public init() {}
    
    public func map(_ descriptor: ImageDescriptor) -> VisualGroundingPayload {
        map(descriptor, includeDebug: true)
    }

    public func map(
        _ descriptor: ImageDescriptor,
        includeDebug: Bool
    ) -> VisualGroundingPayload {
        let textPayload = mapText(from: descriptor)
        let imageFacts = descriptor.imageFacts.map(mapImageFacts(_:))
        let contentType = mapContentType(from: descriptor, textPayload: textPayload)
        let subjects = mapSubjects(from: descriptor, contentType: contentType)
        let scene = descriptor.background.map(mapScene(_:))
        let style = descriptor.style.map(mapStyle(_:))
        let composition = descriptor.composition.map(mapComposition(_:))
            ?? inferComposition(from: descriptor)
        let motionHints = makeMotionHints(
            descriptor: descriptor,
            contentType: contentType,
            subjects: subjects,
            scene: scene,
            textPayload: textPayload
        )
        let preservationHints = makePreservationHints(
            descriptor: descriptor,
            contentType: contentType,
            textPayload: textPayload
        )
        let debug = includeDebug
            ? makeDebugPayload(
                descriptor: descriptor,
                subjects: subjects,
                scene: scene,
                style: style,
                contentType: contentType,
                textPayload: textPayload
            )
            : nil
        
        return VisualGroundingPayload(
            assetRole: descriptor.role.rawValue,
            contentType: contentType,
            subjects: subjects,
            scene: scene,
            style: style,
            composition: composition,
            text: textPayload,
            imageFacts: imageFacts,
            promptHints: descriptor.promptHints,
            motionHints: motionHints,
            preservationHints: preservationHints,
            debug: debug
        )
    }
}

// MARK: - Content Type

private extension DefaultVisualGroundingMapper {
    
    func mapContentType(
        from descriptor: ImageDescriptor,
        textPayload: TextPayload?
    ) -> ContentTypePayload {
        let primarySubject = descriptor.subjects.first
        let subjectType = primarySubject?.type
        let subjectCount = max(primarySubject?.attributes.subjectCount ?? descriptor.subjects.count, 0)
        
        let hasText = (textPayload?.textCount ?? 0) > 0
        let isHighText = (textPayload?.textDensity == .high)
        let isMediumText = (textPayload?.textDensity == .medium)
        
        let isDocumentLike = textPayload?.likelyTextSceneType == .documentPage
        let isScreenshotLike = textPayload?.likelyTextSceneType == .screenshotUI
        let hasOverlayUI = descriptor.imageFacts?.hasOverlayUI == true
        let isMixedPhotoWithUI = descriptor.imageFacts?.isMixedPhotoWithUI == true
        let shouldExposeScreenshotSecondaryType = isScreenshotLike || hasOverlayUI || isMixedPhotoWithUI
        let isUILayoutLike = isScreenshotLike || isDocumentLike
        let shouldPreferPhotoPrimaryType = isMixedPhotoWithUI
            && hasOverlayUI
            && (subjectType == .person || subjectType == .animal || subjectType == .object)
        
        let sceneType = descriptor.background?.sceneType?.lowercased()
        let sceneObjects = Set(descriptor.background?.environmentObjects.map { $0.lowercased() } ?? [])
        
        let primaryType: ContentPrimaryType
        
        if isDocumentLike {
            primaryType = .documentPage
        } else if isScreenshotLike && !shouldPreferPhotoPrimaryType {
            primaryType = .screenshotUI
        } else if subjectType == .person, subjectCount >= 2 {
            primaryType = .groupPhoto
        } else if subjectType == .person {
            primaryType = .portraitPhoto
        } else if subjectType == .animal {
            primaryType = .petPhoto
        } else if subjectType == .object, hasText, isHighText {
            primaryType = .documentPage
        } else if subjectType == .object,
                  sceneObjects.contains("laptop")
                    || sceneObjects.contains("book")
                    || sceneObjects.contains("pen")
                    || sceneObjects.contains("desk")
                    || sceneObjects.contains("table") {
            primaryType = .tabletopScene
        } else if sceneType == "outdoor natural scene" {
            primaryType = .landscapePhoto
        } else if sceneType == "indoor" || sceneType == "indoor bedroom" {
            primaryType = .indoorScene
        } else if sceneType == "city street" {
            primaryType = .outdoorScene
        } else if subjectType == .object {
            primaryType = .objectPhoto
        } else {
            primaryType = .unknown
        }
        
        var secondaryTypes: [ContentPrimaryType] = []
        
        if primaryType != .documentPage, isDocumentLike {
            secondaryTypes.append(.documentPage)
        }
        if primaryType != .screenshotUI, shouldExposeScreenshotSecondaryType {
            secondaryTypes.append(.screenshotUI)
        }
        if primaryType != .portraitPhoto, subjectType == .person, subjectCount == 1 {
            secondaryTypes.append(.portraitPhoto)
        }
        if primaryType != .groupPhoto, subjectType == .person, subjectCount >= 2 {
            secondaryTypes.append(.groupPhoto)
        }
        if primaryType != .petPhoto, subjectType == .animal {
            secondaryTypes.append(.petPhoto)
        }
        if primaryType != .landscapePhoto, sceneType == "outdoor natural scene", !hasText {
            secondaryTypes.append(.landscapePhoto)
        }
        if primaryType != .tabletopScene,
           subjectType == .object,
           (sceneObjects.contains("laptop") || sceneObjects.contains("book")) {
            secondaryTypes.append(.tabletopScene)
        }
        
        return ContentTypePayload(
            primaryType: primaryType,
            secondaryTypes: dedupContentTypes(secondaryTypes),
            isScreenshotLike: isScreenshotLike || hasOverlayUI || (hasText && isMediumText && subjectType != .person),
            isDocumentLike: isDocumentLike || (hasText && isHighText),
            isUILayoutLike: isUILayoutLike,
            isPhotoLike: !isDocumentLike && (!isScreenshotLike || shouldPreferPhotoPrimaryType),
            confidence: primarySubject?.confidence
        )
    }
    
    func dedupContentTypes(_ values: [ContentPrimaryType]) -> [ContentPrimaryType] {
        var seen = Set<ContentPrimaryType>()
        var result: [ContentPrimaryType] = []
        
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        
        return result
    }
}

// MARK: - Subjects

private extension DefaultVisualGroundingMapper {
    
    func mapSubjects(
        from descriptor: ImageDescriptor,
        contentType: ContentTypePayload
    ) -> [SubjectPayload] {
        let mapped = descriptor.subjects.enumerated().map { index, subject in
            mapSubject(subject, index: index, descriptor: descriptor, contentType: contentType)
        }
        
        guard !mapped.isEmpty else {
            if contentType.primaryType == .landscapePhoto || contentType.primaryType == .outdoorScene {
                return [
                    SubjectPayload(
                        id: "subject_0",
                        type: .sceneDominant,
                        count: 1,
                        coreLabel: "landscape scene",
                        semanticHints: ["scene_dominant"],
                        confidence: nil
                    )
                ]
            }
            return []
        }
        
        return mapped
    }
    
    func mapSubject(
        _ subject: DetectedSubject,
        index: Int,
        descriptor: ImageDescriptor,
        contentType: ContentTypePayload
    ) -> SubjectPayload {
        let count = max(subject.attributes.subjectCount ?? 1, 1)
        
        let appearanceTokens = dedupTokens(
            subject.attributes.hair
            + subject.attributes.clothing
            + subject.attributes.colors
        )
        
        let accessories = dedupTokens(subject.attributes.accessories)
        let interactionHints = dedupTokens(subject.attributes.relationshipHints)
        let semanticHints = makeSemanticHints(
            subject: subject,
            descriptor: descriptor,
            contentType: contentType
        )
        
        let bbox = subject.boundingBox.map { [mapBoundingBox($0)] } ?? []
        let actionHint = makeActionHint(from: subject, semanticHints: semanticHints, accessories: accessories)
        
        return SubjectPayload(
            id: "subject_\(index)",
            type: mapSubjectType(subject.type, contentType: contentType),
            count: count,
            coreLabel: makeCoreLabel(from: subject, descriptor: descriptor, contentType: contentType),
            canonicalLabel: subject.classificationLabel,
            candidateLabels: subject.classificationCandidates.map(mapClassificationCandidate(_:)),
            semanticHints: semanticHints,
            posture: subject.pose?.posture,
            postureType: subject.attributes.postureType,
            portraitFraming: subject.attributes.portraitFraming,
            gender: subject.attributes.gender,
            ageLevel: subject.attributes.ageLevel,
            subjectRefHints: dedupTokens(subject.attributes.subjectRefHints),
            subjectScaleHint: subject.attributes.subjectScaleHint,
            actionHint: actionHint,
            interactionHints: interactionHints,
            ageGroupHint: subject.attributes.ageGroupHint,
            ageCompositionHint: subject.attributes.ageCompositionHint,
            appearanceTokens: appearanceTokens,
            accessories: accessories,
            boundingBoxes: bbox,
            confidence: subject.confidence
        )
    }
    
    func mapSubjectType(
        _ type: SubjectType,
        contentType: ContentTypePayload
    ) -> SubjectTypePayload {
        switch type {
        case .person:
            return .person
        case .animal:
            return .animal
        case .object:
            return .object
        case .unknown:
            if contentType.primaryType == .landscapePhoto || contentType.primaryType == .outdoorScene {
                return .sceneDominant
            }
            return .unknown
        }
    }
    
    func makeCoreLabel(
        from subject: DetectedSubject,
        descriptor: ImageDescriptor,
        contentType: ContentTypePayload
    ) -> String {
        let count = max(subject.attributes.subjectCount ?? 1, 1)

        if subject.type != .person, let classificationLabel = subject.classificationLabel {
            return classificationLabel
        }
        
        switch subject.type {
        case .person:
            if let age = subject.attributes.ageGroupHint, age == "child" {
                return count > 1 ? "children" : "child"
            }
            switch count {
            case 1: return "person"
            case 2: return "two people"
            case 3: return "three people"
            default: return "group of people"
            }
            
        case .animal:
            let tags = rawClassifierHints(from: descriptor)
            if tags.contains(where: { $0.contains("cat") || $0.contains("kitten") || $0.contains("feline") }) {
                return count > 1 ? "cats" : "cat"
            }
            if tags.contains(where: { $0.contains("dog") || $0.contains("puppy") || $0.contains("canine") }) {
                return count > 1 ? "dogs" : "dog"
            }
            return count > 1 ? "animals" : "animal"
            
        case .object:
            let objectHints = descriptor.background?.environmentObjects.map { $0.lowercased() } ?? []
            if objectHints.contains("laptop") { return "laptop" }
            if objectHints.contains("book") { return count > 1 ? "books" : "book" }
            if objectHints.contains("computer") { return "computer" }
            return count > 1 ? "objects" : "object"
            
        case .unknown:
            switch contentType.primaryType {
            case .landscapePhoto:
                return "landscape scene"
            case .documentPage:
                return "document page"
            case .screenshotUI:
                return "ui screenshot"
            default:
                return "unknown subject"
            }
        }
    }

    func mapClassificationCandidate(
        _ candidate: RawClassificationObservation
    ) -> ClassificationCandidatePayload {
        ClassificationCandidatePayload(
            label: candidate.identifier,
            confidence: candidate.confidence,
            source: candidate.source
        )
    }
    
    func makeSemanticHints(
        subject: DetectedSubject,
        descriptor: ImageDescriptor,
        contentType: ContentTypePayload
    ) -> [String] {
        var hints: [String] = []
        
        if let age = subject.attributes.ageGroupHint {
            hints.append(age)
        }
        
        if let ageComposition = subject.attributes.ageCompositionHint {
            hints.append(ageComposition)
        }
        
        hints.append(contentsOf: subject.attributes.relationshipHints)
        
        let rawHints = rawClassifierHints(from: descriptor)
        
        switch subject.type {
        case .person:
            if rawHints.contains(where: { $0.contains("baby") }) {
                hints.append("baby_like")
            }
            if rawHints.contains(where: { $0.contains("child") }) {
                hints.append("child_like")
            }
            if rawHints.contains(where: { $0.contains("teen") }) {
                hints.append("teen_like")
            }
            if rawHints.contains(where: { $0.contains("adult") }) {
                hints.append("adult_like")
            }
            if rawHints.contains(where: { $0.contains("gown") || $0.contains("dress") }) {
                hints.append("dress_like")
            }
            if contentType.primaryType == .groupPhoto {
                hints.append("group_photo_like")
            }
            
        case .animal:
            if rawHints.contains(where: { $0.contains("cat") || $0.contains("kitten") || $0.contains("feline") }) {
                hints.append("pet_cat")
            }
            if rawHints.contains(where: { $0.contains("dog") || $0.contains("puppy") }) {
                hints.append("pet_dog")
            }
            
        case .object:
            if contentType.primaryType == .tabletopScene {
                hints.append("tabletop_object")
            }
            
        case .unknown:
            break
        }
        
        return dedupTokens(hints)
    }
    
    func makeActionHint(
        from subject: DetectedSubject,
        semanticHints: [String],
        accessories: [String]
    ) -> String? {
        let baseTokens = [
            subject.pose?.action,
            subject.pose?.facing,
            subject.attributes.facialExpression
        ].compactMap { $0 }
        
        var hints = baseTokens
        
        if accessories.contains(where: { $0.lowercased().contains("microphone") }) {
            hints.append("holding_microphone")
        }
        
        if semanticHints.contains("group_pose") {
            hints.append("group_pose")
        }
        
        return dedupTokens(hints).nonEmpty?.joined(separator: ", ")
    }
    
    func mapBoundingBox(_ rect: CGRect) -> BoundingBoxPayload {
        BoundingBoxPayload(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

// MARK: - Scene

private extension DefaultVisualGroundingMapper {
    
    func mapScene(_ background: BackgroundDescriptor) -> ScenePayload {
        let objects = dedupTokens(background.environmentObjects).map { name in
            SceneObjectPayload(
                name: normalizeSceneObjectName(name),
                confidence: nil,
                role: inferSceneObjectRole(name)
            )
        }
        
        return ScenePayload(
            sceneType: background.sceneType,
            subSceneType: inferSubSceneType(from: background),
            locationTags: dedupTokens(background.locationTags),
            environmentObjects: objects,
            lighting: background.lighting,
            timeOfDay: background.timeOfDay,
            weather: background.weather,
            spatialHints: inferSpatialHints(from: background),
            sceneRefHints: dedupTokens(background.sceneRefHints)
        )
    }
    
    func normalizeSceneObjectName(_ name: String) -> String {
        switch name.lowercased() {
        case "structures":
            return "structure"
        default:
            return name.lowercased()
        }
    }
    
    func inferSceneObjectRole(_ name: String) -> SceneObjectRole {
        switch name.lowercased() {
        case "river", "water", "sky", "trees", "flowers", "plants", "bed", "laptop", "book":
            return .anchor
        case "cloud", "clouds":
            return .dynamicCandidate
        default:
            return .backgroundSupport
        }
    }
    
    func inferSubSceneType(from background: BackgroundDescriptor) -> String? {
        let sceneType = background.sceneType?.lowercased()
        let objects = Set(background.environmentObjects.map { $0.lowercased() })
        
        if sceneType == "indoor", objects.contains("bed") || objects.contains("bedding") {
            return "bedroom"
        }
        if objects.contains("laptop") || objects.contains("book") || objects.contains("pen") {
            return "study_desk"
        }
        if objects.contains("river") || objects.contains("water") {
            return "riverside"
        }
        return nil
    }
    
    func inferSpatialHints(from background: BackgroundDescriptor) -> [String] {
        var hints: [String] = []
        let objects = Set(background.environmentObjects.map { $0.lowercased() })
        
        if background.sceneType == "outdoor natural scene" {
            hints.append("open_space")
        }
        if background.sceneType == "indoor" {
            hints.append("indoor_close_scene")
        }
        if objects.contains("sky") {
            hints.append("deep_background")
        }
        
        return dedupTokens(hints)
    }
}

// MARK: - Style

private extension DefaultVisualGroundingMapper {
    
    func mapStyle(_ style: StyleDescriptor) -> StylePayload {
        let renderTokens = dedupTokens(style.renderingHint)
        
        return StylePayload(
            visualStyleTokens: dedupTokens(style.visualStyle),
            moodTokens: dedupTokens(style.mood),
            colorTokens: dedupTokens(style.colorPalette),
            renderTokens: renderTokens,
            exposureHint: inferExposureHint(from: renderTokens),
            contrastHint: inferContrastHint(from: renderTokens),
            cleanlinessHint: inferCleanlinessHint(from: renderTokens)
        )
    }
    
    func inferExposureHint(from renderTokens: [String]) -> String? {
        if renderTokens.contains(where: { $0.lowercased().contains("bright") }) {
            return "bright"
        }
        if renderTokens.contains(where: { $0.lowercased().contains("dim") }) {
            return "dim"
        }
        return nil
    }
    
    func inferContrastHint(from renderTokens: [String]) -> String? {
        if renderTokens.contains(where: { $0.lowercased().contains("contrast") }) {
            return "high_contrast"
        }
        return nil
    }
    
    func inferCleanlinessHint(from renderTokens: [String]) -> String? {
        if renderTokens.contains(where: { $0.lowercased().contains("clean background") }) {
            return "clean_background"
        }
        return nil
    }
}

// MARK: - Composition

private extension DefaultVisualGroundingMapper {
    
    func mapComposition(_ composition: CompositionDescriptor) -> CompositionPayload {
        CompositionPayload(
            shotType: composition.shotType,
            cameraAngle: composition.angle,
            framing: composition.framing,
            subjectCoverage: nil,
            subjectCentered: nil,
            foregroundClear: nil,
            backgroundType: composition.backgroundType,
            subjectScaleHint: composition.subjectScaleHint
        )
    }
    
    func inferComposition(from descriptor: ImageDescriptor) -> CompositionPayload? {
        guard let subject = descriptor.subjects.first else { return nil }
        
        let coverage = subject.boundingBox.map { Float($0.width * $0.height) }
        let centered = subject.boundingBox.map { box in
            let centerX = box.midX
            return abs(centerX - 0.5) < 0.18
        }
        let foregroundClear = subject.segmentationHint?.isForegroundClear
        
        let shotType: String?
        if let coverage {
            if coverage >= 0.45 {
                shotType = "close_up"
            } else if coverage >= 0.18 {
                shotType = "medium_shot"
            } else {
                shotType = "wide_shot"
            }
        } else {
            shotType = nil
        }
        
        let framing: String?
        if centered == true {
            framing = "centered"
        } else {
            framing = nil
        }
        
        return CompositionPayload(
            shotType: shotType,
            cameraAngle: "eye_level",
            framing: framing,
            subjectCoverage: coverage,
            subjectCentered: centered,
            foregroundClear: foregroundClear,
            backgroundType: descriptor.composition?.backgroundType,
            subjectScaleHint: descriptor.composition?.subjectScaleHint ?? inferSubjectScaleHint(from: coverage)
        )
    }

    func inferSubjectScaleHint(from coverage: Float?) -> String? {
        guard let coverage else { return nil }

        switch coverage {
        case 0.35...:
            return "dominant"
        case 0.14...:
            return "medium"
        default:
            return "small"
        }
    }
}

private extension DefaultVisualGroundingMapper {
    func mapImageFacts(_ facts: ImageFactsDescriptor) -> ImageFactsPayload {
        ImageFactsPayload(
            environmentType: facts.environmentType,
            imageBrightness: facts.imageBrightness,
            imageSharpness: facts.imageSharpness,
            hasOverlayUI: facts.hasOverlayUI,
            isMixedPhotoWithUI: facts.isMixedPhotoWithUI,
            naturalTextBlocks: facts.naturalTextBlocks.map(\.text),
            uiTextBlocks: facts.uiTextBlocks.map(\.text)
        )
    }
}

// MARK: - Text

private extension DefaultVisualGroundingMapper {
    
    func mapText(from descriptor: ImageDescriptor) -> TextPayload? {
        let blocks = descriptor.textBlocks.map {
            RecognizedTextPayload(
                text: $0.text,
                boundingBox: mapBoundingBox($0.boundingBox)
            )
        }
        
        let textCount = blocks.count
        let density = inferTextDensity(textCount)
        let languageHints = inferDominantLanguageHints(from: blocks.map(\.text))
        let textSceneType = inferTextSceneType(descriptor: descriptor, textCount: textCount, density: density)
        
        guard textCount > 0 || textSceneType != .none else {
            return nil
        }
        
        let preserveLayout = textSceneType == .documentPage || textSceneType == .screenshotUI || textSceneType == .posterLike
        let avoidMutation = preserveLayout
        
        return TextPayload(
            rawTexts: blocks,
            textCount: textCount,
            textDensity: density,
            dominantLanguageHints: languageHints,
            likelyTextSceneType: textSceneType,
            shouldPreserveTextLayout: preserveLayout,
            shouldAvoidTextMutation: avoidMutation
        )
    }
    
    func inferTextDensity(_ textCount: Int) -> TextDensity {
        switch textCount {
        case 0:
            return .none
        case 1...5:
            return .low
        case 6...20:
            return .medium
        default:
            return .high
        }
    }
    
    func inferDominantLanguageHints(from texts: [String]) -> [String] {
        var hasChinese = false
        var hasLatin = false
        var hasJapanese = false
        var hasArabic = false
        var hasCyrillic = false
        
        for text in texts {
            for scalar in text.unicodeScalars {
                switch scalar.value {
                case 0x4E00...0x9FFF:
                    hasChinese = true
                case 0x3040...0x30FF:
                    hasJapanese = true
                case 0x0600...0x06FF:
                    hasArabic = true
                case 0x0400...0x04FF:
                    hasCyrillic = true
                case 0x0041...0x007A, 0x00C0...0x024F:
                    hasLatin = true
                default:
                    break
                }
            }
        }
        
        var result: [String] = []
        if hasChinese { result.append("zh") }
        if hasJapanese { result.append("ja") }
        if hasArabic { result.append("ar") }
        if hasCyrillic { result.append("cyrillic") }
        if hasLatin { result.append("latin") }
        
        if result.count > 1 {
            result.insert("mixed", at: 0)
        }
        
        return result
    }
    
    func inferTextSceneType(
        descriptor: ImageDescriptor,
        textCount: Int,
        density: TextDensity
    ) -> TextSceneType {
        let rawHints = rawClassifierHints(from: descriptor)
        
        let hasScreenshotHint = rawHints.contains(where: { $0.contains("screenshot") })
        let hasDocumentHint = rawHints.contains(where: { $0.contains("document") })
        let hasChartHint = rawHints.contains(where: { $0.contains("chart") || $0.contains("diagram") })
        
        if textCount == 0 {
            return .none
        }
        
        if hasDocumentHint && density == .high {
            return .documentPage
        }
        
        if hasScreenshotHint && density != .none {
            return .screenshotUI
        }
        
        if hasChartHint && density != .none {
            return .mixed
        }
        
        if density == .high {
            return .documentPage
        }
        
        if density == .medium {
            return .screenshotUI
        }
        
        return .mixed
    }
}

// MARK: - Motion Hints

private extension DefaultVisualGroundingMapper {
    
    func makeMotionHints(
        descriptor: ImageDescriptor,
        contentType: ContentTypePayload,
        subjects: [SubjectPayload],
        scene: ScenePayload?,
        textPayload: TextPayload?
    ) -> MotionHintsPayload {
        let primarySubject = subjects.first
        
        var subjectMotionCandidates: [String] = []
        var environmentMotionCandidates: [String] = []
        var cameraMotionCandidates: [String] = []
        
        switch primarySubject?.type {
        case .person:
            subjectMotionCandidates.append("subtle_body_motion")
            if resolvedPosture(for: primarySubject) == "sitting"
                || resolvedPosture(for: primarySubject) == "seated" {
                subjectMotionCandidates.append("seated_micro_motion")
            }
            if primarySubject?.appearanceTokens.contains(where: { $0.contains("hair") }) == true {
                subjectMotionCandidates.append("hair_sway")
            }
            
        case .animal:
            subjectMotionCandidates.append("pet_micro_motion")
            subjectMotionCandidates.append("subtle_head_motion")
            
        case .sceneDominant:
            break
            
        case .object:
            break
            
        case .unknown, .none:
            break
        }
        
        let objectNames = scene?.environmentObjects.map { $0.name.lowercased() } ?? []
        if objectNames.contains(where: { ["river", "water"].contains($0) }) {
            environmentMotionCandidates.append("water_flow")
        }
        if objectNames.contains(where: { ["trees", "plants", "flowers", "shrubs"].contains($0) }) {
            environmentMotionCandidates.append("leaves_sway")
        }
        if objectNames.contains("sky"), scene?.weather != "rainy", scene?.weather != "snowy" {
            environmentMotionCandidates.append("cloud_drift")
        }
        
        switch contentType.primaryType {
        case .portraitPhoto, .groupPhoto, .petPhoto:
            cameraMotionCandidates = ["slow_push_in", "static"]
        case .landscapePhoto, .outdoorScene:
            cameraMotionCandidates = ["static", "slow_push_in"]
        case .documentPage, .screenshotUI:
            cameraMotionCandidates = ["static"]
        case .tabletopScene, .objectPhoto:
            cameraMotionCandidates = ["static", "slow_push_in"]
        default:
            cameraMotionCandidates = ["static"]
        }
        
        let profile = inferMotionProfile(
            contentType: contentType,
            subjects: subjects,
            scene: scene,
            textPayload: textPayload
        )
        
        let riskLevel = inferMotionRiskLevel(
            contentType: contentType,
            textPayload: textPayload,
            subjects: subjects
        )
        
        return MotionHintsPayload(
            subjectMotionCandidates: dedupTokens(subjectMotionCandidates),
            environmentMotionCandidates: dedupTokens(environmentMotionCandidates),
            cameraMotionCandidates: dedupTokens(cameraMotionCandidates),
            recommendedMotionProfile: profile,
            motionRiskLevel: riskLevel
        )
    }
    
    func inferMotionProfile(
        contentType: ContentTypePayload,
        subjects: [SubjectPayload],
        scene: ScenePayload?,
        textPayload: TextPayload?
    ) -> MotionProfile {
        let primarySubject = subjects.first
        let shouldPreferPhotoMotionProfile = contentType.primaryType == .portraitPhoto
            || contentType.primaryType == .groupPhoto
            || contentType.primaryType == .petPhoto
            || contentType.primaryType == .landscapePhoto
            || contentType.primaryType == .outdoorScene
            || contentType.primaryType == .indoorScene
            || contentType.primaryType == .objectPhoto
            || contentType.primaryType == .tabletopScene
        
        if textPayload?.shouldPreserveTextLayout == true, !shouldPreferPhotoMotionProfile {
            return .screenshotAmbientEffect
        }
        
        switch contentType.primaryType {
        case .portraitPhoto:
            return .subtlePortraitMotion
        case .groupPhoto:
            return .groupMicroMotion
        case .petPhoto:
            return .petMicroMotion
        case .landscapePhoto:
            if scene?.environmentObjects.contains(where: { $0.name == "river" || $0.name == "water" }) == true {
                return .waterFlowMotion
            }
            return .landscapeAmbientMotion
        case .tabletopScene, .objectPhoto:
            return .tabletopMicroMotion
        case .documentPage, .screenshotUI:
            return .staticPreserve
        default:
            if primarySubject?.type == .person {
                return .subtlePortraitMotion
            }
            return .staticPreserve
        }
    }
    
    func resolvedPosture(for subject: SubjectPayload?) -> String? {
        subject?.postureType?.lowercased() ?? subject?.posture?.lowercased()
    }
    
    func inferMotionRiskLevel(
        contentType: ContentTypePayload,
        textPayload: TextPayload?,
        subjects: [SubjectPayload]
    ) -> MotionRiskLevel {
        if textPayload?.shouldPreserveTextLayout == true {
            return .high
        }
        
        if contentType.primaryType == .groupPhoto || (subjects.first?.count ?? 0) >= 3 {
            return .medium
        }
        
        switch contentType.primaryType {
        case .documentPage, .screenshotUI:
            return .high
        case .portraitPhoto, .petPhoto, .landscapePhoto:
            return .low
        default:
            return .medium
        }
    }
}

// MARK: - Preservation

private extension DefaultVisualGroundingMapper {
    
    func makePreservationHints(
        descriptor: ImageDescriptor,
        contentType: ContentTypePayload,
        textPayload: TextPayload?
    ) -> PreservationHintsPayload {
        let hasPersonOrAnimal = descriptor.subjects.contains {
            $0.type == .person || $0.type == .animal
        }
        
        return PreservationHintsPayload(
            preserveSubjectIdentity: hasPersonOrAnimal,
            preserveSubjectCount: hasPersonOrAnimal,
            preserveBackground: !contentType.isDocumentLike,
            preserveMainLayout: true,
            preserveTextLayout: textPayload?.shouldPreserveTextLayout ?? false,
            avoidLargeSceneChange: true,
            avoidSubjectReplacement: hasPersonOrAnimal
        )
    }
}

// MARK: - Debug

private extension DefaultVisualGroundingMapper {
    
    func makeDebugPayload(
        descriptor: ImageDescriptor,
        subjects: [SubjectPayload],
        scene: ScenePayload?,
        style: StylePayload?,
        contentType: ContentTypePayload,
        textPayload: TextPayload?
    ) -> DebugPayload {
        let subjectSummary = subjects.map(\.coreLabel).joined(separator: "|")
        let sceneSummary = scene?.sceneType ?? "nil"
        let styleSummary = style?.visualStyleTokens.joined(separator: "|") ?? "nil"
        let textSummary = textPayload.map { "\($0.likelyTextSceneType.rawValue):\($0.textCount)" } ?? "nil"
        
        let analyzerSummary = """
        role=\(descriptor.role.rawValue),
        contentType=\(contentType.primaryType.rawValue),
        subjects=\(subjectSummary.isEmpty ? "nil" : subjectSummary),
        scene=\(sceneSummary),
        style=\(styleSummary),
        text=\(textSummary)
        """
        
        return DebugPayload(
            analyzerSummary: analyzerSummary,
            rawSubjectLabels: rawSubjectLabels(from: descriptor),
            rawBackgroundLabels: rawBackgroundLabels(from: descriptor),
            rawStyleLabels: rawStyleLabels(from: descriptor),
            topClassifications: allRawClassifications(from: descriptor)
                .prefix(12)
                .map(mapClassificationCandidate(_:)),
            selectedSubjectLabel: descriptor.subjects.first?.classificationLabel,
            selectedSubjectSource: descriptor.subjects.first?.classificationSource,
            saliencyRegionCount: descriptor.rawVision?.saliencyRegions.count ?? 0,
            saliencyRegions: descriptor.rawVision?.saliencyRegions.map {
                mapBoundingBox($0.boundingBox)
            } ?? []
        )
    }
    
    func rawSubjectLabels(from descriptor: ImageDescriptor) -> [String] {
        allRawClassifications(from: descriptor).prefix(12).map {
            "\($0.identifier)(\(String(format: "%.2f", $0.confidence)))"
        }
    }
    
    func rawBackgroundLabels(from descriptor: ImageDescriptor) -> [String] {
        var values: [String] = []
        
        if let sceneType = descriptor.background?.sceneType {
            values.append(sceneType)
        }
        values.append(contentsOf: descriptor.background?.locationTags ?? [])
        values.append(contentsOf: descriptor.background?.environmentObjects ?? [])
        if let weather = descriptor.background?.weather {
            values.append(weather)
        }
        if let lighting = descriptor.background?.lighting {
            values.append(lighting)
        }
        
        return dedupTokens(values)
    }
    
    func rawStyleLabels(from descriptor: ImageDescriptor) -> [String] {
        var values: [String] = []
        values.append(contentsOf: descriptor.style?.visualStyle ?? [])
        values.append(contentsOf: descriptor.style?.mood ?? [])
        values.append(contentsOf: descriptor.style?.colorPalette ?? [])
        values.append(contentsOf: descriptor.style?.renderingHint ?? [])
        return dedupTokens(values)
    }
    
    func rawClassifierHints(from descriptor: ImageDescriptor) -> [String] {
        dedupTokens(
            allRawClassifications(from: descriptor).map(\.identifier)
            + rawBackgroundLabels(from: descriptor)
            + rawStyleLabels(from: descriptor)
        )
    }

    func allRawClassifications(
        from descriptor: ImageDescriptor
    ) -> [RawClassificationObservation] {
        guard let rawVision = descriptor.rawVision else { return [] }
        let all = rawVision.saliencyRegions.flatMap(\.classifications) + rawVision.classifications
        return all.sorted {
            let lhsBoost: Float = $0.source?.hasPrefix("saliency_") == true ? 1.15 : 1
            let rhsBoost: Float = $1.source?.hasPrefix("saliency_") == true ? 1.15 : 1
            return $0.confidence * lhsBoost > $1.confidence * rhsBoost
        }
    }
}

// MARK: - Helpers

private extension DefaultVisualGroundingMapper {
    
    func dedupTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            
            seen.insert(key)
            result.append(cleaned)
        }
        
        return result
    }
}

private extension Array {
    var nonEmpty: [Element]? {
        isEmpty ? nil : self
    }
}
