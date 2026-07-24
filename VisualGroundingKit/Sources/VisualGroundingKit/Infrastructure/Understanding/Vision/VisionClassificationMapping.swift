//
//  VisionClassificationMapping.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

enum VisionClassificationMapping {
    
    static func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
    
    /// 根据置信度等级为 token 累加默认权重
    static func add(
        _ token: String,
        for level: ConfidenceLevel,
        into store: inout [String: Float]
    ) {
        let score: Float
        switch level {
        case .strong:
            score = 1.0
        case .medium:
            score = 0.6
        case .weak:
            score = 0.2
        case .ignore:
            score = 0.0
        }
        add(token, score: score, into: &store)
    }
    
    
    /// 根据置信度等级为 token 累加默认权重。
    static func add(
        _ token: String,
        score: Float,
        into store: inout [String: Float]
    ) {
        guard score > 0 else { return }
        store[token, default: 0] += score
    }
    
    static func best(from store: [String: Float]) -> String? {
        store
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .first?
            .key
    }
    
    /// 从分数字典中按分数排序，取前 N 个 token。
    static func sortedTokens(
        from store: [String: Float],
        top count: Int
    ) -> [String] {
        store
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(count)
            .map(\.key)
    }
}
