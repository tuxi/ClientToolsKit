//
//  VisualGroundingPayload.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation
import CoreGraphics

/// VisualGroundingKit v1 顶层输出。
///
/// 设计目标：
/// - 面向服务端的视频 / 图像生成链路
/// - 输出结构化视觉事实，而不是客户端直接拼接 Prompt
/// - 将“事实层 / 提示层 / 保持约束层 / 调试层”明确拆开
///
/// 使用建议：
/// - 客户端负责提取与整理
/// - 服务端负责做 Prompt Enhance / 模型适配 / 厂商适配
public struct VisualGroundingPayload: Sendable, Hashable, Codable {
    
    /// Schema 版本号。
    ///
    /// 便于服务端后续做兼容处理。
    public let schemaVersion: String
    
    /// 当前图片在输入集合中的角色。
    ///
    /// 例如：
    /// - mainSubject
    /// - backgroundReference
    /// - styleReference
    public let assetRole: String
    
    /// 内容类型判断。
    ///
    /// 这是服务端路由的重要依据：
    /// - portraitPhoto
    /// - landscapePhoto
    /// - screenshotUI
    /// - documentPage
    public let contentType: ContentTypePayload
    
    /// 主体信息。
    ///
    /// 一张图可能有多个主体，但 v1 仍以“主主体 + 若干补充主体”为主。
    public let subjects: [SubjectPayload]
    
    /// 场景信息。
    public let scene: ScenePayload?
    
    /// 风格信息。
    public let style: StylePayload?
    
    /// 构图信息。
    public let composition: CompositionPayload?
    
    /// OCR 与文本场景信息。
    public let text: TextPayload?

    /// 图像事实层。
    public let imageFacts: ImageFactsPayload?

    /// 服务端消费型轻量 prompt hints。
    public let promptHints: PromptHintsPayload?
    
    /// 动态候选提示。
    ///
    /// 注意：
    /// 这不是最终 prompt，
    /// 只是告诉服务端“这张图更适合怎么动”。
    public let motionHints: MotionHintsPayload?
    
    /// 保持约束提示。
    ///
    /// 用于约束服务端不要把主体、背景、文字、布局改坏。
    public let preservationHints: PreservationHintsPayload?
    
    /// 调试信息。
    ///
    /// 不建议服务端主逻辑依赖这些字段，
    /// 主要用于日志与排障。
    public let debug: DebugPayload?
    
    public init(
        schemaVersion: String = "visual_grounding.v1",
        assetRole: String,
        contentType: ContentTypePayload,
        subjects: [SubjectPayload] = [],
        scene: ScenePayload? = nil,
        style: StylePayload? = nil,
        composition: CompositionPayload? = nil,
        text: TextPayload? = nil,
        imageFacts: ImageFactsPayload? = nil,
        promptHints: PromptHintsPayload? = nil,
        motionHints: MotionHintsPayload? = nil,
        preservationHints: PreservationHintsPayload? = nil,
        debug: DebugPayload? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.assetRole = assetRole
        self.contentType = contentType
        self.subjects = subjects
        self.scene = scene
        self.style = style
        self.composition = composition
        self.text = text
        self.imageFacts = imageFacts
        self.promptHints = promptHints
        self.motionHints = motionHints
        self.preservationHints = preservationHints
        self.debug = debug
    }
}

// MARK: - Content Type

/// 内容类型层。
///
/// 这是顶层内容路由字段，决定服务端后续更适合走：
/// - 人像微动
/// - 风景动态
/// - UI 截图动态
/// - 文档版面保留
public struct ContentTypePayload: Sendable, Hashable, Codable {
    
    /// 主内容类型。
    public let primaryType: ContentPrimaryType
    
    /// 次级内容类型补充。
    public let secondaryTypes: [ContentPrimaryType]
    
    /// 是否像截图。
    public let isScreenshotLike: Bool
    
    /// 是否像文档页。
    public let isDocumentLike: Bool
    
