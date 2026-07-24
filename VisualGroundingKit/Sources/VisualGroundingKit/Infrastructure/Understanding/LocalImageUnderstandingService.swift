//
//  LocalImageUnderstandingService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public final class LocalImageUnderstandingService: ImageUnderstandingService {
    private let subjectDetector: SubjectDetecting
    private let backgroundAnalyzer: BackgroundAnalyzing
    private let styleAnalyzer: StyleAnalyzing
    private let ocrAnalyzer: OCRAnalyzing
    private let rawVisionAnalyzer: RawVisionAnalyzing
    private let imageFactsAnalyzer: ImageFactsAnalyzing
    private let portraitAttributeAnalyzer: PortraitAttributeAnalyzing
    private let backgroundComplexityAnalyzer: BackgroundComplexityAnalyzing
    private let subjectHintAnalyzer: SubjectHintAnalyzing
    private let environmentObjectRefiner: EnvironmentObjectRefining
    
    public init(
        subjectDetector: SubjectDetecting,
        backgroundAnalyzer: BackgroundAnalyzing,
        styleAnalyzer: StyleAnalyzing,
        ocrAnalyzer: OCRAnalyzing,
        rawVisionAnalyzer: RawVisionAnalyzing = MockRawVisionAnalyzer(),
        imageFactsAnalyzer: ImageFactsAnalyzing = MockImageFactsAnalyzer(),
        portraitAttributeAnalyzer: PortraitAttributeAnalyzing = MockPortraitAttributeAnalyzer(),
        backgroundComplexityAnalyzer: BackgroundComplexityAnalyzing = MockBackgroundComplexityAnalyzer(),
        subjectHintAnalyzer: SubjectHintAnalyzing = MockSubjectHintAnalyzer(),
        environmentObjectRefiner: EnvironmentObjectRefining = MockEnvironmentObjectRefiner()
    ) {
        self.subjectDetector = subjectDetector
        self.backgroundAnalyzer = backgroundAnalyzer
        self.styleAnalyzer = styleAnalyzer
        self.ocrAnalyzer = ocrAnalyzer
        self.rawVisionAnalyzer = rawVisionAnalyzer
        self.imageFactsAnalyzer = imageFactsAnalyzer
        self.portraitAttributeAnalyzer = portraitAttributeAnalyzer
        self.backgroundComplexityAnalyzer = backgroundComplexityAnalyzer
        self.subjectHintAnalyzer = subjectHintAnalyzer
        self.environmentObjectRefiner = environmentObjectRefiner
    }
    
    public func analyze(image: InputImageAsset) async throws -> ImageDescriptor {
        async let rawVision = rawVisionAnalyzer.analyze(in: image.image)
        let resolvedRawVision = try await rawVision
        async let background = backgroundAnalyzer.analyze(
            in: image.image,
            rawVision: resolvedRawVision
        )
        async let style = styleAnalyzer.analyze(
            in: image.image,
            rawVision: resolvedRawVision
        )
        let portraitAttributes = try await portraitAttributeAnalyzer.analyze(
            image: image.image,
            rawVision: resolvedRawVision
        )
        let resolvedTexts = try await ocrAnalyzer.recognize(
            in: image.image,
            rawVision: resolvedRawVision
        )
        let resolvedSubjects = try await subjectDetector.detect(
            in: image.image,
            rawVision: resolvedRawVision,
            portraitAttributes: portraitAttributes
        )
        let resolvedSubjectHints = try await subjectHintAnalyzer.analyze(
            subjects: resolvedSubjects,
            rawVision: resolvedRawVision
        )
        let resolvedBackgroundType = try await backgroundComplexityAnalyzer.analyze(
            image: image.image,
            subjectBoxes: resolvedSubjects.compactMap(\.boundingBox),
            saliencyRegions: resolvedRawVision.saliencyRegions
        )
        let resolvedImageFacts = try await imageFactsAnalyzer.analyze(
            image: image.image,
            rawVision: resolvedRawVision
        )
        let refinedSubjects = mergeSubjectHints(
            resolvedSubjectHints,
            into: resolvedSubjects
        )
        let baseBackground = try await background
        let refinedBackground = try await mergeBackground(
            background: baseBackground,
            rawVision: resolvedRawVision
        )
        let composition = resolvedBackgroundType.map {
            CompositionDescriptor(
                backgroundType: $0.rawValue,
                subjectScaleHint: refinedSubjects.first?.attributes.subjectScaleHint
            )
        }
        let promptHints = derivePromptHints(
            subjects: refinedSubjects,
            background: refinedBackground,
            composition: composition
        )

        return ImageDescriptor(
            id: image.id,
            role: image.role,
            subjects: refinedSubjects,
            background: refinedBackground,
            style: try await style,
            composition: composition,
            textBlocks: resolvedTexts,
            rawVision: resolvedRawVision,
            imageFacts: resolvedImageFacts,
            promptHints: promptHints,
            quality: nil,
            embedding: nil
        )
    }
}

