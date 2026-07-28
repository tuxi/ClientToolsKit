//
//  SubjectMotionPhraseComposer.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/23.
//

import Foundation

/// 主体动作短语编排器。
///
/// 作用：
/// - 将离散的 subject motion tokens 编排成更自然的短语
/// - 解决 token 直接逐个翻译后不自然、重复、冲突的问题
///
/// 设计目标：
/// - 不负责识别动作，只负责“表达动作”
/// - 不负责改写 grounding，只消费已有 token
/// - 优先解决：
///   - 起始姿态 + 目标动作
///   - 重复语义折叠
///   - 组合动作合并
///   - 多 token 的自然输出
///
/// 当前支持的中文编排场景：
/// - start seated pose + stand up motion -> 由坐姿缓慢起身
/// - start seated pose + stand up motion + dance motion -> 由坐姿缓慢起身后轻轻起舞
/// - start seated pose + dance motion -> 由坐姿起身后轻轻起舞
/// - start standing pose + turning motion -> 由站姿轻微转身
/// - look at camera + wave hand -> 看向镜头并轻轻挥手
/// - look at camera + subtle nod -> 看向镜头并轻微点头
/// - look at camera + turning motion -> 轻轻转身看向镜头
/// - holding child pose + subtle interaction -> 抱着孩子轻微互动
/// - holding child pose + look at camera -> 抱着孩子看向镜头
/// - subtle interaction + subtle group motion -> 轻微互动
/// - stand up motion + subtle seated motion -> 由坐姿缓慢起身
/// - subtle seated motion + subtle nod -> 坐着轻微点头
/// - subtle standing motion + turning motion -> 站姿轻微转身
public enum SubjectMotionPhraseComposer {
    
    // MARK: - Public
    
    /// 生成中文主体动作短语。
    ///
    /// - Parameters:
    ///   - tokens: 主体动作 token 列表
    ///   - subject: 主体信息，可选，用于少量上下文辅助
    /// - Returns: 编排后的中文短语，若没有可输出内容则返回 nil
    public static func composeChinese(
        tokens: [String],
        subject: GroundedSubject?
    ) -> String? {
        let normalizedTokens = normalizeTokens(tokens)
        guard !normalizedTokens.isEmpty else { return nil }
        
        // 1. 先命中高优先级组合模式，避免被后续拆散
        if let phrase = composeChineseStrongPattern(tokens: normalizedTokens, subject: subject) {
            return phrase
        }
        
        // 2. 再做 token 折叠，去重、降噪、去冲突
        let reducedTokens = reduceChineseTokens(normalizedTokens, subject: subject)
        guard !reducedTokens.isEmpty else { return nil }
        
        // 3. 折叠后再试一次强规则
        if let phrase = composeChineseStrongPattern(tokens: reducedTokens, subject: subject) {
            return phrase
        }
        
        // 4. 最后做普通翻译拼接
        let translated = reducedTokens.compactMap(translateChineseMotionToken(_:))
        guard !translated.isEmpty else { return nil }
        
        return joinChinesePhrases(translated)
    }
    
    /// 生成英文主体动作短语。
    ///
    /// 当前版本仍然偏基础，但已支持核心组合。
    public static func composeEnglish(
        tokens: [String],
        subject: GroundedSubject?
    ) -> String? {
        let normalizedTokens = normalizeTokens(tokens)
        guard !normalizedTokens.isEmpty else { return nil }
        
        if let phrase = composeEnglishStrongPattern(tokens: normalizedTokens, subject: subject) {
            return phrase
        }
        
        let reducedTokens = reduceEnglishTokens(normalizedTokens, subject: subject)
        guard !reducedTokens.isEmpty else { return nil }
        
        if let phrase = composeEnglishStrongPattern(tokens: reducedTokens, subject: subject) {
            return phrase
        }
        
        let translated = reducedTokens.compactMap(translateEnglishMotionToken(_:))
        guard !translated.isEmpty else { return nil }
        
        return joinEnglishPhrases(translated)
    }
}

// MARK: - Chinese Strong Patterns

private extension SubjectMotionPhraseComposer {
    