    /// 是否像 UI 界面。
    public let isUILayoutLike: Bool
    
    /// 是否像真实拍摄照片。
    public let isPhotoLike: Bool
    
    /// 分类置信度。
    public let confidence: Float?
    
    public init(
        primaryType: ContentPrimaryType,
        secondaryTypes: [ContentPrimaryType] = [],
        isScreenshotLike: Bool = false,
        isDocumentLike: Bool = false,
        isUILayoutLike: Bool = false,
        isPhotoLike: Bool = true,
        confidence: Float? = nil
    ) {
        self.primaryType = primaryType
        self.secondaryTypes = secondaryTypes
        self.isScreenshotLike = isScreenshotLike
        self.isDocumentLike = isDocumentLike
        self.isUILayoutLike = isUILayoutLike
        self.isPhotoLike = isPhotoLike
        self.confidence = confidence
    }
}

public enum ContentPrimaryType: String, Sendable, Hashable, Codable {
    case portraitPhoto
    case groupPhoto
    case petPhoto
    case landscapePhoto
    case tabletopScene
    case indoorScene
    case outdoorScene
    case screenshotUI
    case documentPage
    case posterLike
    case objectPhoto
    case unknown
}

// MARK: - Subject

/// 主体层。
///
/// 注意：
/// - v1 不要求把主体描述得非常“聪明”
/// - 但必须尽量避免只输出 subject / object 这种过空信息
/// - 主体层是服务端生成视频 Prompt 的核心输入之一
public struct SubjectPayload: Sendable, Hashable, Codable {
    
    /// 主体唯一标识。
    ///
    /// 可以是 "subject_0" / "subject_1"
    public let id: String
    
    /// 主体类型。
    public let type: SubjectTypePayload
    
    /// 主体数量。
    ///
    /// 对“群体主体”可以是 2 / 3 / 4...
    public let count: Int
    
    /// 主体核心标签。
    ///
    /// 例如：
    /// - person
    /// - three people
    /// - cat
    /// - laptop
    public let coreLabel: String

    /// 经过本地分类归一化后的具体主体标签，例如 cup / cat / laptop。
    public let canonicalLabel: String?

    /// 低置信度场景下可供上层模型参考的精简候选。
    public let candidateLabels: [ClassificationCandidatePayload]
    
    /// 弱语义提示。
    ///
    /// 例如：
    /// - baby
    /// - family_group
    /// - performer_like
    /// - pet_cat
    ///
    /// 注意：
    /// 这里只是提示，不应作为绝对事实。
    public let semanticHints: [String]
    
    /// 主体姿态。
    ///
    /// 例如：
    /// - standing
    /// - sitting
    /// - seated
    /// - lying
    public let posture: String?

    /// 人像姿态分桶。
    public let postureType: String?

    /// 人像景别分桶。
    public let portraitFraming: String?

    /// 保守性别字段。
    public let gender: String?

    /// 保守年龄段字段。
    public let ageLevel: String?

    /// 服务端消费型主体称呼弱提示。
    public let subjectRefHints: [String]

    /// 主体在画面中的主导程度。
    public let subjectScaleHint: String?
    
    /// 静态动作提示。
    ///
    /// 例如：
    /// - group_pose
    /// - holding_microphone
    /// - selfie_pose
    public let actionHint: String?
    
    /// 主体之间关系或交互提示。
    ///
    /// 例如：
    /// - group_pose
    /// - standing_beside
    /// - facing_camera_like
    public let interactionHints: [String]
    
    /// 单主体年龄提示。
    public let ageGroupHint: String?
    
    /// 多主体年龄构成提示。
    public let ageCompositionHint: String?
    
    /// 外观相关 token。
    ///
    /// 例如：
    /// - dress
    /// - jeans
    /// - child_clothing
    public let appearanceTokens: [String]
    
    /// 配饰或手持物。
    ///
    /// 例如：
    /// - microphone
    /// - hat
    /// - glasses
    public let accessories: [String]
    
