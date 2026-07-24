//
//  ImageDescriptor.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import CoreGraphics
import Foundation

public struct ImageDescriptor: Identifiable, Sendable, Codable {
    public let id: UUID
    public let role: InputImageAsset.ImageRole
    public let subjects: [DetectedSubject]
    public let background: BackgroundDescriptor?
    public let style: StyleDescriptor?
    public let composition: CompositionDescriptor?
    public let textBlocks: [RecognizedTextBlock]
    public let rawVision: RawVisionAnalysis?
    public let imageFacts: ImageFactsDescriptor?
    public let promptHints: PromptHintsPayload?
    public let quality: ImageQualityDescriptor?
    public let embedding: [Float]?
    
    public init(
        id: UUID,
        role: InputImageAsset.ImageRole,
        subjects: [DetectedSubject],
        background: BackgroundDescriptor?,
        style: StyleDescriptor?,
        composition: CompositionDescriptor?,
        textBlocks: [RecognizedTextBlock],
        rawVision: RawVisionAnalysis? = nil,
        imageFacts: ImageFactsDescriptor? = nil,
        promptHints: PromptHintsPayload? = nil,
        quality: ImageQualityDescriptor?,
        embedding: [Float]?
    ) {
        self.id = id
        self.role = role
        self.subjects = subjects
        self.background = background
        self.style = style
        self.composition = composition
        self.textBlocks = textBlocks
        self.rawVision = rawVision
        self.imageFacts = imageFacts
        self.promptHints = promptHints
        self.quality = quality
        self.embedding = embedding
    }
}

public struct DetectedSubject: Sendable, Codable {
    public let type: SubjectType
    public let confidence: Float
    public let classificationLabel: String?
    public let classificationSource: String?
    public let classificationCandidates: [RawClassificationObservation]
    public let attributes: SubjectAttributes
    public let pose: PoseDescriptor?
    public let boundingBox: CGRect?
    public let segmentationHint: SegmentationHint?
    
    public init(
        type: SubjectType,
        confidence: Float,
        classificationLabel: String? = nil,
        classificationSource: String? = nil,
        classificationCandidates: [RawClassificationObservation] = [],
        attributes: SubjectAttributes,
        pose: PoseDescriptor?,
        boundingBox: CGRect?,
        segmentationHint: SegmentationHint?
    ) {
        self.type = type
        self.confidence = confidence
        self.classificationLabel = classificationLabel
        self.classificationSource = classificationSource
        self.classificationCandidates = classificationCandidates
        self.attributes = attributes
        self.pose = pose
        self.boundingBox = boundingBox
        self.segmentationHint = segmentationHint
    }
}

public enum SubjectType: String, Sendable, Codable {
    case person
    case animal
    case object
    case unknown
}

public struct SubjectAttributes: Sendable, Codable {
    public let genderHint: String?
    
    /// 单主体年龄提示。
    ///
    /// 例如：
    /// - child
    /// - adult
    ///
    /// 注意：
    /// 这个字段只适合“单主体”或非常明确的情况。
    public let ageGroupHint: String?
    
    /// 多主体年龄构成提示。
    ///
    /// 例如：
    /// - all_children
    /// - mixed_adult_child
    ///
    /// 注意：
    /// 这是对“群体构成”的保守推断，不代表精确年龄识别。
    public let ageCompositionHint: String?
    
    public let hair: [String]
    public let clothing: [String]
    public let accessories: [String]
    public let colors: [String]
    
    public let facialExpression: String?
    public let identityConsistencyKey: String?
    public let postureType: String?
    public let portraitFraming: String?
    public let gender: String?
    public let ageLevel: String?
    public let subjectRefHints: [String]
    public let subjectScaleHint: String?
    
    /// 主体数量
    public let subjectCount: Int?
    
    /// 主体关系提示。
    ///
    /// 例如：
    /// - holding_child
    /// - standing_beside
    /// - group_pose
    ///
    /// 这里只保留“观察到的关系事实”，
    /// 不做剧情推断。
    public let relationshipHints: [String]
    
