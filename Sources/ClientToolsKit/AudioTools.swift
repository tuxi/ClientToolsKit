@preconcurrency import AVFoundation
import ClientToolProtocol
import Foundation
@preconcurrency import Speech

/// Records microphone audio to an MPEG-4 AAC file in the shared workspace.
public struct RecordAudioTool: ClientTool {
    public let name = "record_audio"
    public let description = """
使用设备麦克风录音，并将 MPEG-4 AAC 音频保存到 workspace。适合会议、采访和语音笔记。
duration_seconds 必填，范围 1 到 3600 秒。宿主 App 必须配置 NSMicrophoneUsageDescription。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "duration_seconds": .object([
                    "type": .string("number"),
                    "description": .string("录音时长（秒），范围 1 到 3600"),
                    "minimum": .number(1),
                    "maximum": .number(3_600)
                ]),
                "save_path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内的相对保存路径，默认 recordings/recording-<时间>.m4a")
                ])
            ]),
            "required": .array([.string("duration_seconds")])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args else {
            throw AudioToolError.invalidArguments("Arguments must be a JSON object")
        }
        let duration = try AudioArguments.number(values["duration_seconds"], name: "duration_seconds")
        guard (1...3_600).contains(duration) else {
            throw AudioToolError.invalidArguments("duration_seconds must be between 1 and 3600")
        }
        let relativePath: String
        if case .string(let requestedPath) = values["save_path"] {
            relativePath = requestedPath
        } else {
            relativePath = Self.defaultPath()
        }
        guard relativePath.lowercased().hasSuffix(".m4a") else {
            throw AudioToolError.invalidArguments("save_path must use the .m4a extension")
        }
        try Self.requireUsageDescription("NSMicrophoneUsageDescription")

        let workspace = try ToolWorkspace(context: context)
        let outputURL = try workspace.resolve(relativePath: relativePath, createParentDirectory: true)
        let result = try await AudioRecorderRunner.record(to: outputURL, duration: duration)
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let payload = AudioRecordingResult(
            success: true,
            relativePath: relativePath,
            durationSeconds: result.duration,
            bytes: bytes,
            mimeType: "audio/mp4",
            sampleRate: 44_100,
            channels: 1
        )
        let asset = AgentAssetRef(
            id: "\(context.callID)-recording",
            kind: "audio",
            displayName: outputURL.lastPathComponent,
            workspaceID: context.workspaceID,
            workspaceRelativePath: relativePath,
            absolutePath: outputURL.path,
            mimeType: "audio/mp4",
            sourceTurnID: context.turnID,
            sourceCallID: context.callID,
            metadata: ["duration_seconds": .number(result.duration)]
        )
        return try ToolResultEncoder.executionResult(payload, assets: [asset])
    }

    private static func defaultPath() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "recordings/recording-\(formatter.string(from: Date())).m4a"
    }

    private static func requireUsageDescription(_ key: String) throws {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioToolError.missingUsageDescription(key)
        }
    }
}

/// Transcribes an existing workspace audio file using Apple's Speech framework.
public struct TranscribeAudioTool: ClientTool {
    public let name = "transcribe_audio"
    public let description = """
使用 Apple Speech 将 workspace 内的音频转写为文字，并返回带时间戳的分段结果。
默认 require_on_device=true，仅允许端侧识别；设备或语言不支持时会明确失败，不会自动上传录音。
宿主 App 必须配置 NSSpeechRecognitionUsageDescription。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("workspace 内音频文件的相对路径")
                ]),
                "locale": .object([
                    "type": .string("string"),
                    "description": .string("识别语言，如 zh-CN、en-US；默认跟随系统")
                ]),
                "require_on_device": .object([
                    "type": .string("boolean"),
                    "description": .string("是否强制端侧识别，默认 true"),
                    "default": .bool(true)
                ]),
                "contextual_strings": .object([
                    "type": .string("array"),
                    "description": .string("可选的专有名词或上下文短语"),
                    "items": .object(["type": .string("string")]),
                    "maxItems": .integer(100)
                ])
            ]),
            "required": .array([.string("path")])
        ])
    }

    public init() {}

    public func execute(
        args: JSONValue?,
        context: ClientToolExecutionContext
    ) async throws -> ClientToolExecutionResult {
        guard case .object(let values) = args,
              case .string(let relativePath) = values["path"] else {
            throw AudioToolError.invalidArguments("Missing required string parameter: path")
        }
        let localeIdentifier: String?
        if case .string(let requestedLocale) = values["locale"] {
            localeIdentifier = requestedLocale
        } else {
            localeIdentifier = nil
        }
        let requireOnDevice: Bool
        if case .bool(let requestedValue) = values["require_on_device"] {
            requireOnDevice = requestedValue
        } else {
            requireOnDevice = true
        }
        var contextualStrings: [String] = []
        if case .array(let values) = values["contextual_strings"] {
            guard values.count <= 100 else {
                throw AudioToolError.invalidArguments("contextual_strings must contain at most 100 items")
            }
            contextualStrings = try values.map {
                guard case .string(let string) = $0 else {
                    throw AudioToolError.invalidArguments("contextual_strings must contain only strings")
                }
                return string
            }
        }

        let workspace = try ToolWorkspace(context: context)
        let audioURL = try workspace.resolve(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AudioToolError.fileNotFound(relativePath)
        }
        try Self.requireUsageDescription("NSSpeechRecognitionUsageDescription")
        let transcription = try await SpeechTranscriptionRunner.transcribe(
            audioURL: audioURL,
            localeIdentifier: localeIdentifier,
            requireOnDevice: requireOnDevice,
            contextualStrings: contextualStrings
        )
        return try ToolResultEncoder.executionResult(
            AudioTranscriptionResult(
                success: true,
                relativePath: relativePath,
                locale: transcription.locale,
                text: transcription.text,
                segments: transcription.segments,
                onDevice: requireOnDevice
            )
        )
    }

    private static func requireUsageDescription(_ key: String) throws {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AudioToolError.missingUsageDescription(key)
        }
    }
}