    /// 主体框。
    public let boundingBoxes: [BoundingBoxPayload]
    
    /// 主体识别置信度。
    public let confidence: Float?
    
    public init(
        id: String,
        type: SubjectTypePayload,
        count: Int,
        coreLabel: String,
        canonicalLabel: String? = nil,
        candidateLabels: [ClassificationCandidatePayload] = [],
        semanticHints: [String] = [],
        posture: String? = nil,
        postureType: String? = nil,
        portraitFraming: String? = nil,
        gender: String? = nil,
        ageLevel: String? = nil,
        subjectRefHints: [String] = [],
        subjectScaleHint: String? = nil,
        actionHint: String? = nil,
        interactionHints: [String] = [],
        ageGroupHint: String? = nil,
        ageCompositionHint: String? = nil,
        appearanceTokens: [String] = [],
        accessories: [String] = [],
        boundingBoxes: [BoundingBoxPayload] = [],
        confidence: Float? = nil
    ) {
        self.id = id
        self.type = type
        self.count = count
        self.coreLabel = coreLabel
        self.canonicalLabel = canonicalLabel
        self.candidateLabels = candidateLabels
        self.semanticHints = semanticHints
        self.posture = posture
        self.postureType = postureType
        self.portraitFraming = portraitFraming
        self.gender = gender
        self.ageLevel = ageLevel
        self.subjectRefHints = subjectRefHints
        self.subjectScaleHint = subjectScaleHint
        self.actionHint = actionHint
        self.interactionHints = interactionHints
        self.ageGroupHint = ageGroupHint
        self.ageCompositionHint = ageCompositionHint
        self.appearanceTokens = appearanceTokens
        self.accessories = accessories
        self.boundingBoxes = boundingBoxes
        self.confidence = confidence
    }
}

public struct ClassificationCandidatePayload: Sendable, Hashable, Codable {
    public let label: String
    public let confidence: Float
    public let source: String?

    public init(label: String, confidence: Float, source: String? = nil) {
        self.label = label
        self.confidence = confidence
        self.source = source
    }
}

public enum SubjectTypePayload: String, Sendable, Hashable, Codable {
    case person
    case animal
    case object
    case sceneDominant
    case unknown
}

public struct BoundingBoxPayload: Sendable, Hashable, Codable {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat
    
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Scene

/// 场景层。
///
/// 用来表达环境事实与服务端可用的场景锚点。
public struct ScenePayload: Sendable, Hashable, Codable {
    
    /// 主场景类型。
    ///
    /// 例如：
    /// - outdoor natural scene
    /// - city street
    /// - indoor bedroom
    /// - tabletop scene
    public let sceneType: String?
    
    /// 子场景类型。
    ///
    /// 例如：
    /// - bedroom
    /// - stage
    /// - study_desk
    public let subSceneType: String?
    
    /// 位置标签。
    ///
    /// 例如：
    /// - outdoor
    /// - street
    /// - natural
    public let locationTags: [String]
    
    /// 环境物体。
    public let environmentObjects: [SceneObjectPayload]
    
    /// 光照提示。
    public let lighting: String?
    
    /// 时间段提示。
    public let timeOfDay: String?
    
    /// 天气提示。
    public let weather: String?
    
    /// 空间提示。
    ///
    /// 例如：
    /// - open_space
    /// - shallow_depth
    /// - indoor_close_scene
    public let spatialHints: [String]

    /// 服务端消费型场景弱提示。
    public let sceneRefHints: [String]
    
    public init(
        sceneType: String? = nil,
        subSceneType: String? = nil,
        locationTags: [String] = [],
        environmentObjects: [SceneObjectPayload] = [],
        lighting: String? = nil,
        timeOfDay: String? = nil,
        weather: String? = nil,
        spatialHints: [String] = [],
        sceneRefHints: [String] = []
    ) {
        self.sceneType = sceneType
        self.subSceneType = subSceneType
        self.locationTags = locationTags
        self.environmentObjects = environmentObjects
        self.lighting = lighting
        self.timeOfDay = timeOfDay
        self.weather = weather
        self.spatialHints = spatialHints
        self.sceneRefHints = sceneRefHints
    }
}

public struct SceneObjectPayload: Sendable, Hashable, Codable {
    
