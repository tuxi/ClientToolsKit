import ClientToolProtocol
import UIEvidenceBenchmarkCore
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

private struct DatasetManifest: Decodable {
    let schemaVersion: String
    let datasetSha256: String
    let images: [ImageSpec]
}

private struct ImageSpec: Decodable {
    let id: String
    let image: String
    let groundTruth: String
    let mimeType: String
    let sourceKind: String
    let sourceSha256: String
    let groundTruthSha256: String
    let crops: [CropSpec]
}

private struct CropSpec: Decodable {
    let bbox: BBoxSpec
    let purpose: String
}

private struct BBoxSpec: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct RunMetadata: Encodable {
    let schema: String
    let dataset: String
    let producerName: String
    let producerVersion: String
    let repetitions: Int
    let records: [RunRecord]

    enum CodingKeys: String, CodingKey {
        case schema, dataset, repetitions, records
        case producerName = "producer_name"
        case producerVersion = "producer_version"
    }
}

private struct RunRecord: Encodable {
    let id: String
    let image: String
    let sourceKind: String
    let mimeType: String
    let repeats: Int
    let latenciesMs: [Double]
    let evidence: UIEvidenceDocument
    let assets: [AgentAssetRef]
    let sourceCheck: SourceCheck
    let cropChecks: [CropCheck]
    let toolContent: String

    enum CodingKeys: String, CodingKey {
        case id, image, repeats, evidence, assets
        case sourceKind = "source_kind"
        case mimeType = "mime_type"
        case latenciesMs = "latencies_ms"
        case sourceCheck = "source_check"
        case cropChecks = "crop_checks"
        case toolContent = "tool_content"
    }
}

private struct SourceCheck: Encodable {
    let workspacePath: String
    let escapedWorkspace: Bool
    let exists: Bool
    let decodable: Bool
    let sha256Matches: Bool
    let width: Int
    let height: Int
    let dimensionsMatchEvidence: Bool

    enum CodingKeys: String, CodingKey {
        case exists, decodable, width, height
        case workspacePath = "workspace_path"
        case escapedWorkspace = "escaped_workspace"
        case sha256Matches = "sha256_matches"
        case dimensionsMatchEvidence = "dimensions_match_evidence"
    }
}

private struct CropCheck: Encodable {
    let assetID: String
    let sourceAssetID: String?
    let sourceBBox: BBoxSpec
    let requestedBBox: BBoxSpec
    let workspacePath: String
    let relationValid: Bool
    let escapedWorkspace: Bool
    let exists: Bool
    let decodable: Bool
    let width: Int
    let height: Int
    let expectedWidth: Int
    let expectedHeight: Int
    let dimensionsMatchSourceBBox: Bool
    let usable: Bool

    enum CodingKeys: String, CodingKey {
        case exists, decodable, width, height, usable
        case assetID = "asset_id"
        case sourceAssetID = "source_asset_id"
        case sourceBBox = "source_bbox"
        case requestedBBox = "requested_bbox"
        case workspacePath = "workspace_path"
        case relationValid = "relation_valid"
        case escapedWorkspace = "escaped_workspace"
        case expectedWidth = "expected_width"
        case expectedHeight = "expected_height"
        case dimensionsMatchSourceBBox = "dimensions_match_source_bbox"
    }
}

private enum RunnerError: LocalizedError {
    case invalidArguments(String)
    case invalidManifest(String)
    case datasetMismatch(String)
    case missingOutput(UIEvidenceDocument)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): return message
        case .invalidManifest(let message): return message
        case .datasetMismatch(let message): return message
        case .missingOutput(let document):
            return "Tool output did not decode as ui_evidence.v1 (schema=\(document.schema))"
        }
    }
}