@MainActor
private enum AudioRecorderRunner {
    static func record(to outputURL: URL, duration: Double) async throws -> (duration: Double, url: URL) {
        let granted: Bool
        #if os(iOS)
        granted = await AVAudioApplication.requestRecordPermission()
        #elseif os(macOS)
        granted = await AVCaptureDevice.requestAccess(for: .audio)
        #else
        granted = false
        #endif
        guard granted else {
            throw AudioToolError.microphonePermissionDenied
        }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AudioToolError.recordingFailed
        }
        do {
            try await Task.sleep(for: .seconds(duration))
        } catch {
            recorder.stop()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        let actualDuration = recorder.currentTime
        recorder.stop()
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw AudioToolError.recordingFailed
        }
        return (actualDuration, outputURL)
    }
}

@MainActor
private final class SpeechTranscriptionRunner {
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<SpeechPayload, Error>?

    static func transcribe(
        audioURL: URL,
        localeIdentifier: String?,
        requireOnDevice: Bool,
        contextualStrings: [String]
    ) async throws -> SpeechPayload {
        let runner = SpeechTranscriptionRunner()
        return try await runner.run(
            audioURL: audioURL,
            localeIdentifier: localeIdentifier,
            requireOnDevice: requireOnDevice,
            contextualStrings: contextualStrings
        )
    }

    private func run(
        audioURL: URL,
        localeIdentifier: String?,
        requireOnDevice: Bool,
        contextualStrings: [String]
    ) async throws -> SpeechPayload {
        let authorization = await Self.authorizationStatus()
        guard authorization == .authorized else {
            throw AudioToolError.speechRecognitionPermissionDenied
        }

        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AudioToolError.unsupportedLocale(locale.identifier)
        }
        guard recognizer.isAvailable else {
            throw AudioToolError.speechRecognizerUnavailable(locale.identifier)
        }
        if requireOnDevice && !recognizer.supportsOnDeviceRecognition {
            throw AudioToolError.onDeviceRecognitionUnavailable(locale.identifier)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = requireOnDevice
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        self?.handle(result: result, error: error, locale: locale.identifier)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    private func handle(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        locale: String
    ) {
        if let error {
            finish(.failure(AudioToolError.transcriptionFailed(error.localizedDescription)))
            return
        }
        guard let result, result.isFinal else { return }
        let transcription = result.bestTranscription
        let segments = transcription.segments.map {
            AudioTranscriptionSegment(
                text: $0.substring,
                timestamp: $0.timestamp,
                duration: $0.duration,
                confidence: Double($0.confidence)
            )
        }
        finish(.success(SpeechPayload(
            locale: locale,
            text: transcription.formattedString,
            segments: segments
        )))
    }

    private func cancel() {
        recognitionTask?.cancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<SpeechPayload, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        recognitionTask = nil
        continuation.resume(with: result)
    }

    private static func authorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization {
                continuation.resume(returning: $0)
            }
        }
    }
}

private enum AudioArguments {
    static func number(_ value: JSONValue?, name: String) throws -> Double {
        switch value {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: throw AudioToolError.invalidArguments("\(name) must be a number")
        }
    }
}

private struct AudioRecordingResult: Encodable {
    let success: Bool
    let relativePath: String
    let durationSeconds: Double
    let bytes: Int64
    let mimeType: String
    let sampleRate: Int
    let channels: Int

    enum CodingKeys: String, CodingKey {
        case success, bytes, channels
        case relativePath = "relative_path"
        case durationSeconds = "duration_seconds"
        case mimeType = "mime_type"
        case sampleRate = "sample_rate"
    }
}

private struct AudioTranscriptionResult: Encodable {
    let success: Bool
    let relativePath: String
    let locale: String
    let text: String
    let segments: [AudioTranscriptionSegment]
    let onDevice: Bool

    enum CodingKeys: String, CodingKey {
        case success, locale, text, segments
        case relativePath = "relative_path"
        case onDevice = "on_device"
    }
}

private struct SpeechPayload {
    let locale: String
    let text: String
    let segments: [AudioTranscriptionSegment]
}

private struct AudioTranscriptionSegment: Encodable {
    let text: String
    let timestamp: Double
    let duration: Double
    let confidence: Double
}

public enum AudioToolError: LocalizedError {
    case invalidArguments(String)
    case fileNotFound(String)
    case missingUsageDescription(String)
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case recordingFailed
    case unsupportedLocale(String)
    case speechRecognizerUnavailable(String)
    case onDeviceRecognitionUnavailable(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return "Invalid arguments: \(message)"
        case .fileNotFound(let path): return "Audio file was not found in the workspace: \(path)"
        case .missingUsageDescription(let key):
            return "The host App Info.plist must define a non-empty \(key) value."
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Enable it in System Settings and try again."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition permission was denied. Enable it in System Settings and try again."
        case .recordingFailed: return "Audio recording failed."
        case .unsupportedLocale(let locale): return "Speech recognition does not support locale \(locale)."
        case .speechRecognizerUnavailable(let locale):
            return "Speech recognition is temporarily unavailable for locale \(locale)."
        case .onDeviceRecognitionUnavailable(let locale):
            return "On-device speech recognition is unavailable for locale \(locale)."
        case .transcriptionFailed(let message): return "Audio transcription failed: \(message)"
        }
    }
}