    /// 中文高优先级动作模式。
    ///
    /// 这些模式优先于普通 token 逐个翻译。
    static func composeChineseStrongPattern(
        tokens: [String],
        subject: GroundedSubject?
    ) -> String? {
        let set = Set(tokens.map { $0.lowercased() })
        let posture = subject?.posture?.lowercased()
        let count = subject?.count ?? 1
        
        // 1. 坐姿 -> 起身 -> 起舞
        if set.contains("start seated pose"),
           set.contains("stand up motion"),
           set.contains("dance motion") {
            return "由坐姿缓慢起身后轻轻起舞"
        }
        
        // 2. 坐姿 -> 起舞（隐含先起身）
        if set.contains("start seated pose"),
           set.contains("dance motion") {
            return "由坐姿起身后轻轻起舞"
        }
        
        // 3. 坐姿 -> 起身
        if set.contains("start seated pose"),
           set.contains("stand up motion") {
            return "由坐姿缓慢起身"
        }
        
        // 4. 没有 start seated pose，但主体本身是 sitting，且有 stand up motion
        // 这是你当前日志里最关键的一种：
        // stand up motion + subtle seated motion + subject.posture=sitting
        if set.contains("stand up motion"),
           (set.contains("subtle seated motion")
            || posture == "sitting"
            || posture == "seated") {
            return "由坐姿缓慢起身"
        }
        
        // 5. 站姿 -> 转身
        if set.contains("start standing pose"),
           set.contains("turning motion") {
            return "由站姿轻微转身"
        }
        
        // 6. 主体本身 standing + turning，也可以直接表达成站姿转身
        if set.contains("turning motion"),
           (set.contains("subtle standing motion")
            || posture == "standing") {
            if set.contains("look at camera") {
                return "轻轻转身看向镜头"
            }
            return "站姿轻微转身"
        }
        
        // 7. 看向镜头 + 挥手
        if set.contains("look at camera"),
           set.contains("wave hand") {
            return "看向镜头并轻轻挥手"
        }
        
        // 8. 看向镜头 + 点头
        if set.contains("look at camera"),
           set.contains("subtle nod") {
            return "看向镜头并轻微点头"
        }
        
        // 9. 看向镜头 + 轻微站姿动作
        if set.contains("look at camera"),
           set.contains("subtle standing motion") {
            return "看向镜头并轻微动作"
        }
        
        // 10. 看向镜头 + 轻微自然动作
        if set.contains("look at camera"),
           set.contains("subtle body motion") {
            return "看向镜头并轻微动作"
        }
        
        // 11. 抱孩子 + 互动
        if set.contains("holding child pose"),
           set.contains("subtle interaction") {
            return "抱着孩子轻微互动"
        }
        
        // 12. 抱孩子 + 看向镜头
        if set.contains("holding child pose"),
           set.contains("look at camera") {
            return "抱着孩子看向镜头"
        }
        
        // 13. 抱孩子 + 挥手
        if set.contains("holding child pose"),
           set.contains("wave hand") {
            return "抱着孩子轻轻挥手"
        }
        
        // 14. 多人互动 + 群体动作
        if set.contains("subtle interaction"),
           set.contains("subtle group motion") {
            return "轻微互动"
        }
        
        // 15. 多人 + 挥手
        if count >= 2,
           set.contains("wave hand"),
           set.contains("subtle group motion") {
            return "轻轻挥手互动"
        }
        
        // 16. 坐姿轻动 + 点头
        if set.contains("subtle seated motion"),
           set.contains("subtle nod") {
            return "坐着轻微点头"
        }
        
        // 17. 坐姿轻动 + 看向镜头
        if set.contains("subtle seated motion"),
           set.contains("look at camera") {
            return "坐着看向镜头"
        }
        
        // 18. 起舞 + 看向镜头
        if set.contains("dance motion"),
           set.contains("look at camera") {
            return "看向镜头轻轻起舞"
        }
        
        return nil
    }
}

// MARK: - English Strong Patterns

private extension SubjectMotionPhraseComposer {
    