@main
private struct UIEvidenceBenchmarkRunner {
    static func main() async throws {
        let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
        let datasetRoot = URL(fileURLWithPath: options.datasetPath, isDirectory: true).standardizedFileURL
        let outputRoot = URL(fileURLWithPath: options.outputPath, isDirectory: true).standardizedFileURL
        let manifestURL = datasetRoot.appendingPathComponent("manifest.json")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(DatasetManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion == "ui_evidence_benchmark_dataset.v2" else {
            throw RunnerError.invalidManifest("Unsupported manifest schema: \(manifest.schemaVersion)")
        }
        guard !manifest.images.isEmpty else {
            throw RunnerError.invalidManifest("Manifest contains no images")
        }

        try verifyDataset(manifest: manifest, datasetRoot: datasetRoot)
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let evidenceRoot = outputRoot.appendingPathComponent("ui_evidence", isDirectory: true)
        let assetsRoot = outputRoot.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assetsRoot, withIntermediateDirectories: true)

        let tool = InspectUIImageTool()
        var records: [RunRecord] = []
        records.reserveCapacity(manifest.images.count)

        for (index, spec) in manifest.images.enumerated() {
            let sourceURL = datasetRoot.appendingPathComponent(spec.image)
            let record = try await run(
                spec: spec,
                sourceURL: sourceURL,
                outputRoot: outputRoot,
                evidenceRoot: evidenceRoot,
                assetsRoot: assetsRoot,
                repetitions: options.repetitions,
                tool: tool
            )
            records.append(record)
            let evidenceURL = evidenceRoot.appendingPathComponent("\(spec.id).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(record.evidence).write(to: evidenceURL, options: .atomic)
            print("[\(index + 1)/\(manifest.images.count)] \(spec.id): elements=\(record.evidence.elements.count) groups=\(record.evidence.repeatedGroups.count) p50=\(format(percentile(record.latenciesMs, 0.50)))ms")
        }

        let metadata = RunMetadata(
            schema: "ui_evidence_benchmark_run.v1",
            dataset: manifest.datasetSha256,
            producerName: InspectUIImageToolBenchmarkIdentity.producerName,
            producerVersion: InspectUIImageToolBenchmarkIdentity.producerVersion,
            repetitions: options.repetitions,
            records: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(metadata).write(
            to: outputRoot.appendingPathComponent("run_metadata.json"),
            options: .atomic
        )
    }

    private static func run(
        spec: ImageSpec,
        sourceURL: URL,
        outputRoot: URL,
        evidenceRoot: URL,
        assetsRoot: URL,
        repetitions: Int,
        tool: InspectUIImageTool
    ) async throws -> RunRecord {
        let workspace = assetsRoot.appendingPathComponent(spec.id, isDirectory: true)
        try? FileManager.default.removeItem(at: workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let workspaceImageName = sourceURL.lastPathComponent
        let workspaceImageURL = workspace.appendingPathComponent(workspaceImageName)
        try FileManager.default.copyItem(at: sourceURL, to: workspaceImageURL)

        let args = makeArguments(spec: spec, relativePath: workspaceImageName)
        let context = ClientToolExecutionContext(
            workspaceRoot: workspace,
            workspaceID: "ui-evidence-benchmark",
            sessionID: "ui-evidence-benchmark",
            turnID: spec.id,
            callID: "inspect_ui_image"
        )

        var latencies: [Double] = []
        var finalResult: ClientToolExecutionResult?
        for _ in 0..<repetitions {
            let started = CFAbsoluteTimeGetCurrent()
            let result = try await tool.execute(args: args, context: context)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            latencies.append(elapsedMs)
            finalResult = result
        }
        guard let result = finalResult, let output = result.output else {
            throw RunnerError.invalidManifest("No tool output for \(spec.id)")
        }

        let outputData = try JSONEncoder().encode(output)
        let document = try JSONDecoder().decode(UIEvidenceDocument.self, from: outputData)
        guard document.schema == "ui_evidence.v1" else {
            throw RunnerError.missingOutput(document)
        }

        let sourceCheck = inspectSource(
            workspace: workspace,
            relativePath: workspaceImageName,
            expectedSHA256: spec.sourceSha256,
            document: document,
            assets: result.assets
        )
        let cropChecks = inspectCrops(
            workspace: workspace,
            width: document.source.width,
            height: document.source.height,
            requested: spec.crops,
            document: document,
            assets: result.assets
        )

        return RunRecord(
            id: spec.id,
            image: spec.image,
            sourceKind: spec.sourceKind,
            mimeType: spec.mimeType,
            repeats: repetitions,
            latenciesMs: latencies,
            evidence: document,
            assets: result.assets,
            sourceCheck: sourceCheck,
            cropChecks: cropChecks,
            toolContent: result.content
        )
    }

    private static func makeArguments(spec: ImageSpec, relativePath: String) -> JSONValue {
        let crops: [JSONValue] = spec.crops.map { crop in
            .object([
                "bbox": .object([
                    "x": .number(crop.bbox.x),
                    "y": .number(crop.bbox.y),
                    "width": .number(crop.bbox.width),
                    "height": .number(crop.bbox.height)
                ]),
                "purpose": .string(crop.purpose)
            ])
        }
        return .object([
            "path": .string(relativePath),
            "source_kind": .string(spec.sourceKind),
            "crops": .array(crops)
        ])
    }

    private static func inspectSource(
        workspace: URL,
        relativePath: String,
        expectedSHA256: String,
        document: UIEvidenceDocument,
        assets: [AgentAssetRef]
    ) -> SourceCheck {
        let imageURL = workspace.appendingPathComponent(relativePath).standardizedFileURL
        let exists = FileManager.default.fileExists(atPath: imageURL.path)
        let escape = !isInside(imageURL, root: workspace)
        let image = decodeImage(at: imageURL)
        let digest = (try? sha256Hex(Data(contentsOf: imageURL))) ?? ""
        let sourceAsset = assets.first { role(of: $0) == "source" }
        let sourcePath = sourceAsset?.workspaceRelativePath ?? ""
        return SourceCheck(
            workspacePath: sourcePath,
            escapedWorkspace: escape,
            exists: exists,
            decodable: image != nil,
            sha256Matches: digest == expectedSHA256,
            width: image?.width ?? 0,
            height: image?.height ?? 0,
            dimensionsMatchEvidence: image?.width == document.source.width && image?.height == document.source.height
        )
    }

    private static func inspectCrops(
        workspace: URL,
        width: Int,
        height: Int,
        requested: [CropSpec],
        document: UIEvidenceDocument,
        assets: [AgentAssetRef]
    ) -> [CropCheck] {
        document.crops.enumerated().map { index, crop in
            let asset = assets.first { $0.id == crop.assetID }
            let relativePath = asset?.workspaceRelativePath ?? ""
            let imageURL = workspace.appendingPathComponent(relativePath).standardizedFileURL
            let escaped = relativePath.isEmpty || !isInside(imageURL, root: workspace)
            let exists = !relativePath.isEmpty && FileManager.default.fileExists(atPath: imageURL.path)
            let image = exists ? decodeImage(at: imageURL) : nil
            let expectedPixels = pixelRect(
                bbox: crop.sourceBBox,
                width: width,
                height: height
            )
            let sourceAssetID = asset?.metadata?["source_asset_id"]?.stringValue
            let relationValid =
                crop.assetID == document.crops[index].assetID &&
                sourceAssetID == document.source.assetID &&
                asset?.metadata?["asset_role"]?.stringValue == "crop" &&
                asset?.mimeType == "image/png"
            let requestedBox = index < requested.count ? requested[index].bbox : BBoxSpec(
                x: crop.sourceBBox.x,
                y: crop.sourceBBox.y,
                width: crop.sourceBBox.width,
                height: crop.sourceBBox.height
            )
            let sizeMatches =
                image != nil &&
                abs((image?.width ?? 0) - expectedPixels.width) <= 1 &&
                abs((image?.height ?? 0) - expectedPixels.height) <= 1
            return CropCheck(
                assetID: crop.assetID,
                sourceAssetID: sourceAssetID,
                sourceBBox: BBoxSpec(
                    x: crop.sourceBBox.x,
                    y: crop.sourceBBox.y,
                    width: crop.sourceBBox.width,
                    height: crop.sourceBBox.height
                ),
                requestedBBox: requestedBox,
                workspacePath: relativePath,
                relationValid: relationValid,
                escapedWorkspace: escaped,
                exists: exists,
                decodable: image != nil,
                width: image?.width ?? 0,
                height: image?.height ?? 0,
                expectedWidth: expectedPixels.width,
                expectedHeight: expectedPixels.height,
                dimensionsMatchSourceBBox: sizeMatches,
                usable: relationValid && !escaped && exists && image != nil && sizeMatches
            )
        }
    }

    private static func decodeImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func pixelRect(bbox: UIEvidenceBBox, width: Int, height: Int) -> (width: Int, height: Int) {
        let x0 = Int((bbox.x * Double(width)).rounded(.down))
        let y0 = Int((bbox.y * Double(height)).rounded(.down))
        let x1 = Int((bbox.maxX * Double(width)).rounded(.up))
        let y1 = Int((bbox.maxY * Double(height)).rounded(.up))
        let rect = CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            .integral
        return (max(0, Int(rect.width)), max(0, Int(rect.height)))
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func role(of asset: AgentAssetRef) -> String? {
        asset.metadata?["asset_role"]?.stringValue
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func verifyDataset(manifest: DatasetManifest, datasetRoot: URL) throws {
        var aggregateParts: [String] = []
        for spec in manifest.images {
            let imageURL = datasetRoot.appendingPathComponent(spec.image)
            let gtURL = datasetRoot.appendingPathComponent(spec.groundTruth)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                throw RunnerError.datasetMismatch("Missing image: \(spec.image)")
            }
            guard FileManager.default.fileExists(atPath: gtURL.path) else {
                throw RunnerError.datasetMismatch("Missing ground truth: \(spec.groundTruth)")
            }
            let imageHash = try sha256Hex(Data(contentsOf: imageURL))
            let gtHash = try sha256Hex(Data(contentsOf: gtURL))
            guard imageHash == spec.sourceSha256 else {
                throw RunnerError.datasetMismatch("Image hash changed: \(spec.image)")
            }
            guard gtHash == spec.groundTruthSha256 else {
                throw RunnerError.datasetMismatch("Ground-truth hash changed: \(spec.groundTruth)")
            }
            aggregateParts.append("\(spec.id):\(imageHash):\(gtHash)")
        }
        let aggregate = sha256Hex(Data(aggregateParts.joined(separator: "\n").utf8))
        guard aggregate == manifest.datasetSha256 else {
            throw RunnerError.datasetMismatch("Dataset aggregate SHA-256 changed")
        }
    }

    private static func parseOptions(_ args: [String]) throws -> (datasetPath: String, outputPath: String, repetitions: Int) {
        var datasetPath: String?
        var outputPath: String?
        var repetitions = 3
        var index = 0
        while index < args.count {
            switch args[index] {
            case "--dataset":
                index += 1
                guard index < args.count else { throw RunnerError.invalidArguments("--dataset requires a path") }
                datasetPath = args[index]
            case "--output":
                index += 1
                guard index < args.count else { throw RunnerError.invalidArguments("--output requires a path") }
                outputPath = args[index]
            case "--repetitions":
                index += 1
                guard index < args.count, let value = Int(args[index]), value > 0 else {
                    throw RunnerError.invalidArguments("--repetitions requires a positive integer")
                }
                repetitions = value
            default:
                throw RunnerError.invalidArguments("Unknown argument: \(args[index])")
            }
            index += 1
        }
        guard let datasetPath, let outputPath else {
            throw RunnerError.invalidArguments("Usage: UIEvidenceBenchmarkRunner --dataset <dir> --output <dir> [--repetitions 3]")
        }
        return (datasetPath, outputPath, repetitions)
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(p * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private enum InspectUIImageToolBenchmarkIdentity {
    static let producerName = "ClientToolsKit.inspect_ui_image"
    static let producerVersion = "2"
}

private extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