private extension LocalImageUnderstandingService {
    func mergeSubjectHints(
        _ hints: [SubjectHintResult],
        into subjects: [DetectedSubject]
    ) -> [DetectedSubject] {
        zip(subjects, hints).map { subject, hint in
            DetectedSubject(
                type: subject.type,
                confidence: subject.confidence,
                classificationLabel: subject.classificationLabel,
                classificationSource: subject.classificationSource,
                classificationCandidates: subject.classificationCandidates,
                attributes: SubjectAttributes(
                    genderHint: subject.attributes.genderHint,
                    ageGroupHint: subject.attributes.ageGroupHint,
                    ageCompositionHint: subject.attributes.ageCompositionHint,
                    hair: subject.attributes.hair,
                    clothing: subject.attributes.clothing,
                    accessories: subject.attributes.accessories,
                    colors: subject.attributes.colors,
                    facialExpression: subject.attributes.facialExpression,
                    identityConsistencyKey: subject.attributes.identityConsistencyKey,
                    postureType: subject.attributes.postureType,
                    portraitFraming: subject.attributes.portraitFraming,
                    gender: subject.attributes.gender,
                    ageLevel: hint.ageLevel?.rawValue ?? subject.attributes.ageLevel,
                    subjectRefHints: hint.subjectRefHints.isEmpty ? subject.attributes.subjectRefHints : hint.subjectRefHints,
                    subjectScaleHint: hint.subjectScaleHint ?? subject.attributes.subjectScaleHint,
                    subjectCount: subject.attributes.subjectCount,
                    relationshipHints: subject.attributes.relationshipHints
                ),
                pose: subject.pose,
                boundingBox: subject.boundingBox,
                segmentationHint: subject.segmentationHint
            )
        }
    }

    func mergeBackground(
        background: BackgroundDescriptor?,
        rawVision: RawVisionAnalysis
    ) async throws -> BackgroundDescriptor? {
        let refined = try await environmentObjectRefiner.refine(
            background: background,
            rawVision: rawVision
        )

        guard background != nil || !refined.environmentObjects.isEmpty || !refined.sceneRefHints.isEmpty else {
            return background
        }

        return BackgroundDescriptor(
            sceneType: background?.sceneType,
            locationTags: background?.locationTags ?? [],
            environmentObjects: refined.environmentObjects,
            sceneRefHints: refined.sceneRefHints,
            weather: background?.weather,
            lighting: background?.lighting,
            timeOfDay: background?.timeOfDay
        )
    }

    func derivePromptHints(
        subjects: [DetectedSubject],
        background: BackgroundDescriptor?,
        composition: CompositionDescriptor?
    ) -> PromptHintsPayload? {
        let subject = subjects.first
        let sceneObjects = Set(background?.environmentObjects.map { $0.lowercased() } ?? [])
        let sceneRefHints = Set(background?.sceneRefHints ?? [])

        let subjectRefStyle: String?
        if subject?.type == .person, (subject?.attributes.subjectCount ?? subjects.count) >= 2 {
            subjectRefStyle = "multi_person"
        } else if subject?.type == .person, subject?.attributes.ageLevel == SubjectAgeLevel.child.rawValue {
            subjectRefStyle = "single_person_child_like"
        } else if subject?.type == .person {
            subjectRefStyle = "single_person_generic"
        } else if subject?.type == .animal {
            subjectRefStyle = "animal_subject"
        } else {
            subjectRefStyle = nil
        }

        let subjectSceneBalance: String?
        switch composition?.subjectScaleHint {
        case "dominant":
            subjectSceneBalance = "subject_dominant"
        case "medium":
            subjectSceneBalance = "balanced"
        case "small":
            subjectSceneBalance = "scene_dominant"
        default:
            subjectSceneBalance = nil
        }

        let motionPreference: String?
        if subject?.type == .person, (subject?.attributes.subjectCount ?? subjects.count) >= 2 {
            motionPreference = "group_micro_motion"
        } else if subject?.type == .person {
            motionPreference = "portrait_micro_motion"
        } else if !sceneObjects.isEmpty || !sceneRefHints.isEmpty {
            motionPreference = "ambient_scene_motion"
        } else {
            motionPreference = nil
        }

        if subjectRefStyle == nil, subjectSceneBalance == nil, motionPreference == nil {
            return nil
        }

        return PromptHintsPayload(
            subjectRefStyle: subjectRefStyle,
            subjectSceneBalance: subjectSceneBalance,
            motionPreference: motionPreference
        )
    }
}