    static func composeEnglishStrongPattern(
        tokens: [String],
        subject: GroundedSubject?
    ) -> String? {
        let set = Set(tokens.map { $0.lowercased() })
        let posture = subject?.posture?.lowercased()
        
        if set.contains("start seated pose"),
           set.contains("stand up motion"),
           set.contains("dance motion") {
            return "rise gently from a seated pose, then begin to dance"
        }
        
        if set.contains("start seated pose"),
           set.contains("dance motion") {
            return "rise from a seated pose and begin to dance"
        }
        
        if set.contains("start seated pose"),
           set.contains("stand up motion") {
            return "rise gently from a seated pose"
        }
        
        if set.contains("stand up motion"),
           (set.contains("subtle seated motion")
            || posture == "sitting"
            || posture == "seated") {
            return "rise gently from a seated pose"
        }
        
        if set.contains("start standing pose"),
           set.contains("turning motion") {
            return "turn gently from a standing pose"
        }
        
        if set.contains("look at camera"),
           set.contains("wave hand") {
            return "look at the camera and wave gently"
        }
        
        if set.contains("look at camera"),
           set.contains("subtle nod") {
            return "look at the camera and nod gently"
        }
        
        if set.contains("look at camera"),
           set.contains("turning motion") {
            return "turn gently toward the camera"
        }
        
        if set.contains("holding child pose"),
           set.contains("subtle interaction") {
            return "hold the child and interact gently"
        }
        
        if set.contains("holding child pose"),
           set.contains("look at camera") {
            return "hold the child and look at the camera"
        }
        
        if set.contains("subtle interaction"),
           set.contains("subtle group motion") {
            return "gentle interaction"
        }
        
        if set.contains("subtle seated motion"),
           set.contains("subtle nod") {
            return "sit calmly and nod gently"
        }
        
        return nil
    }
}

// MARK: - Chinese Token Reduction

private extension SubjectMotionPhraseComposer {
    
    /// 中文 token 折叠。
    ///
    /// 目标：
    /// - 去掉重复语义
    /// - 保留更有信息量的 token
    /// - 避免“起始姿态 token”直接裸输出
    static func reduceChineseTokens(
        _ tokens: [String],
        subject: GroundedSubject?
    ) -> [String] {
        var result = normalizeTokens(tokens)
        let posture = subject?.posture?.lowercased()
        let count = subject?.count ?? 1
        
        // 1. 如果有“轻微互动”，去掉“轻微群体动作”
        if contains("subtle interaction", in: result) {
            result.removeAll { equals($0, "subtle group motion") }
        }
        
        // 2. 如果有“坐姿轻微动作”，去掉“轻微自然动作”
        if contains("subtle seated motion", in: result) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        // 3. 如果有“站姿轻微动作”，去掉“轻微自然动作”
        if contains("subtle standing motion", in: result) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        // 4. 多人时如果既有群体动作又有普通 body motion，去掉 body motion
        if count >= 2, contains("subtle group motion", in: result) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        // 5. 如果主体本身是 sitting，且已有 stand up motion，
        // 就不再保留 subtle seated motion，避免输出“起身、坐姿轻微动作”
        if (posture == "sitting" || posture == "seated"),
           contains("stand up motion", in: result) {
            result.removeAll { equals($0, "subtle seated motion") }
        }
        
        // 6. 如果主体本身是 standing，且已有 turning / wave / nod / look at camera，
        // 通常不必再保留 subtle standing motion
        if posture == "standing",
           containsAny(in: result, candidates: [
            "turning motion",
            "wave hand",
            "subtle nod",
            "look at camera"
           ]) {
            result.removeAll { equals($0, "subtle standing motion") }
        }
        
        // 7. 如果已经有明确动作（起舞 / 转身 / 挥手 / 点头 / 看向镜头），
        // 轻微自然动作通常是噪声，可删
        if containsAny(in: result, candidates: [
            "dance motion",
            "turning motion",
            "wave hand",
            "subtle nod",
            "look at camera"
        ]) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        // 8. 如果没有对应目标动作，起始姿态 token 不单独保留，避免“由坐姿开始”裸输出
        if contains("start seated pose", in: result),
           !containsAny(in: result, candidates: ["stand up motion", "dance motion"]) {
            result.removeAll { equals($0, "start seated pose") }
        }
        
        if contains("start standing pose", in: result),
           !contains("turning motion", in: result) {
            result.removeAll { equals($0, "start standing pose") }
        }
        
        return normalizeTokens(result)
    }
}

// MARK: - English Token Reduction

private extension SubjectMotionPhraseComposer {
    
