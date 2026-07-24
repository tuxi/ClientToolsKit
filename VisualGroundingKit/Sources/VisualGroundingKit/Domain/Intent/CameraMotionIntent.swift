//
//  CameraMotionIntent.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/22.
//

import Foundation

/// 镜头运动意图。
public struct CameraMotionIntent: Sendable {
    /// 镜头运动类型
    ///
    /// 例如：
    /// - slow_push_in
    /// - slight_pan_left
    /// - static
    public let motionType: String?
    
    public init(motionType: String? = nil) {
        self.motionType = motionType
    }
}
