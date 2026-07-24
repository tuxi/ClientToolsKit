import ClientToolProtocol
import Foundation

/// A filesystem boundary shared by local client tools.
///
/// Tools exchange paths relative to this root so an agent can safely pass a file
/// produced by one tool to another without relying on device-specific absolute paths.
public struct ToolWorkspace: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    /// Creates a workspace from the per-call execution context.
    /// There is intentionally no Documents-directory fallback: writing to the
    /// wrong workspace is worse than failing the tool call.
    public init(context: ClientToolExecutionContext) throws {
        guard let rootURL = context.workspaceRoot else {
            throw ToolWorkspaceError.workspaceUnavailable
        }
        guard rootURL.isFileURL, (rootURL.path as NSString).isAbsolutePath else {
            throw ToolWorkspaceError.invalidWorkspaceRoot(rootURL.absoluteString)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ToolWorkspaceError.invalidWorkspaceRoot(rootURL.path)
        }
        self.init(rootURL: rootURL)
    }

    /// Resolves a workspace-relative path and rejects absolute paths and traversal.
    public func resolve(
        relativePath: String,
        createParentDirectory: Bool = false
    ) throws -> URL {
        guard !relativePath.isEmpty else {
            throw ToolWorkspaceError.emptyPath
        }

        guard !(relativePath as NSString).isAbsolutePath else {
            throw ToolWorkspaceError.absolutePathNotAllowed(relativePath)
        }

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = resolvedRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path
        let candidatePath = candidate.path

        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            throw ToolWorkspaceError.pathOutsideWorkspace(relativePath)
        }

        if createParentDirectory {
            try FileManager.default.createDirectory(
                at: candidate.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        return candidate
    }
}

public enum ToolWorkspaceError: LocalizedError {
    case workspaceUnavailable
    case invalidWorkspaceRoot(String)
    case emptyPath
    case absolutePathNotAllowed(String)
    case pathOutsideWorkspace(String)

    public var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            return "The current client-tool execution has no locally accessible workspace."
        case .invalidWorkspaceRoot(let path):
            return "The current workspace root is invalid or unavailable on this device: \(path)"
        case .emptyPath:
            return "Workspace path must not be empty."
        case .absolutePathNotAllowed(let path):
            return "Absolute paths are not allowed; use a workspace-relative path: \(path)"
        case .pathOutsideWorkspace(let path):
            return "Path is outside the workspace: \(path)"
        }
    }
}

enum ToolResultEncoder {
    static func executionResult<T: Encodable>(
        _ value: T,
        assets: [AgentAssetRef] = []
    ) throws -> ClientToolExecutionResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ToolResultEncodingError.invalidUTF8
        }
        let output = try JSONDecoder().decode(JSONValue.self, from: data)
        return ClientToolExecutionResult(content: content, output: output, assets: assets)
    }
}

enum ToolResultEncodingError: LocalizedError {
    case invalidUTF8

    var errorDescription: String? {
        "Failed to encode the tool result as UTF-8 JSON."
    }
}
