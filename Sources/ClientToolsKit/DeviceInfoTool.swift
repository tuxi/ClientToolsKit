@preconcurrency import AVFoundation
import ClientToolProtocol
import Foundation
@preconcurrency import Speech

#if canImport(UIKit)
import UIKit
#endif

/// Returns static device information and an optional snapshot of dynamic state.
public struct DeviceInfoTool: ClientTool {
    public let name = "get_device_info"
    public let description = """
获取当前设备的结构化信息。默认同时返回平台、系统、硬件、App 信息以及电量、低电量模式、热状态、磁盘余量等动态状态。
可用 include_status=false 只读取静态信息；include_permissions=true 可附带相机、麦克风和语音识别授权状态。
"""

    public var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "include_status": .object([
                    "type": .string("boolean"),
                    "description": .string("是否包含动态设备状态，默认 true"),
                    "default": .bool(true)
                ]),
                "include_permissions": .object([
                    "type": .string("boolean"),
                    "description": .string("是否包含相机、麦克风、语音识别授权状态，默认 false"),
                    "default": .bool(false)
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
        let values: [String: JSONValue]
        if case .object(let object) = args {
            values = object
        } else {
            values = [:]
        }
        let includeStatus: Bool
        if case .bool(let requested) = values["include_status"] {
            includeStatus = requested
        } else {
            includeStatus = true
        }
        let includePermissions: Bool
        if case .bool(let requested) = values["include_permissions"] {
            includePermissions = requested
        } else {
            includePermissions = false
        }

        let processInfo = ProcessInfo.processInfo
        let app = AppInformation(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )

        #if os(iOS)
        let device = await MainActor.run {
            let current = UIDevice.current
            return DevicePlatformInformation(
                platform: "iOS",
                systemName: current.systemName,
                systemVersion: current.systemVersion,
                model: current.model,
                hostName: nil
            )
        }
        #elseif os(macOS)
        let device = DevicePlatformInformation(
            platform: "macOS",
            systemName: "macOS",
            systemVersion: processInfo.operatingSystemVersionString,
            model: Self.macHardwareModel(),
            hostName: processInfo.hostName
        )
        #else
        let device = DevicePlatformInformation(
            platform: "unknown",
            systemName: nil,
            systemVersion: processInfo.operatingSystemVersionString,
            model: nil,
            hostName: nil
        )
        #endif

        let hardware = HardwareInformation(
            processorCount: processInfo.processorCount,
            activeProcessorCount: processInfo.activeProcessorCount,
            physicalMemoryBytes: Int64(clamping: processInfo.physicalMemory)
        )
        let status = includeStatus ? await Self.currentStatus(processInfo: processInfo) : nil
        let permissions = includePermissions ? PermissionInformation(
            camera: Self.authorizationName(AVCaptureDevice.authorizationStatus(for: .video)),
            microphone: Self.authorizationName(AVCaptureDevice.authorizationStatus(for: .audio)),
            speechRecognition: Self.speechAuthorizationName(SFSpeechRecognizer.authorizationStatus())
        ) : nil

        return try ToolResultEncoder.executionResult(DeviceInformationResult(
            success: true,
            device: device,
            hardware: hardware,
            app: app,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            status: status,
            permissions: permissions
        ))
    }

    private static func currentStatus(processInfo: ProcessInfo) async -> DeviceDynamicStatus {
        let resourceValues = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
        #if os(iOS)
        let battery = await MainActor.run { () -> BatteryInformation in
            let device = UIDevice.current
            let wasMonitoring = device.isBatteryMonitoringEnabled
            device.isBatteryMonitoringEnabled = true
            defer { device.isBatteryMonitoringEnabled = wasMonitoring }
            let level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
            return BatteryInformation(
                level: level,
                state: batteryStateName(device.batteryState)
            )
        }
        #else
        let battery: BatteryInformation? = nil
        #endif
        return DeviceDynamicStatus(
            battery: battery,
            lowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
            thermalState: thermalStateName(processInfo.thermalState),
            systemUptimeSeconds: processInfo.systemUptime,
            availableStorageBytes: resourceValues?.volumeAvailableCapacityForImportantUsage,
            totalStorageBytes: resourceValues?.volumeTotalCapacity.map(Int64.init)
        )
    }

    #if os(iOS)
    @MainActor
    private static func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }
    #endif

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func authorizationName(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    private static func speechAuthorizationName(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> String {
        switch status {
        case .notDetermined: return "not_determined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    #if os(macOS)
    private static func macHardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else {
            return nil
        }
        return String(
            decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }
    #endif
}

private struct DeviceInformationResult: Encodable {
    let success: Bool
    let device: DevicePlatformInformation
    let hardware: HardwareInformation
    let app: AppInformation
    let locale: String
    let timeZone: String
    let status: DeviceDynamicStatus?
    let permissions: PermissionInformation?

    enum CodingKeys: String, CodingKey {
        case success, device, hardware, app, locale, status, permissions
        case timeZone = "time_zone"
    }
}

private struct DevicePlatformInformation: Encodable {
    let platform: String
    let systemName: String?
    let systemVersion: String
    let model: String?
    let hostName: String?

    enum CodingKeys: String, CodingKey {
        case platform, model
        case systemName = "system_name"
        case systemVersion = "system_version"
        case hostName = "host_name"
    }
}

private struct HardwareInformation: Encodable {
    let processorCount: Int
    let activeProcessorCount: Int
    let physicalMemoryBytes: Int64

    enum CodingKeys: String, CodingKey {
        case processorCount = "processor_count"
        case activeProcessorCount = "active_processor_count"
        case physicalMemoryBytes = "physical_memory_bytes"
    }
}

private struct AppInformation: Encodable {
    let version: String?
    let build: String?
    let bundleIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case version, build
        case bundleIdentifier = "bundle_identifier"
    }
}

private struct DeviceDynamicStatus: Encodable {
    let battery: BatteryInformation?
    let lowPowerModeEnabled: Bool
    let thermalState: String
    let systemUptimeSeconds: Double
    let availableStorageBytes: Int64?
    let totalStorageBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case battery
        case lowPowerModeEnabled = "low_power_mode_enabled"
        case thermalState = "thermal_state"
        case systemUptimeSeconds = "system_uptime_seconds"
        case availableStorageBytes = "available_storage_bytes"
        case totalStorageBytes = "total_storage_bytes"
    }
}

private struct BatteryInformation: Encodable {
    let level: Double?
    let state: String
}

private struct PermissionInformation: Encodable {
    let camera: String
    let microphone: String
    let speechRecognition: String

    enum CodingKeys: String, CodingKey {
        case camera, microphone
        case speechRecognition = "speech_recognition"
    }
}
