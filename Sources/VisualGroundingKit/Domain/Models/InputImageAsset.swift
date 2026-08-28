//
//  InputImageAsset.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public struct InputImageAsset: Identifiable, Sendable {
    public let id: UUID
    /// NSImage 在 macOS 15 SDK 中不是 Sendable（它是可变引用类型，Apple 甚至用
    /// `@available(*, unavailable)` 显式禁止了响应式遵守），直到 macOS 26 SDK 才被
    /// 标记为 Sendable，导致同一份代码在不同 SDK 下编译结果不一致。
    /// 这里约定 image 在构造后不再被修改（与 UIImage 的不可变用法一致），
    /// 用 `nonisolated(unsafe)` 关闭该属性的 Sendable 检查，保证新旧 SDK 均可编译。
    nonisolated(unsafe) public let image: VisualImage
    public let source: SourceType
    public let role: ImageRole
    
    public init(
        id: UUID = UUID(),
        image: VisualImage,
        source: SourceType,
        role: ImageRole
    ) {
        self.id = id
        self.image = image
        self.source = source
        self.role = role
    }
    
    public enum SourceType: Sendable {
        case photoLibrary
        case camera
        case cache
        case workspace
    }
    
    public enum ImageRole: String, Sendable, Codable {
        case mainSubject
        case secondarySubject
        case backgroundReference
        case styleReference
        case unspecified
    }
}
