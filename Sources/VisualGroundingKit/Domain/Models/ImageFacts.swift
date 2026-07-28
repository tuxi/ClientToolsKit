//
//  ImageFacts.swift
//  VisualGroundingKit
//
//  Created by Codex on 2026/4/21.
//

import Foundation

public struct ImageFactsDescriptor: Sendable, Codable, Hashable {
    public let environmentType: EnvironmentType?
    public let imageBrightness: ImageBrightnessLevel?
    public let imageSharpness: ImageSharpnessLevel?
    public let hasOverlayUI: Bool?
    public let isMixedPhotoWithUI: Bool?
    public let naturalTextBlocks: [RecognizedTextBlock]
    public let uiTextBlocks: [RecognizedTextBlock]

    public init(
        environmentType: EnvironmentType? = nil,
        imageBrightness: ImageBrightnessLevel? = nil,
        imageSharpness: ImageSharpnessLevel? = nil,
        hasOverlayUI: Bool? = nil,
        isMixedPhotoWithUI: Bool? = nil,
        naturalTextBlocks: [RecognizedTextBlock] = [],
        uiTextBlocks: [RecognizedTextBlock] = []
    ) {
        self.environmentType = environmentType
        self.imageBrightness = imageBrightness
        self.imageSharpness = imageSharpness
        self.hasOverlayUI = hasOverlayUI
        self.isMixedPhotoWithUI = isMixedPhotoWithUI
        self.naturalTextBlocks = naturalTextBlocks
        self.uiTextBlocks = uiTextBlocks
    }
}

public struct ImageFactsPayload: Sendable, Codable, Hashable {
    public let environmentType: EnvironmentType?
    public let imageBrightness: ImageBrightnessLevel?
    public let imageSharpness: ImageSharpnessLevel?
    public let hasOverlayUI: Bool?
    public let isMixedPhotoWithUI: Bool?
    public let naturalTextBlocks: [String]
    public let uiTextBlocks: [String]

    public init(
        environmentType: EnvironmentType? = nil,
        imageBrightness: ImageBrightnessLevel? = nil,
        imageSharpness: ImageSharpnessLevel? = nil,
        hasOverlayUI: Bool? = nil,
        isMixedPhotoWithUI: Bool? = nil,
        naturalTextBlocks: [String] = [],
        uiTextBlocks: [String] = []
    ) {
        self.environmentType = environmentType
        self.imageBrightness = imageBrightness
        self.imageSharpness = imageSharpness
        self.hasOverlayUI = hasOverlayUI
        self.isMixedPhotoWithUI = isMixedPhotoWithUI
        self.naturalTextBlocks = naturalTextBlocks
        self.uiTextBlocks = uiTextBlocks
    }
}

public enum EnvironmentType: String, Sendable, Codable, Hashable {
    case indoor
    case outdoor
    case natural
    case urban
    case room
    case plain
}

public enum ImageBrightnessLevel: String, Sendable, Codable, Hashable {
    case bright
    case normal
    case dark
}

public enum ImageSharpnessLevel: String, Sendable, Codable, Hashable {
    case sharp
    case normal
    case blurry
}

public enum BackgroundType: String, Sendable, Codable, Hashable {
    case blurred
    case simple
    case complex
    case pure
}

public enum PortraitPostureType: String, Sendable, Codable, Hashable {
    case standing
    case sitting
    case walking
    case `static`
}

public enum PortraitFramingType: String, Sendable, Codable, Hashable {
    case closeUp = "close_up"
    case mediumShot = "medium_shot"
    case fullBody = "full_body"
}

public enum SubjectGender: String, Sendable, Codable, Hashable {
    case male
    case female
    case unknown
}

public enum SubjectAgeLevel: String, Sendable, Codable, Hashable {
    case child
    case young
    case adult
    case elderly
    case unknown
}