    /// 环境元素名称。
    ///
    /// 例如：
    /// - river
    /// - sky
    /// - laptop
    /// - book
    /// - bed
    public let name: String
    
    /// 置信度。
    public let confidence: Float?
    
    /// 该元素在场景中的角色。
    public let role: SceneObjectRole
    
    public init(
        name: String,
        confidence: Float? = nil,
        role: SceneObjectRole = .backgroundSupport
    ) {
        self.name = name
        self.confidence = confidence
        self.role = role
    }
}

public enum SceneObjectRole: String, Sendable, Hashable, Codable {
    case anchor
    case dynamicCandidate
    case backgroundSupport
    case layoutSensitive
}

// MARK: - Style

/// 风格层。
///
/// 表达“从图片观察到的风格倾向”，
/// 而不是用户主动要求的风格。
public struct StylePayload: Sendable, Hashable, Codable {
    public let visualStyleTokens: [String]
    public let moodTokens: [String]
    public let colorTokens: [String]
    public let renderTokens: [String]
    
    /// 曝光提示。
    public let exposureHint: String?
    
    /// 对比度提示。
    public let contrastHint: String?
    
    /// 画面干净程度提示。
    public let cleanlinessHint: String?
    
    public init(
        visualStyleTokens: [String] = [],
        moodTokens: [String] = [],
        colorTokens: [String] = [],
        renderTokens: [String] = [],
        exposureHint: String? = nil,
        contrastHint: String? = nil,
        cleanlinessHint: String? = nil
    ) {
        self.visualStyleTokens = visualStyleTokens
        self.moodTokens = moodTokens
        self.colorTokens = colorTokens
        self.renderTokens = renderTokens
        self.exposureHint = exposureHint
        self.contrastHint = contrastHint
        self.cleanlinessHint = cleanlinessHint
    }
}

// MARK: - Composition

/// 构图层。
///
/// v1 不需要非常复杂，但建议先把结构占好。
public struct CompositionPayload: Sendable, Hashable, Codable {
    
    /// 取景方式。
    ///
    /// 例如：
    /// - close_up
    /// - medium_shot
    /// - full_body
    public let shotType: String?
    
    /// 镜头角度。
    ///
    /// 例如：
    /// - eye_level
    /// - top_down
    /// - low_angle
    public let cameraAngle: String?
    
    /// 画面构图。
    ///
    /// 例如：
    /// - centered
    /// - left_weighted
    /// - portrait_like
    public let framing: String?
    
    /// 主体覆盖比例。
    ///
    /// 范围建议 0~1。
    public let subjectCoverage: Float?
    
    /// 主体是否居中。
    public let subjectCentered: Bool?
    
    /// 前景是否清晰。
    public let foregroundClear: Bool?

    /// 背景结构分桶。
    public let backgroundType: String?

    /// 主体在构图中的主导程度。
    public let subjectScaleHint: String?
    
    public init(
        shotType: String? = nil,
        cameraAngle: String? = nil,
        framing: String? = nil,
        subjectCoverage: Float? = nil,
        subjectCentered: Bool? = nil,
        foregroundClear: Bool? = nil,
        backgroundType: String? = nil,
        subjectScaleHint: String? = nil
    ) {
        self.shotType = shotType
        self.cameraAngle = cameraAngle
        self.framing = framing
        self.subjectCoverage = subjectCoverage
        self.subjectCentered = subjectCentered
        self.foregroundClear = foregroundClear
        self.backgroundType = backgroundType
        self.subjectScaleHint = subjectScaleHint
    }
}

// MARK: - Text

/// OCR 与文本场景层。
///
/// 不只是保存 OCR 结果，还要表达：
/// - 这是不是截图
/// - 这是不是文档
/// - 文本布局是否应该被保留
public struct TextPayload: Sendable, Hashable, Codable {
    
