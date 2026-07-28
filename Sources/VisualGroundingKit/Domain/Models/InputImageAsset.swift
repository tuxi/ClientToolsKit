//
//  InputImageAsset.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

public struct InputImageAsset: Identifiable, Sendable {
    public let id: UUID
    public let image: VisualImage
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
