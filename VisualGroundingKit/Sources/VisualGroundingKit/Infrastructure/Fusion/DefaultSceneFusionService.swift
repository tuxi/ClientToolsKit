//
//  DefaultSceneFusionService.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 默认场景融合服务。
///
/// 作用：
/// - 将多个 `ImageDescriptor` 融合成一个 `CompositeScenePlan`
/// - 决定主体、配角、环境、关系、构图、风格、约束
///
/// 第二版目标：
/// - 更合理地融合 subjectCount / ageGroupHint / group pose
/// - 背景优先使用 sceneType，而不是随便取第一个 locationTag
/// - style / mood / render 分离，减少 Prompt 重复
public final class DefaultSceneFusionService: SceneFusionService {
    
    public init() {}
    
    public func fuse(_ descriptors: [ImageDescriptor], intent: GenerationIntent) async throws -> CompositeScenePlan {
        let main = resolveMainSubject(from: descriptors)
        let secondaries = resolveSecondarySubjects(from: descriptors, main: main)
        let environment = resolveEnvironment(from: descriptors)
        let relationship = resolveRelationship(main: main, secondaries: secondaries)
        let composition = resolveComposition(from: descriptors)
        let style = resolveStyle(from: descriptors, environment: environment)
        let constraints = resolveConstraints(from: descriptors, intent: intent)
        
        return CompositeScenePlan(
            mainSubject: main,
            secondarySubjects: secondaries,
            environment: environment,
            relationship: relationship,
            composition: composition,
            style: style,
            constraints: constraints,
            intent: intent
        )
    }
}

// MARK: - 主体融合

private extension DefaultSceneFusionService {
    
    /// 解析主主体
    func resolveMainSubject(from descriptors: [ImageDescriptor]) -> SceneSubject? {
        if let mainRef = descriptors.first(where: { $0.role == .mainSubject }),
           let subject = mainRef.subjects.first {
            return mapSceneSubject(from: subject, preserveIdentity: true)
        }
        
        if let firstPerson = descriptors
            .flatMap(\.subjects)
            .first(where: { $0.type == .person }) {
            return mapSceneSubject(from: firstPerson, preserveIdentity: true)
        }
        
        if let first = descriptors.flatMap(\.subjects).first {
            return mapSceneSubject(from: first, preserveIdentity: false)
        }
        
        return nil
    }
    
    /// 解析配角
    ///
    /// 当前阶段：
    /// - 如果主主体已经是“多人 / 群体”语义，就不再额外拆 secondary
    /// - 避免出现 “two people, beside person” 这种重复表达
    func resolveSecondarySubjects(
        from descriptors: [ImageDescriptor],
        main: SceneSubject?
    ) -> [SceneSubject] {
        guard let main else { return [] }
        
        let groupIndicators = [
            "two people", "two children", "three people", "three children",
            "group of people", "group of children"
        ]
        
        if groupIndicators.contains(where: { main.coreDescription.contains($0) }) {
            return []
        }
        
        return descriptors
            .flatMap(\.subjects)
            .dropFirst()
            .map { mapSceneSubject(from: $0, preserveIdentity: false) }
    }
    
    /// 将 `DetectedSubject` 映射为 `SceneSubject`
    func mapSceneSubject(
        from subject: DetectedSubject,
        preserveIdentity: Bool
    ) -> SceneSubject {
        let typeDescription = subjectBaseDescription(from: subject)
        
        let appearance = dedupTokens(
            subject.attributes.hair
            + subject.attributes.clothing
            + subject.attributes.accessories
            + subject.attributes.colors
        )
        
        let actions = dedupTokens(
            [subject.pose?.posture, subject.pose?.action]
                .compactMap { $0 }
        )
        
        return SceneSubject(
            type: subject.type.rawValue,
            coreDescription: typeDescription,
            appearanceTokens: appearance,
            actionTokens: actions,
            preserveIdentity: preserveIdentity
        )
    }
    
    /// 根据 subject 类型生成基础描述
    func subjectBaseDescription(from subject: DetectedSubject) -> String {
        switch subject.type {
        case .person:
            return personDescription(from: subject.attributes)
        case .animal:
            return (subject.attributes.subjectCount ?? 1) > 1 ? "animals" : "animal"
        case .object:
            return (subject.attributes.subjectCount ?? 1) > 1 ? "objects" : "object"
        case .unknown:
            return "subject"
        }
    }
    
    /// 生成人物描述
    ///
    /// 例如：
    /// - person
    /// - child
    /// - two people
    /// - two children
    /// - group of people
    func personDescription(from attributes: SubjectAttributes) -> String {
        let count = max(attributes.subjectCount ?? 1, 1)
        let isChild = attributes.ageGroupHint == "child"
        
        switch count {
        case 1:
            return isChild ? "child" : "person"
        case 2:
            return isChild ? "two children" : "two people"
        case 3:
            return isChild ? "three children" : "three people"
        default:
            return isChild ? "group of children" : "group of people"
        }
    }
}