    public init(
        genderHint: String? = nil,
        ageGroupHint: String? = nil,
        ageCompositionHint: String? = nil,
        hair: [String] = [],
        clothing: [String] = [],
        accessories: [String] = [],
        colors: [String] = [],
        facialExpression: String? = nil,
        identityConsistencyKey: String? = nil,
        postureType: String? = nil,
        portraitFraming: String? = nil,
        gender: String? = nil,
        ageLevel: String? = nil,
        subjectRefHints: [String] = [],
        subjectScaleHint: String? = nil,
        subjectCount: Int? = nil,
        relationshipHints: [String] = []
    ) {
        self.genderHint = genderHint
        self.ageGroupHint = ageGroupHint
        self.ageCompositionHint = ageCompositionHint
        self.hair = hair
        self.clothing = clothing
        self.accessories = accessories
        self.colors = colors
        self.facialExpression = facialExpression
        self.identityConsistencyKey = identityConsistencyKey
        self.postureType = postureType
        self.portraitFraming = portraitFraming
        self.gender = gender
        self.ageLevel = ageLevel
        self.subjectRefHints = subjectRefHints
        self.subjectScaleHint = subjectScaleHint
        self.subjectCount = subjectCount
        self.relationshipHints = relationshipHints
    }
}

public struct PoseDescriptor: Sendable, Codable {
    public let posture: String?
    public let action: String?
    public let facing: String?
    public let handState: String?
    
    public init(
        posture: String? = nil,
        action: String? = nil,
        facing: String? = nil,
        handState: String? = nil
    ) {
        self.posture = posture
        self.action = action
        self.facing = facing
        self.handState = handState
    }
}

public struct SegmentationHint: Sendable, Codable {
    public let isForegroundClear: Bool
    
    public init(isForegroundClear: Bool) {
        self.isForegroundClear = isForegroundClear
    }
}

public struct BackgroundDescriptor: Sendable, Codable {
    public let sceneType: String?
    public let locationTags: [String]
    public let environmentObjects: [String]
    public let sceneRefHints: [String]
    public let weather: String?
    public let lighting: String?
    public let timeOfDay: String?
    
    public init(
        sceneType: String? = nil,
        locationTags: [String] = [],
        environmentObjects: [String] = [],
        sceneRefHints: [String] = [],
        weather: String? = nil,
        lighting: String? = nil,
        timeOfDay: String? = nil
    ) {
        self.sceneType = sceneType
        self.locationTags = locationTags
        self.environmentObjects = environmentObjects
        self.sceneRefHints = sceneRefHints
        self.weather = weather
        self.lighting = lighting
        self.timeOfDay = timeOfDay
    }
}

public struct StyleDescriptor: Sendable, Codable {
    public let visualStyle: [String]
    public let mood: [String]
    public let colorPalette: [String]
    public let renderingHint: [String]
    
    public init(
        visualStyle: [String] = [],
        mood: [String] = [],
        colorPalette: [String] = [],
        renderingHint: [String] = []
    ) {
        self.visualStyle = visualStyle
        self.mood = mood
        self.colorPalette = colorPalette
        self.renderingHint = renderingHint
    }
}

public struct CompositionDescriptor: Sendable, Codable {
    public let shotType: String?
    public let angle: String?
    public let framing: String?
    public let subjectPosition: String?
    public let depthHint: String?
    public let backgroundType: String?
    public let subjectScaleHint: String?
    
    public init(
        shotType: String? = nil,
        angle: String? = nil,
        framing: String? = nil,
        subjectPosition: String? = nil,
        depthHint: String? = nil,
        backgroundType: String? = nil,
        subjectScaleHint: String? = nil
    ) {
        self.shotType = shotType
        self.angle = angle
        self.framing = framing
        self.subjectPosition = subjectPosition
        self.depthHint = depthHint
        self.backgroundType = backgroundType
        self.subjectScaleHint = subjectScaleHint
    }
}

public struct RecognizedTextBlock: Sendable, Codable, Hashable {
    public let text: String
    public let boundingBox: CGRect
    
    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public struct ImageQualityDescriptor: Sendable, Codable {
    public let isBlurry: Bool
    public let exposure: String?
    
    public init(isBlurry: Bool, exposure: String? = nil) {
        self.isBlurry = isBlurry
        self.exposure = exposure
    }
}
