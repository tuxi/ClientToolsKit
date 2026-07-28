//
//  VisualGroundingError.swift
//  VisualGroundingKit
//
//  Created by xiaoyuan on 2026/3/24.
//

import Foundation

public enum VisualGroundingError: LocalizedError {
    case emptyImages
    
    public var errorDescription: String? {
        switch self {
        case .emptyImages:
            return "输入图片不能为空"
        }
    }
}
