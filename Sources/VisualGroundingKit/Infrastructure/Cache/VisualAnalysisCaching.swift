//
//  VisualAnalysisCaching.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation

public protocol VisualAnalysisCaching: Sendable {
    func descriptor(for key: String) async -> ImageDescriptor?
    func saveDescriptor(_ descriptor: ImageDescriptor, for key: String) async
}
