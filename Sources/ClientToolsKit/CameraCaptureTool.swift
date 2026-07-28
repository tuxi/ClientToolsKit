//
//  CameraCaptureTool.swift
//  Talkify
//
//  P1 Demo: 摄像头拍照工具（iOS + macOS 双平台）。
//  支持两种模式：
//    - silent：使用 AVFoundation AVCaptureSession 静默拍照（默认，向后兼容）
//    - interactive：展示系统相机 UI，用户点击拍照或 10 秒倒计时后自动拍照（iOS）
//  首次使用会触发系统摄像头权限弹窗。
//

import Foundation
@preconcurrency import AVFoundation
import Photos
import ClientToolProtocol
#if os(iOS)
import UIKit
#endif

/// 摄像头拍照工具 — 支持静默和交互两种模式。
/// iOS 使用后置/前置摄像头，macOS 使用内置 FaceTime 摄像头。
///
/// **silent 模式**（默认）：程序化捕获，无需 UI — 适合 Agent 在工作流中自动调用。
/// **interactive 模式**：展示系统相机界面（UIImagePickerController），
///   用户可手动点击快门拍照，或等待 10 秒倒计时后自动拍照。
///   用户取消会返回 cancelled=true（Agent 看到后不应重试）。
public struct CameraCaptureTool: ClientTool {
    public let name = "capture_photo"
    public let description = """
使用设备摄像头拍摄照片并保存到当前 workspace。
返回可传给其他本地工具的相对路径、文件大小和分辨率。

**默认使用 interactive 模式**：弹出系统相机界面，用户看到实时画面、点击快门或等待 10 秒倒计时自动拍照。
用户应始终能看到取景画面并主动参与构图——不要使用 silent 静默模式，除非：
  - 用户明确要求「静默拍摄」「后台拍照」「不要弹出界面」
  - 当前在 macOS 上（macOS 不支持 interactive，自动回退为 silent）

参数：
  - camera (可选): "front" 使用前置摄像头，"back" 使用后置摄像头，默认 "back"
  - save_path (可选): workspace 内的相对保存路径，默认保存到 captures/ 目录
  - save_to_photos (可选): iOS 是否同时保存到系统相册，默认 false
  - capture_mode (可选): "interactive"（默认，弹出相机界面）/ "silent"（静默，无 UI）

interactive 模式行为：
  - 弹出系统相机界面，用户看到实时预览画面
  - 屏幕顶部显示 10 秒倒计时（最后 3 秒有放大动画提示）
  - 用户可随时点击快门按钮提前拍照，不等倒计时
  - 倒计时归零时自动拍照
  - 用户点击「取消」返回 cancelled=true，不要自动重试
  - 不可用时自动回退 silent（macOS、无 presentationCoordinator 等）

注意：首次使用会弹出系统摄像头权限对话框，用户需授权后重试。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "camera": .object([
                    "type": .string("string"),
                    "description": .string("摄像头选择：\"front\"（前置/FaceTime）/ \"back\"（后置），默认 \"back\""),
                    "enum": .array([.string("front"), .string("back")]),
                    "default": .string("back")
                ]),
                "save_path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的相对保存路径（可选，默认保存到 captures/ 目录）")
                ]),
                "save_to_photos": .object([
                    "type": .string("boolean"),
                    "description": .string("是否同时保存到 iOS 系统相册，默认 false"),
                    "default": .bool(false)
                ]),
                "capture_mode": .object([
                    "type": .string("string"),
                    "description": .string("拍照模式：\"interactive\"（默认，弹出系统相机界面）/ \"silent\"（无 UI 静默拍照，仅在用户明确要求或 macOS 时使用）"),
                    "enum": .array([.string("interactive"), .string("silent")]),
                    "default": .string("interactive")
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
        // 解析参数
        var useFrontCamera = false
        var requestedPath: String?
        var saveToPhotos = false
        var captureMode: CaptureMode = .interactive

        if case .object(let dict) = args {
            if case .string(let camera) = dict["camera"], camera == "front" {
                useFrontCamera = true
            }
            if case .string(let customPath) = dict["save_path"] {
                requestedPath = customPath
            }
            if case .bool(let requestedSaveToPhotos) = dict["save_to_photos"] {
                saveToPhotos = requestedSaveToPhotos
            }
            if case .string(let mode) = dict["capture_mode"] {
                captureMode = CaptureMode(rawValue: mode) ?? .interactive
            }
        }

        let workspace = try ToolWorkspace(context: context)
        let relativePath = requestedPath ?? Self.defaultRelativePath()
        let outputURL = try workspace.resolve(
            relativePath: relativePath,
            createParentDirectory: true
        )
        let outputPath = outputURL.path

        let startTime = Date()

        // 1. 检查/请求摄像头权限
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw CameraError.permissionDenied
            }
        case .denied:
            throw CameraError.permissionDenied
        case .restricted:
            throw CameraError.restricted
        @unknown default:
            throw CameraError.permissionDenied
        }

        // 2. 根据模式选择捕获路径
        let photoData: Data
        var actualCaptureMode = CaptureMode.silent

#if os(iOS)
        if captureMode == .interactive, context.presentationCoordinator != nil {
            let image: UIImage
            do {
                image = try await captureInteractively(
                    useFrontCamera: useFrontCamera,
                    context: context
                )
            } catch CameraError.cancelled {
                return try ToolResultEncoder.executionResult(
                    CancelledCaptureResult(
                        success: false,
                        cancelled: true,
                        shouldRetry: false,
                        message: "用户取消了拍照。不要再次调用 capture_photo，除非用户明确要求重试。"
                    ),
                    assets: []
                )
            }
            guard let jpegData = image.jpegData(compressionQuality: 0.92) else {
                throw CameraError.captureFailed
            }
            photoData = jpegData
            actualCaptureMode = .interactive
        } else {
            photoData = try await captureSilently(useFrontCamera: useFrontCamera)
            actualCaptureMode = .silent
        }
#else
        photoData = try await captureSilently(useFrontCamera: useFrontCamera)
        actualCaptureMode = .silent
#endif

        // 3. 写入 workspace
        try photoData.write(to: outputURL, options: .atomic)

        // 4. 按需保存到系统相册 (iOS only)
        var savedToGallery = false
#if os(iOS)
        if saveToPhotos, let image = UIImage(data: photoData) {
            let albumStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            switch albumStatus {
            case .authorized, .limited:
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                    savedToGallery = true
                } catch {
                    // 相册保存失败不影响 workspace 中已经写入的照片。
                }
            case .notDetermined:
                let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                if granted == .authorized || granted == .limited {
                    do {
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        }
                        savedToGallery = true
                    } catch {
                        // 同上。
                    }
                }
            case .denied, .restricted:
                break
            @unknown default:
                break
            }
        }
#endif

        let elapsed = Date().timeIntervalSince(startTime)

        let attributes = try? FileManager.default.attributesOfItem(atPath: outputPath)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value
        let fileSize = byteCount.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "未知"

        // 从图片数据解析分辨率
        var width: Int?
        var height: Int?
        if let source = CGImageSourceCreateWithData(photoData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? Int,
           let pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? Int {
            width = pixelWidth
            height = pixelHeight
        }

        let result = CameraCaptureResult(
            success: true,
            relativePath: relativePath,
            absolutePath: outputPath,
            mimeType: "image/jpeg",
            fileSize: fileSize,
            bytes: byteCount,
            width: width,
            height: height,
            camera: useFrontCamera ? "front" : "back",
            captureMode: actualCaptureMode.rawValue,
            savedToPhotos: savedToGallery,
            elapsedSeconds: elapsed
        )
        let asset = AgentAssetRef(
            id: "\(context.callID)-photo",
            kind: "image",
            displayName: outputURL.lastPathComponent,
            workspaceID: context.workspaceID,
            workspaceRelativePath: relativePath,
            absolutePath: outputPath,
            mimeType: "image/jpeg",
            sourceTurnID: context.turnID,
            sourceCallID: context.callID
        )
        return try ToolResultEncoder.executionResult(result, assets: [asset])
    }

    // MARK: - Silent capture (AVCaptureSession)

    private func captureSilently(useFrontCamera: Bool) async throws -> Data {
        // 查找摄像头
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )

        guard let camera = discoverySession.devices.first else {
            throw CameraError.noCameraFound(position: useFrontCamera ? "前置" : "后置")
        }

        // 创建 AVCaptureSession
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // 添加输入
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        // 添加照片输出
        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(photoOutput)

        // 启动会话
        session.startRunning()
        defer { session.stopRunning() }

        // 等待摄像头预热
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // 拍照
        let settings = AVCapturePhotoSettings()
        let handler = PhotoCaptureHandler()
        return try await handler.capture(using: photoOutput, settings: settings)
    }

    // MARK: - Interactive capture (iOS)

#if os(iOS)
    private func captureInteractively(
        useFrontCamera: Bool,
        context: ClientToolExecutionContext
    ) async throws -> UIImage {
        guard let presentationCoordinator = context.presentationCoordinator else {
            throw CameraError.presentationUnavailable
        }

        let cameraDevice: UIImagePickerController.CameraDevice =
            useFrontCamera ? .front : .rear

        return try await InteractiveCameraRunner.capture(
            using: presentationCoordinator,
            cameraDevice: cameraDevice
        )
    }
#endif

    private static func defaultRelativePath() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd/HHmmss-SSS"
        return "captures/\(formatter.string(from: Date()))-\(UUID().uuidString).jpg"
    }
}

// MARK: - CaptureMode

private enum CaptureMode: String {
    case silent
    case interactive
}

// MARK: - CameraCaptureResult

private struct CameraCaptureResult: Encodable {
    let success: Bool
    let relativePath: String
    let absolutePath: String
    let mimeType: String
    let fileSize: String
    let bytes: Int64?
    let width: Int?
    let height: Int?
    let camera: String
    let captureMode: String
    let savedToPhotos: Bool
    let elapsedSeconds: Double

    enum CodingKeys: String, CodingKey {
        case success
        case relativePath = "relative_path"
        case absolutePath = "absolute_path"
        case mimeType = "mime_type"
        case fileSize = "file_size"
        case bytes, width, height, camera
        case captureMode = "capture_mode"
        case savedToPhotos = "saved_to_photos"
        case elapsedSeconds = "elapsed_seconds"
    }
}

// MARK: - Cancelled Capture Result (interactive 模式用户取消)

private struct CancelledCaptureResult: Encodable {
    let success: Bool
    let cancelled: Bool
    let shouldRetry: Bool
    let message: String

    enum CodingKeys: String, CodingKey {
        case success, cancelled, message
        case shouldRetry = "should_retry"
    }
}

// MARK: - PhotoCaptureHandler (silent 模式)

/// 将 AVCapturePhotoCaptureDelegate 回调桥接为 async/await。
private final class PhotoCaptureHandler: NSObject, AVCapturePhotoCaptureDelegate {
    private var continuation: CheckedContinuation<Data, Error>?

    func capture(using output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: CameraError.captureFailed)
        }
        continuation = nil
    }
}

// MARK: - Interactive Camera (iOS)

#if os(iOS)

/// 将 UIImagePickerController 的交互式拍照桥接为 async/await。
/// 支持用户手动点击快门或 10 秒倒计时自动拍照。
///
/// 关键设计：delegate 回调中直接 dismiss picker（标准 UIKit 模式），
/// 不在外层通过 presentationCoordinator 再 dismiss，避免与系统的内部
/// 转场冲突导致异步调用永远不返回。
@MainActor
private enum InteractiveCameraRunner {
    /// 自动拍照倒计时秒数。
    static let autoCaptureInterval: TimeInterval = 10

    static func capture(
        using presentationCoordinator: any ClientToolPresentationCoordinator,
        cameraDevice: UIImagePickerController.CameraDevice
    ) async throws -> UIImage {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw CameraError.scannerUnavailable
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = cameraDevice
        picker.showsCameraControls = true
        picker.allowsEditing = false

        let delegate = InteractiveCameraDelegate(
            picker: picker,
            autoCaptureInterval: autoCaptureInterval
        )
        picker.delegate = delegate

        // 倒计时浮层：必须在 present 之前设好 frame
        let screenBounds = UIScreen.main.bounds
        let overlay = delegate.makeCountdownOverlay(frame: screenBounds)
        picker.cameraOverlayView = overlay

        try await presentationCoordinator.present(picker, animated: true)

        // present 完成后 overlay 尺寸可能被系统调整，刷新布局
        delegate.relayoutCountdownLabel()

        let image: UIImage
        do {
            image = try await withTaskCancellationHandler {
                try await delegate.waitForResult()
            } onCancel: {
                Task { @MainActor in delegate.cancel() }
            }
        } catch {
            // 异常路径兜底：delegate 可能尚未 dismiss（如超时），强制关闭
            if picker.presentingViewController != nil {
                picker.dismiss(animated: false)
            }
            throw error
        }

        // 成功路径：delegate 已在回调中 dismiss 了 picker，这里不需要再调
        return image
    }
}

/// UIImagePickerController 的 delegate，负责：
/// - 管理 10 秒倒计时和自动拍照
/// - 在 delegate 回调中直接 dismiss picker（标准 UIKit 模式）
/// - 将结果通过 continuation 桥接为 async/await
///
/// 重要：
/// - dismiss 在 delegate 回调中同步执行，不在外层通过 coordinator 再调
/// - `isFinished` 仅在 `finish()` 中设为 true，保证 continuation 一定被 resume
@MainActor
private final class InteractiveCameraDelegate: NSObject {

    private weak var picker: UIImagePickerController?
    private let autoCaptureInterval: TimeInterval
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var countdownTimer: DispatchSourceTimer?
    private var safetyTimer: DispatchSourceTimer?
    private var countdown: Int
    private var isFinished = false
    private weak var countdownLabel: UILabel?

    init(picker: UIImagePickerController, autoCaptureInterval: TimeInterval) {
        self.picker = picker
        self.autoCaptureInterval = autoCaptureInterval
        self.countdown = Int(autoCaptureInterval)
        super.init()
    }

    // MARK: - Countdown overlay

    func makeCountdownOverlay(frame: CGRect) -> UIView {
        let overlay = UIView(frame: frame)
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .medium)
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = CGSize(width: 0, height: 2)
        label.layer.shadowRadius = 8
        label.layer.shadowOpacity = 0.7
        label.text = "\(countdown)"
        self.countdownLabel = label

        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])

        return overlay
    }

    func relayoutCountdownLabel() {
        countdownLabel?.superview?.setNeedsLayout()
        countdownLabel?.superview?.layoutIfNeeded()
    }

    // MARK: - Countdown timer

    private func startCountdown() {
        countdown = Int(autoCaptureInterval)
        updateCountdownDisplay()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.tickCountdown()
        }
        timer.resume()
        self.countdownTimer = timer
    }

    private func stopCountdown() {
        countdownTimer?.cancel()
        countdownTimer = nil
    }

    private func stopSafetyTimeout() {
        safetyTimer?.cancel()
        safetyTimer = nil
    }

    private func tickCountdown() {
        guard !isFinished else { return }
        countdown -= 1

        if countdown <= 0 {
            stopCountdown()
            countdownLabel?.text = "📸"
            // 不在此设 isFinished = true — 等 delegate 回调统一处理
            picker?.takePicture()
        } else {
            updateCountdownDisplay()
        }
    }

    private func updateCountdownDisplay() {
        countdownLabel?.text = "\(countdown)"

        if countdown <= 3 {
            countdownLabel?.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
            UIView.animate(withDuration: 0.85, delay: 0, options: [.curveEaseOut], animations: {
                self.countdownLabel?.transform = .identity
            })
        }
    }

    // MARK: - Result handling

    func waitForResult() async throws -> UIImage {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            startCountdown()
            startSafetyTimeout()
        }
    }

    /// 60 秒兜底超时：防止任何原因导致 continuation 永远不被 resume。
    private func startSafetyTimeout() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 60.0)
        timer.setEventHandler { [weak self] in
            self?.finish(with: .failure(CameraError.timedOut))
        }
        timer.resume()
        self.safetyTimer = timer
    }

    func cancel() {
        finish(with: .failure(CancellationError()))
    }

    /// 统一清理入口：停止定时器 → 移除浮层 → 清除 overlay → resume continuation
    private func finish(with result: Result<UIImage, Error>) {
        guard !isFinished else { return }
        isFinished = true
        stopCountdown()
        stopSafetyTimeout()
        countdownLabel?.removeFromSuperview()
        countdownLabel = nil
        // 清除 overlay 避免遮挡系统预览界面
        picker?.cameraOverlayView = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}

// MARK: - UIImagePickerControllerDelegate & UINavigationControllerDelegate

extension InteractiveCameraDelegate: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        guard let image = info[.originalImage] as? UIImage else {
            // 注意：delegate 负责 dismiss picker
            picker.dismiss(animated: true)
            finish(with: .failure(CameraError.captureFailed))
            return
        }
        let fixedImage = image.fixedOrientation()
        // 标准 UIKit 模式：delegate 中直接 dismiss picker
        picker.dismiss(animated: true)
        finish(with: .success(fixedImage))
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(with: .failure(CameraError.cancelled))
    }
}

// MARK: - UIImage Orientation Fix

extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let fixed = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return fixed ?? self
    }
}

#endif // os(iOS)

// MARK: - CameraError

public enum CameraError: LocalizedError {
    case permissionDenied
    case restricted
    case noCameraFound(position: String)
    case cannotAddInput
    case cannotAddOutput
    case captureFailed
    case cancelled
    case presentationUnavailable
    case scannerUnavailable
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "摄像头权限被拒绝。请打开 系统设置 → 隐私与安全性 → 相机，允许本应用访问摄像头后重试。"
        case .restricted:
            return "摄像头访问受到限制（家长控制或企业策略）。"
        case .noCameraFound(let position):
            return "未找到\(position)摄像头。请确认设备已连接摄像头。"
        case .cannotAddInput:
            return "无法将摄像头输入添加到捕获会话。"
        case .cannotAddOutput:
            return "无法将照片输出添加到捕获会话。"
        case .captureFailed:
            return "拍照失败：未能获取照片数据。"
        case .cancelled:
            return "用户取消了拍照。"
        case .presentationUnavailable:
            return "interactive 模式需要宿主 App 提供 ClientToolPresentationCoordinator。"
        case .scannerUnavailable:
            return "当前设备不支持系统相机拍照。"
        case .timedOut:
            return "拍照超时（60 秒内未完成），请重试。"
        }
    }
}
