//
//  CompositeScenePlan.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public struct CompositeScenePlan: Sendable {
    public let mainSubject: SceneSubject?
    public let secondarySubjects: [SceneSubject]
    public let environment: SceneEnvironment?
    public let relationship: SubjectRelationship?
    public let composition: SceneComposition?
    public let style: SceneStyle?
    public let constraints: [PromptConstraint]
    public let intent: GenerationIntent
    
    public init(
        mainSubject: SceneSubject?,
        secondarySubjects: [SceneSubject],
        environment: SceneEnvironment?,
        relationship: SubjectRelationship?,
        composition: SceneComposition?,
        style: SceneStyle?,
        constraints: [PromptConstraint],
        intent: GenerationIntent
    ) {
        self.mainSubject = mainSubject
        self.secondarySubjects = secondarySubjects
        self.environment = environment
        self.relationship = relationship
        self.composition = composition
        self.style = style
        self.constraints = constraints
        self.intent = intent
    }
}

public struct SceneSubject: Sendable {
    public let type: String
    public let coreDescription: String
    public let appearanceTokens: [String]
    public let actionTokens: [String]
    public let preserveIdentity: Bool
    
    public init(
        type: String,
        coreDescription: String,
        appearanceTokens: [String],
        actionTokens: [String],
        preserveIdentity: Bool
    ) {
        self.type = type
        self.coreDescription = coreDescription
        self.appearanceTokens = appearanceTokens
        self.actionTokens = actionTokens
        self.preserveIdentity = preserveIdentity
    }
}

public struct SubjectRelationship: Sendable {
    public let spatial: String?
    public let interaction: String?
    public let emotionalTone: String?
    
    public init(
        spatial: String? = nil,
        interaction: String? = nil,
        emotionalTone: String? = nil
    ) {
        self.spatial = spatial
        self.interaction = interaction
        self.emotionalTone = emotionalTone
    }
}

public struct SceneEnvironment: Sendable {
    public let place: String?
    public let props: [String]
    public let lighting: [String]
    public let atmosphere: [String]
    
    public init(
        place: String? = nil,
        props: [String] = [],
        lighting: [String] = [],
        atmosphere: [String] = []
    ) {
        self.place = place
        self.props = props
        self.lighting = lighting
        self.atmosphere = atmosphere
    }
}

public struct SceneComposition: Sendable {
    public let shotType: String?
    public let cameraAngle: String?
    public let lensStyle: String?
    public let framing: String?
    
    public init(
        shotType: String? = nil,
        cameraAngle: String? = nil,
        lensStyle: String? = nil,
        framing: String? = nil
    ) {
        self.shotType = shotType
        self.cameraAngle = cameraAngle
        self.lensStyle = lensStyle
        self.framing = framing
    }
}

public struct SceneStyle: Sendable {
    public let styleTokens: [String]
    // 单独管理分为
    public let moodTokens: [String]
    public let qualityTokens: [String]
    // 只管渲染提示
    public let renderTokens: [String]
    // 只管色彩
    public let colorTokens: [String]
    
    public init(
        styleTokens: [String] = [],
        moodTokens: [String] = [],
        qualityTokens: [String] = [],
        renderTokens: [String] = [],
        colorTokens: [String] = []
    ) {
        self.styleTokens = styleTokens
        self.moodTokens = moodTokens
        self.qualityTokens = qualityTokens
        self.renderTokens = renderTokens
        self.colorTokens = colorTokens
    }
}

public struct PromptConstraint: Sendable {
    public let type: ConstraintType
    public let value: String
    
    public init(type: ConstraintType, value: String) {
        self.type = type
        self.value = value
    }
    
    public enum ConstraintType: Sendable {
        case preserveMainSubject
        case keepFaceNatural
        case avoidExtraLimbs
        case avoidTextArtifacts
        case keepBackgroundClean
        case styleConsistency
        case custom
    }
}
