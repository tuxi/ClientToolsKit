//
//  ScreenshotTooliOS.swift
//  ClientToolsKit
//
//  Created by xiaoyuan on 2026/8/23.
//

#if os(iOS)
import Foundation
import ReplayKit
import UIKit
import ClientToolProtocol

/// iOS截图工具
/// 两种捕获模式：
/// 1. capture_mode = "app_view"：捕获当前应用内界面。无需权限，瞬间完成。仅能获取本App渲染内容，无法捕获状态栏、其他App、系统弹窗。
/// 2. capture_mode = "system_screen"：捕获设备完整物理屏幕画面，依赖ReplayKit录屏。
///    ⚠️ 限制：代码无法自动开启录屏；调用后需要用户手动下拉控制中心，长按录屏按钮选中本App并启动录制，才能拿到屏幕帧。超时未操作会抛出错误。
public struct ScreenshotTool: ClientTool {
    public let name = "take_screenshot"
    public let description = """
iOS屏幕截图工具。
capture_mode: app_view（默认）仅截取当前App内部界面，无需系统权限；
capture_mode: system_screen 获取设备完整屏幕画面，需要用户在控制中心手动开启录屏。
返回截图workspace相对路径、文件大小、图片分辨率。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "save_path": .object([
                    "type": .string("string"),
                    "description": .string("workspace内的相对保存路径（可选，默认保存到screenshots/目录）")
                ]),
                "capture_mode": .object([
                    "type": .string("string"),
                    "description": .string("截图模式：app_view(默认，仅本App界面) / system_screen(整机完整屏幕，需要ReplayKit录屏)")
                ])
            ]),
            "required": .array([])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        let relativePath: String
        var captureMode: IOSCaptureMode = .appView

        if case .object(let dict) = args {
            if case .string(let customPath) = dict["save_path"] {
                relativePath = customPath
            } else {
                relativePath = Self.defaultRelativePath()
            }
            if case .string(let modeStr) = dict["capture_mode"] {
                captureMode = IOSCaptureMode(rawValue: modeStr) ?? .appView
            }
        } else {
            relativePath = Self.defaultRelativePath()
        }

        let workspace = try ToolWorkspace(context: context)
        let outputURL = try workspace.resolve(relativePath: relativePath, createParentDirectory: true)
        let outputPath = outputURL.path

        let startTime = Date()
        let cgImage: CGImage

        switch captureMode {
        case .appView:
            cgImage = try await captureCurrentAppView()
        case .systemScreen:
            // ReplayKit操作设置12秒超时，避免永久挂起
            cgImage = try await withTimeout(seconds: 12) {
                try await captureSystemScreenByReplayKit()
            }
        }

        // 输出PNG图片
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL, "public.png" as CFString, 1, nil
        ) else {
            throw ScreenshotError.writeFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ScreenshotError.writeFailed
        }

        let elapsed = Date().timeIntervalSince(startTime)

        let fileSize: String
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
           let size = attrs[.size] as? Int64 {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            fileSize = "未知"
        }

        let width = cgImage.width
        let height = cgImage.height

        let result = ScreenshotResult(
            success: true,
            relativePath: relativePath,
            absolutePath: outputPath,
            mimeType: "image/png",
            fileSize: fileSize,
            width: width,
            height: height,
            elapsedSeconds: elapsed
        )
        let asset = AgentAssetRef(
            id: "\(context.callID)-screenshot",
            kind: "image",
            displayName: outputURL.lastPathComponent,
            workspaceID: context.workspaceID,
            workspaceRelativePath: relativePath,
            absolutePath: outputPath,
            mimeType: "image/png",
            sourceTurnID: context.turnID,
            sourceCallID: context.callID
        )
        return try ToolResultEncoder.executionResult(result, assets: [asset])
    }

    private static func defaultRelativePath() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd/HHmmss-SSS"
        return "screenshots/\(formatter.string(from: Date()))-\(UUID().uuidString).png"
    }

    // MARK: - app_view 模式：渲染当前App窗口
    private func captureCurrentAppView() async throws -> CGImage {
        guard let window = await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else {
            throw ScreenshotError.noDisplayFound
        }
        return try await MainActor.run {
            guard let image = window.layer.renderSafe() else {
                throw ScreenshotError.noDisplayFound
            }
            return image
        }
    }

    // MARK: - system_screen 模式：ReplayKit录屏捕获屏幕帧
    private func captureSystemScreenByReplayKit() async throws -> CGImage {
        return try await withCheckedThrowingContinuation { cont in
            let recorder = RPScreenRecorder.shared()
            guard recorder.isAvailable else {
                cont.resume(throwing: ScreenshotError.permissionDenied)
                return
            }

            recorder.startCapture(handler: { sampleBuffer, bufferType, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard bufferType == .video,
                      let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    return
                }
                CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                let ctx = CIContext(options: [.useSoftwareRenderer: false])
                guard let cgImg = ctx.createCGImage(ciImage, from: ciImage.extent) else {
                    cont.resume(throwing: ScreenshotError.writeFailed)
                    return
                }
                recorder.stopCapture()
                cont.resume(returning: cgImg)

            }) { error in
                if let error = error {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// 任务超时包装
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ScreenshotError.timeout
            }
            guard let result = try await group.next() else {
                throw ScreenshotError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}

fileprivate enum IOSCaptureMode: String {
    case appView = "app_view"
    case systemScreen = "system_screen"
}

fileprivate extension CALayer {
    /// 安全渲染layer为CGImage，移除fatalError、强制解包
    func renderSafe() -> CGImage? {
        let scale = UIScreen.main.scale
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        UIGraphicsBeginImageContextWithOptions(size, true, scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        render(in: ctx)
        guard let uiImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        return uiImage.cgImage
    }
}

#endif