    /// 原始 OCR 文本块。
    public let rawTexts: [RecognizedTextPayload]
    
    /// 文本块数量。
    public let textCount: Int
    
    /// 文本密度。
    public let textDensity: TextDensity
    
    /// 主语言提示。
    ///
    /// 例如：
    /// - zh
    /// - en
    /// - mixed
    public let dominantLanguageHints: [String]
    
    /// 文本场景类型。
    public let likelyTextSceneType: TextSceneType
    
    /// 是否应保留文字布局。
    public let shouldPreserveTextLayout: Bool
    
    /// 是否应避免文字被改写。
    public let shouldAvoidTextMutation: Bool
    
    public init(
        rawTexts: [RecognizedTextPayload] = [],
        textCount: Int,
        textDensity: TextDensity,
        dominantLanguageHints: [String] = [],
        likelyTextSceneType: TextSceneType,
        shouldPreserveTextLayout: Bool,
        shouldAvoidTextMutation: Bool
    ) {
        self.rawTexts = rawTexts
        self.textCount = textCount
        self.textDensity = textDensity
        self.dominantLanguageHints = dominantLanguageHints
        self.likelyTextSceneType = likelyTextSceneType
        self.shouldPreserveTextLayout = shouldPreserveTextLayout
        self.shouldAvoidTextMutation = shouldAvoidTextMutation
    }
}

public struct RecognizedTextPayload: Sendable, Hashable, Codable {
    public let text: String
    public let boundingBox: BoundingBoxPayload?
    
    public init(text: String, boundingBox: BoundingBoxPayload? = nil) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public enum TextDensity: String, Sendable, Hashable, Codable {
    case none
    case low
    case medium
    case high
}

public enum TextSceneType: String, Sendable, Hashable, Codable {
    case none
    case screenshotUI
    case documentPage
    case posterLike
    case mixed
}

// MARK: - Motion Hints

/// 动态候选层。
///
/// 注意：
/// 这不是最终 prompt，
/// 只是告诉服务端“建议朝哪个方向生成动态”。
public struct MotionHintsPayload: Sendable, Hashable, Codable {
    
    /// 主体动态候选。
    ///
    /// 例如：
    /// - blink_like
    /// - subtle_body_motion
    /// - hair_sway
    /// - hand_wave_like
    public let subjectMotionCandidates: [String]
    
    /// 环境动态候选。
    ///
    /// 例如：
    /// - water_flow
    /// - leaves_sway
    /// - cloud_drift
    /// - light_flicker
    public let environmentMotionCandidates: [String]
    
    /// 镜头动态候选。
    ///
    /// 例如：
    /// - static
    /// - slow_push_in
    /// - slow_pull_out
    public let cameraMotionCandidates: [String]
    
    /// 推荐的动态策略。
    public let recommendedMotionProfile: MotionProfile
    
    /// 动态风险等级。
    ///
    /// 风险高表示这张图更容易被模型改坏。
    public let motionRiskLevel: MotionRiskLevel
    
    public init(
        subjectMotionCandidates: [String] = [],
        environmentMotionCandidates: [String] = [],
        cameraMotionCandidates: [String] = [],
        recommendedMotionProfile: MotionProfile,
        motionRiskLevel: MotionRiskLevel
    ) {
        self.subjectMotionCandidates = subjectMotionCandidates
        self.environmentMotionCandidates = environmentMotionCandidates
        self.cameraMotionCandidates = cameraMotionCandidates
        self.recommendedMotionProfile = recommendedMotionProfile
        self.motionRiskLevel = motionRiskLevel
    }
}

public enum MotionProfile: String, Sendable, Hashable, Codable {
    case subtlePortraitMotion
    case groupMicroMotion
    case petMicroMotion
    case landscapeAmbientMotion
    case waterFlowMotion
    case tabletopMicroMotion
    case screenshotAmbientEffect
    case staticPreserve
}

public enum MotionRiskLevel: String, Sendable, Hashable, Codable {
    case low
    case medium
    case high
}

// MARK: - Preservation Hints

/// 保持约束层。
///
/// 用于告诉服务端：
/// 哪些元素必须尽量保持不变。
public struct PreservationHintsPayload: Sendable, Hashable, Codable {
    