    static func reduceEnglishTokens(
        _ tokens: [String],
        subject: GroundedSubject?
    ) -> [String] {
        var result = normalizeTokens(tokens)
        let posture = subject?.posture?.lowercased()
        let count = subject?.count ?? 1
        
        if contains("subtle interaction", in: result) {
            result.removeAll { equals($0, "subtle group motion") }
        }
        
        if contains("subtle seated motion", in: result) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        if contains("subtle standing motion", in: result) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        if count >= 2, contains("subtle group motion", in: result) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        if (posture == "sitting" || posture == "seated"),
           contains("stand up motion", in: result) {
            result.removeAll { equals($0, "subtle seated motion") }
        }
        
        if containsAny(in: result, candidates: [
            "dance motion",
            "turning motion",
            "wave hand",
            "subtle nod",
            "look at camera"
        ]) {
            result.removeAll { equals($0, "subtle body motion") }
        }
        
        if contains("start seated pose", in: result),
           !containsAny(in: result, candidates: ["stand up motion", "dance motion"]) {
            result.removeAll { equals($0, "start seated pose") }
        }
        
        if contains("start standing pose", in: result),
           !contains("turning motion", in: result) {
            result.removeAll { equals($0, "start standing pose") }
        }
        
        return normalizeTokens(result)
    }
}

// MARK: - Translation

private extension SubjectMotionPhraseComposer {
    
    static func translateChineseMotionToken(_ token: String) -> String? {
        switch token.lowercased() {
        case "subtle natural motion":
            return "轻微自然动作"
        case "subtle body motion":
            return "轻微自然动作"
        case "subtle group motion":
            return "轻微群体动作"
        case "subtle seated motion":
            return "坐姿轻微动作"
        case "subtle standing motion":
            return "站姿轻微动作"
        case "subtle seated group motion":
            return "坐姿轻微群体动作"
        case "subtle interaction":
            return "轻微互动"
        case "dance motion":
            return "轻轻起舞"
        case "walking motion":
            return "轻微走动"
        case "turning motion":
            return "轻微转身"
        case "subtle nod":
            return "轻微点头"
        case "wave hand":
            return "轻轻挥手"
        case "look at camera":
            return "看向镜头"
        case "holding child pose":
            return "抱着孩子"
        case "stand up motion":
            return "缓慢起身"
        case "start seated pose":
            return "由坐姿开始"
        case "start standing pose":
            return "由站姿开始"
        default:
            return token.isEmpty ? nil : token
        }
    }
    
    static func translateEnglishMotionToken(_ token: String) -> String? {
        switch token.lowercased() {
        case "subtle body motion":
            return "subtle natural motion"
        case "subtle group motion":
            return "subtle group motion"
        case "subtle seated motion":
            return "subtle seated motion"
        case "subtle standing motion":
            return "subtle standing motion"
        case "subtle seated group motion":
            return "subtle seated group motion"
        case "subtle interaction":
            return "gentle interaction"
        case "dance motion":
            return "begin to dance"
        case "walking motion":
            return "walk gently"
        case "turning motion":
            return "turn gently"
        case "subtle nod":
            return "nod gently"
        case "wave hand":
            return "wave gently"
        case "look at camera":
            return "look at the camera"
        case "holding child pose":
            return "holding a child"
        case "stand up motion":
            return "rise gently"
        case "start seated pose":
            return "from a seated pose"
        case "start standing pose":
            return "from a standing pose"
        case "subtle natural motion":
            return "subtle natural motion"
        default:
            return token.isEmpty ? nil : token
        }
    }
}

// MARK: - Helpers

private extension SubjectMotionPhraseComposer {
    
    /// token 去重并保持顺序。
    static func normalizeTokens(_ tokens: [String]) -> [String] {
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
    
    static func contains(_ token: String, in tokens: [String]) -> Bool {
        tokens.contains { equals($0, token) }
    }
    
    static func containsAny(in tokens: [String], candidates: [String]) -> Bool {
        candidates.contains { candidate in
            contains(candidate, in: tokens)
        }
    }
    
    static func equals(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
    
    /// 中文短语拼接。
    ///
    /// 两项用“，”；
    /// 三项及以上用“、”。
    static func joinChinesePhrases(_ phrases: [String]) -> String {
        let cleaned = normalizeTokens(phrases)
        guard !cleaned.isEmpty else { return "" }
        
        if cleaned.count == 1 {
            return cleaned[0]
        }
        
        if cleaned.count == 2 {
            return "\(cleaned[0])，\(cleaned[1])"
        }
        
        return cleaned.joined(separator: "、")
    }
    
    static func joinEnglishPhrases(_ phrases: [String]) -> String {
        let cleaned = normalizeTokens(phrases)
        guard !cleaned.isEmpty else { return "" }
        
        if cleaned.count == 1 {
            return cleaned[0]
        }
        
        if cleaned.count == 2 {
            return "\(cleaned[0]), \(cleaned[1])"
        }
        
        return cleaned.joined(separator: ", ")
    }
}