// MARK: - 环境融合

private extension DefaultSceneFusionService {
    
    /// 解析环境
    ///
    /// 第二版重点：
    /// - 优先使用 `sceneType`
    /// - `locationTags` 只作为补充，不再抢 place 主位
    /// - lighting / timeOfDay / weather 分开组织
    func resolveEnvironment(from descriptors: [ImageDescriptor]) -> SceneEnvironment? {
        let bg = descriptors.first(where: { $0.role == .backgroundReference })?.background
            ?? descriptors.compactMap(\.background).first
        
        guard let bg else { return nil }
        
        let place = bg.sceneType ?? bg.locationTags.first
        
        let props = dedupTokens(bg.environmentObjects)
        let lighting = dedupTokens([bg.lighting, bg.timeOfDay].compactMap { $0 })
        let atmosphere = dedupTokens([bg.weather].compactMap { $0 })
        
        return SceneEnvironment(
            place: place,
            props: props,
            lighting: lighting,
            atmosphere: atmosphere
        )
    }
}

// MARK: - 关系融合

private extension DefaultSceneFusionService {
    
    /// 解析主体关系
    ///
    /// 当前阶段先做保守规则：
    /// - 如果没有 secondary，就不强加关系
    /// - 如果有 secondary，则给一个简单空间关系
    func resolveRelationship(
        main: SceneSubject?,
        secondaries: [SceneSubject]
    ) -> SubjectRelationship? {
        guard main != nil, !secondaries.isEmpty else { return nil }
        
        return SubjectRelationship(
            spatial: "beside",
            interaction: nil,
            emotionalTone: "natural"
        )
    }
}

// MARK: - 构图融合

private extension DefaultSceneFusionService {
    
    /// 解析构图
    ///
    /// 当前阶段仍然使用保守默认值
    func resolveComposition(from descriptors: [ImageDescriptor]) -> SceneComposition? {
        let comp = descriptors.compactMap(\.composition).first
        
        return SceneComposition(
            shotType: comp?.shotType ?? "full body portrait",
            cameraAngle: comp?.angle ?? "eye level",
            lensStyle: nil,
            framing: comp?.framing ?? "centered composition"
        )
    }
}

// MARK: - 风格融合

private extension DefaultSceneFusionService {
    
    /// 解析风格
    ///
    /// 第二版重点：
    /// - styleTokens / moodTokens / renderTokens 分离
    /// - 避免 mood 混入 style
    /// - 避免 render 中重复加入环境里已有的 lighting
    func resolveStyle(
        from descriptors: [ImageDescriptor],
        environment: SceneEnvironment?
    ) -> SceneStyle? {
        let styleRef = descriptors.first(where: { $0.role == .styleReference })?.style
        let style = styleRef ?? descriptors.compactMap(\.style).first
        
        guard let style else { return nil }
        
        let styleTokens = dedupTokens(style.visualStyle)
        let moodTokens = dedupTokens(style.mood)
        
        let environmentLighting = Set(environment?.lighting.map(normalizeToken) ?? [])
        
        let renderTokens = dedupTokens(
            style.renderingHint.filter {
                !environmentLighting.contains(normalizeToken($0))
            }
        )
        
        let colorTokens = dedupTokens(style.colorPalette)
        
        return SceneStyle(
            styleTokens: styleTokens,
            moodTokens: moodTokens,
            qualityTokens: ["highly detailed"],
            renderTokens: renderTokens,
            colorTokens: colorTokens
        )
    }
}

// MARK: - 约束融合

private extension DefaultSceneFusionService {
    
    /// 解析 Prompt 约束
    func resolveConstraints(
        from descriptors: [ImageDescriptor],
        intent: GenerationIntent
    ) -> [PromptConstraint] {
        [
            PromptConstraint(type: .preserveMainSubject, value: "preserve facial identity"),
            PromptConstraint(type: .keepFaceNatural, value: "natural face details"),
            PromptConstraint(type: .avoidExtraLimbs, value: "avoid extra limbs and fingers"),
            PromptConstraint(type: .styleConsistency, value: "keep overall style consistent")
        ]
    }
}

// MARK: - 工具方法

private extension DefaultSceneFusionService {
    
    /// token 去重
    func dedupTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            
            let key = normalizeToken(cleaned)
            guard !seen.contains(key) else { continue }
            
            seen.insert(key)
            result.append(cleaned)
        }
        
        return result
    }
    
    /// token 归一化
    func normalizeToken(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