    /// 保持主体身份一致。
    public let preserveSubjectIdentity: Bool
    
    /// 保持主体数量一致。
    public let preserveSubjectCount: Bool
    
    /// 保持背景一致。
    public let preserveBackground: Bool
    
    /// 保持主要布局一致。
    public let preserveMainLayout: Bool
    
    /// 保持文字布局一致。
    public let preserveTextLayout: Bool
    
    /// 避免大幅场景变化。
    public let avoidLargeSceneChange: Bool
    
    /// 避免主体被替换。
    public let avoidSubjectReplacement: Bool
    
    public init(
        preserveSubjectIdentity: Bool = true,
        preserveSubjectCount: Bool = true,
        preserveBackground: Bool = true,
        preserveMainLayout: Bool = true,
        preserveTextLayout: Bool = false,
        avoidLargeSceneChange: Bool = true,
        avoidSubjectReplacement: Bool = true
    ) {
        self.preserveSubjectIdentity = preserveSubjectIdentity
        self.preserveSubjectCount = preserveSubjectCount
        self.preserveBackground = preserveBackground
        self.preserveMainLayout = preserveMainLayout
        self.preserveTextLayout = preserveTextLayout
        self.avoidLargeSceneChange = avoidLargeSceneChange
        self.avoidSubjectReplacement = avoidSubjectReplacement
    }
}

// MARK: - Debug

/// 调试层。
///
/// 给日志和排障使用，不建议作为主业务逻辑的强依赖。
public struct DebugPayload: Sendable, Hashable, Codable {
    
    /// 简要分析摘要。
    public let analyzerSummary: String?
    
    /// 原始主体分类标签。
    public let rawSubjectLabels: [String]
    
    /// 原始背景标签。
    public let rawBackgroundLabels: [String]
    
    /// 原始风格标签。
    public let rawStyleLabels: [String]

    /// Vision 的原始 top-N 分类证据，包含整图和显著区域来源。
    public let topClassifications: [ClassificationCandidatePayload]

    /// 主体选择器最终采用的具体标签。
    public let selectedSubjectLabel: String?

    /// 最终主体标签来自整图还是某个显著区域。
    public let selectedSubjectSource: String?

    /// 显著区域数量，用于确认是否执行了区域二次分类。
    public let saliencyRegionCount: Int

    /// 参与二次分类的归一化显著区域框。
    public let saliencyRegions: [BoundingBoxPayload]
    
    public init(
        analyzerSummary: String? = nil,
        rawSubjectLabels: [String] = [],
        rawBackgroundLabels: [String] = [],
        rawStyleLabels: [String] = [],
        topClassifications: [ClassificationCandidatePayload] = [],
        selectedSubjectLabel: String? = nil,
        selectedSubjectSource: String? = nil,
        saliencyRegionCount: Int = 0,
        saliencyRegions: [BoundingBoxPayload] = []
    ) {
        self.analyzerSummary = analyzerSummary
        self.rawSubjectLabels = rawSubjectLabels
        self.rawBackgroundLabels = rawBackgroundLabels
        self.rawStyleLabels = rawStyleLabels
        self.topClassifications = topClassifications
        self.selectedSubjectLabel = selectedSubjectLabel
        self.selectedSubjectSource = selectedSubjectSource
        self.saliencyRegionCount = saliencyRegionCount
        self.saliencyRegions = saliencyRegions
    }
}
