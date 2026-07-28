import Foundation
import Testing
@testable import VisualGroundingKit

#if canImport(AppKit)
import AppKit

private func makeTestImage() -> VisualImage {
    NSImage(size: NSSize(width: 64, height: 64))
}

private func sampleFileURL(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs")
        .appendingPathComponent(name)
}
#else
import UIKit

private func makeTestImage() -> VisualImage {
    UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
}

private func sampleFileURL(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs")
        .appendingPathComponent(name)
}
#endif

private actor StubQualityMeasurer: ImageQualityMeasuring {
    let brightnessValue: ImageBrightnessLevel?
    let sharpnessValue: ImageSharpnessLevel?

    init(
        brightnessValue: ImageBrightnessLevel?,
        sharpnessValue: ImageSharpnessLevel?
    ) {
        self.brightnessValue = brightnessValue
        self.sharpnessValue = sharpnessValue
    }

    func brightness(of image: VisualImage) async throws -> ImageBrightnessLevel? {
        _ = image
        return brightnessValue
    }

    func sharpness(of image: VisualImage) async throws -> ImageSharpnessLevel? {
        _ = image
        return sharpnessValue
    }
}

private actor StubOverlayPartitionAnalyzer: OverlayUIPartitionAnalyzing {
    let result: OverlayUIPartitionResult

    init(result: OverlayUIPartitionResult) {
        self.result = result
    }

    func partition(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> OverlayUIPartitionResult {
        _ = image
        _ = rawVision
        return result
    }
}

private actor StubRawVisionAnalyzer: RawVisionAnalyzing {
    let rawVision: RawVisionAnalysis

    init(rawVision: RawVisionAnalysis) {
        self.rawVision = rawVision
    }

    func analyze(in image: VisualImage) async throws -> RawVisionAnalysis {
        _ = image
        return rawVision
    }

    func analyze(in image: VisualImage, profile: AnalysisProfile) async throws -> RawVisionAnalysis {
        _ = image
        _ = profile
        return rawVision
    }
}

private actor StubPortraitAttributeAnalyzer: PortraitAttributeAnalyzing {
    let result: PortraitAttributeResult

    init(result: PortraitAttributeResult) {
        self.result = result
    }

    func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> PortraitAttributeResult {
        _ = image
        _ = rawVision
        return result
    }
}

private actor StubSubjectDetector: SubjectDetecting {
    let result: [DetectedSubject]
    private(set) var rawPathCalls = 0

    init(result: [DetectedSubject]) {
        self.result = result
    }

    func detect(in image: VisualImage) async throws -> [DetectedSubject] {
        _ = image
        return result
    }

    func detect(
        in image: VisualImage,
        rawVision: RawVisionAnalysis,
        portraitAttributes: PortraitAttributeResult?
    ) async throws -> [DetectedSubject] {
        _ = image
        _ = rawVision
        _ = portraitAttributes
        rawPathCalls += 1
        return result
    }

    func callCount() -> Int {
        rawPathCalls
    }
}

@Test
func imageDescriptorSupportsNewFactsFields() {
    let descriptor = ImageDescriptor(
        id: UUID(),
        role: .mainSubject,
        subjects: [],
        background: nil,
        style: nil,
        composition: nil,
        textBlocks: [],
        rawVision: RawVisionAnalysis(),
        imageFacts: ImageFactsDescriptor(
            environmentType: .outdoor,
            imageBrightness: .normal,
            imageSharpness: .sharp
        ),
        quality: nil,
        embedding: nil
    )

    #expect(descriptor.rawVision != nil)
    #expect(descriptor.imageFacts?.environmentType == .outdoor)
}

@Test
func visionOCRAnalyzerPrefersRawVisionTextsWhenAvailable() async throws {
    let analyzer = VisionOCRAnalyzer()
    let image = makeTestImage()
    let rawVision = RawVisionAnalysis(
        recognizedTexts: [
            RawRecognizedTextObservation(
                text: "Dream Cafe",
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08),
                confidence: 0.91
            ),
            RawRecognizedTextObservation(
                text: "10:30",
                boundingBox: CGRect(x: 0.8, y: 0.95, width: 0.1, height: 0.03),
                confidence: 0.99
            )
        ]
    )

    let result = try await analyzer.recognize(in: image, rawVision: rawVision)

    #expect(result.map(\.text) == ["Dream Cafe", "10:30"])
}

@Test
func visionSubjectDetectorPrefersCupOverHigherConfidenceTable() async throws {
    let detector = VisionSubjectDetector()
    let rawVision = RawVisionAnalysis(
        classifications: [
            RawClassificationObservation(
                identifier: "table",
                confidence: 0.30,
                source: "full_image"
            ),
            RawClassificationObservation(
                identifier: "coffee mug",
                confidence: 0.12,
                source: "full_image"
            )
        ]
    )

    let subjects = try await detector.detect(
        in: makeTestImage(),
        rawVision: rawVision,
        portraitAttributes: nil
    )

    #expect(subjects.first?.type == .object)
    #expect(subjects.first?.classificationLabel == "cup")
    #expect(subjects.first?.classificationSource == "full_image")
    #expect(subjects.first?.classificationCandidates.contains { $0.identifier == "coffee mug" } == true)
}

@Test
func visionSubjectDetectorUsesSaliencyRegionToFindCup() async throws {
    let detector = VisionSubjectDetector()
    let rawVision = RawVisionAnalysis(
        classifications: [
            RawClassificationObservation(
                identifier: "table",
                confidence: 0.40,
                source: "full_image"
            )
        ],
        saliencyRegions: [
            RawSaliencyRegion(
                boundingBox: CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.5),
                confidence: 0.8,
                classifications: [
                    RawClassificationObservation(
                        identifier: "cup",
                        confidence: 0.10,
                        source: "saliency_0"
                    )
                ]
            )
        ]
    )

    let subjects = try await detector.detect(
        in: makeTestImage(),
        rawVision: rawVision,
        portraitAttributes: nil
    )

    #expect(subjects.first?.classificationLabel == "cup")
    #expect(subjects.first?.classificationSource == "saliency_0")
}

@Test
func visualGroundingMapperCanExcludeDebugWhileKeepingCandidates() {
    let descriptor = ImageDescriptor(
        id: UUID(),
        role: .mainSubject,
        subjects: [
            DetectedSubject(
                type: .object,
                confidence: 0.12,
                classificationLabel: "cup",
                classificationCandidates: [
                    RawClassificationObservation(
                        identifier: "coffee mug",
                        confidence: 0.12,
                        source: "saliency_0"
                    )
                ],
                attributes: SubjectAttributes(subjectCount: 1),
                pose: nil,
                boundingBox: nil,
                segmentationHint: nil
            )
        ],
        background: BackgroundDescriptor(environmentObjects: ["table"]),
        style: nil,
        composition: nil,
        textBlocks: [],
        rawVision: RawVisionAnalysis(),
        quality: nil,
        embedding: nil
    )

    let payload = DefaultVisualGroundingMapper().map(descriptor, includeDebug: false)

    #expect(payload.debug == nil)
    #expect(payload.subjects.first?.coreLabel == "cup")
    #expect(payload.subjects.first?.canonicalLabel == "cup")
    #expect(payload.subjects.first?.candidateLabels.first?.label == "coffee mug")
}

@Test
func defaultVisualGroundingMapperIncludesImageFactsAndExtendedSubjectFields() {
    let mapper = DefaultVisualGroundingMapper()
    let descriptor = ImageDescriptor(
        id: UUID(),
        role: .mainSubject,
        subjects: [
            DetectedSubject(
                type: .person,
                confidence: 0.93,
                attributes: SubjectAttributes(
                    postureType: "standing",
                    portraitFraming: "medium_shot",
                    gender: "unknown",
                    ageLevel: "unknown",
                    subjectRefHints: ["single_person_generic"],
                    subjectScaleHint: "medium",
                    subjectCount: 1
                ),
                pose: PoseDescriptor(posture: "standing"),
                boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.35, height: 0.6),
                segmentationHint: SegmentationHint(isForegroundClear: true)
            )
        ],
        background: nil,
        style: nil,
        composition: CompositionDescriptor(
            shotType: "medium_shot",
            angle: "eye_level",
            backgroundType: "simple"
        ),
        textBlocks: [],
        rawVision: RawVisionAnalysis(),
        imageFacts: ImageFactsDescriptor(
            environmentType: .outdoor,
            imageBrightness: .bright,
            imageSharpness: .sharp,
            hasOverlayUI: true,
            isMixedPhotoWithUI: true,
            naturalTextBlocks: [
                RecognizedTextBlock(
                    text: "Dream Cafe",
                    boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08)
                )
            ],
            uiTextBlocks: [
                RecognizedTextBlock(
                    text: "发布",
                    boundingBox: CGRect(x: 0.84, y: 0.95, width: 0.08, height: 0.03)
                )
            ]
        ),
        promptHints: PromptHintsPayload(
            subjectRefStyle: "single_person_generic",
            subjectSceneBalance: "balanced",
            motionPreference: "portrait_micro_motion"
        ),
        quality: nil,
        embedding: nil
    )

    let payload = mapper.map(descriptor)

    #expect(payload.imageFacts?.environmentType == .outdoor)
    #expect(payload.imageFacts?.naturalTextBlocks == ["Dream Cafe"])
    #expect(payload.imageFacts?.uiTextBlocks == ["发布"])
    #expect(payload.subjects.first?.postureType == "standing")
    #expect(payload.subjects.first?.portraitFraming == "medium_shot")
    #expect(payload.subjects.first?.subjectRefHints == ["single_person_generic"])
    #expect(payload.subjects.first?.subjectScaleHint == "medium")
    #expect(payload.composition?.backgroundType == "simple")
    #expect(payload.promptHints?.subjectRefStyle == "single_person_generic")
}

@Test
func defaultVisualGroundingMapperPrefersPhotoPrimaryTypeForPhotoWithUIOverlay() {
    let mapper = DefaultVisualGroundingMapper()
    let descriptor = ImageDescriptor(
        id: UUID(),
        role: .mainSubject,
        subjects: [
            DetectedSubject(
                type: .person,
                confidence: 1.0,
                attributes: SubjectAttributes(
                    postureType: "static",
                    portraitFraming: "full_body",
                    subjectCount: 2
                ),
                pose: nil,
                boundingBox: CGRect(x: 0.26, y: 0.25, width: 0.63, height: 0.32),
                segmentationHint: SegmentationHint(isForegroundClear: true)
            )
        ],
        background: BackgroundDescriptor(
            sceneType: "outdoor natural scene",
            locationTags: ["outdoor", "natural"],
            environmentObjects: ["fence", "structure"]
        ),
        style: nil,
        composition: CompositionDescriptor(shotType: "medium_shot"),
        textBlocks: [
            RecognizedTextBlock(text: "13:41", boundingBox: CGRect(x: 0.11, y: 0.95, width: 0.15, height: 0.02)),
            RecognizedTextBlock(text: "发布", boundingBox: CGRect(x: 0.67, y: 0.07, width: 0.09, height: 0.02))
        ],
        rawVision: RawVisionAnalysis(),
        imageFacts: ImageFactsDescriptor(
            environmentType: .outdoor,
            imageBrightness: .normal,
            imageSharpness: .sharp,
            hasOverlayUI: true,
            isMixedPhotoWithUI: true,
            naturalTextBlocks: [],
            uiTextBlocks: [
                RecognizedTextBlock(text: "13:41", boundingBox: CGRect(x: 0.11, y: 0.95, width: 0.15, height: 0.02)),
                RecognizedTextBlock(text: "发布", boundingBox: CGRect(x: 0.67, y: 0.07, width: 0.09, height: 0.02))
            ]
        ),
        quality: nil,
        embedding: nil
    )

    let payload = mapper.map(descriptor)

    #expect(payload.contentType.primaryType == ContentPrimaryType.groupPhoto)
    #expect(payload.contentType.secondaryTypes.contains(ContentPrimaryType.screenshotUI))
    #expect(payload.contentType.isScreenshotLike == true)
    #expect(payload.contentType.isPhotoLike == true)
}

@Test
func defaultVisualGroundingMapperPrefersPhotoMotionProfileForPhotoWithUIOverlay() {
    let mapper = DefaultVisualGroundingMapper()
    let descriptor = ImageDescriptor(
        id: UUID(),
        role: .mainSubject,
        subjects: [
            DetectedSubject(
                type: .person,
                confidence: 1.0,
                attributes: SubjectAttributes(
                    postureType: "static",
                    portraitFraming: "medium_shot",
                    subjectCount: 2
                ),
                pose: nil,
                boundingBox: CGRect(x: 0.26, y: 0.25, width: 0.63, height: 0.32),
                segmentationHint: SegmentationHint(isForegroundClear: true)
            )
        ],
        background: BackgroundDescriptor(
            sceneType: "outdoor natural scene",
            locationTags: ["outdoor", "natural"],
            environmentObjects: ["fence", "structure"]
        ),
        style: nil,
        composition: CompositionDescriptor(shotType: "medium_shot"),
        textBlocks: [
            RecognizedTextBlock(text: "13:41", boundingBox: CGRect(x: 0.11, y: 0.95, width: 0.15, height: 0.02)),
            RecognizedTextBlock(text: "发布", boundingBox: CGRect(x: 0.67, y: 0.07, width: 0.09, height: 0.02))
        ],
        rawVision: RawVisionAnalysis(),
        imageFacts: ImageFactsDescriptor(
            environmentType: .outdoor,
            imageBrightness: .normal,
            imageSharpness: .sharp,
            hasOverlayUI: true,
            isMixedPhotoWithUI: true,
            naturalTextBlocks: [],
            uiTextBlocks: [
                RecognizedTextBlock(text: "13:41", boundingBox: CGRect(x: 0.11, y: 0.95, width: 0.15, height: 0.02)),
                RecognizedTextBlock(text: "发布", boundingBox: CGRect(x: 0.67, y: 0.07, width: 0.09, height: 0.02))
            ]
        ),
        quality: nil,
        embedding: nil
    )

    let payload = mapper.map(descriptor)

    #expect(payload.contentType.primaryType == .groupPhoto)
    #expect(payload.motionHints?.recommendedMotionProfile == .groupMicroMotion)
    #expect(payload.motionHints?.cameraMotionCandidates.first == "slow_push_in")
}

@Test
func visionImageFactsAnalyzerCombinesMeasuredAndPartitionedFacts() async throws {
    let analyzer = VisionImageFactsAnalyzer(
        qualityMeasurer: StubQualityMeasurer(
            brightnessValue: .bright,
            sharpnessValue: .sharp
        ),
        overlayPartitionAnalyzer: StubOverlayPartitionAnalyzer(
            result: OverlayUIPartitionResult(
                naturalTextBlocks: [
                    RecognizedTextBlock(
                        text: "Dream Cafe",
                        boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08)
                    )
                ],
                uiTextBlocks: [
                    RecognizedTextBlock(
                        text: "发布",
                        boundingBox: CGRect(x: 0.84, y: 0.95, width: 0.08, height: 0.03)
                    )
                ],
                hasOverlayUI: true,
                isMixedPhotoWithUI: true
            )
        )
    )

    let facts = try await analyzer.analyze(
        image: makeTestImage(),
        rawVision: RawVisionAnalysis(
            classifications: [
                RawClassificationObservation(identifier: "city street", confidence: 0.92)
            ]
        )
    )

    #expect(facts.environmentType == .urban)
    #expect(facts.imageBrightness == .bright)
    #expect(facts.imageSharpness == .sharp)
    #expect(facts.hasOverlayUI == true)
    #expect(facts.isMixedPhotoWithUI == true)
    #expect(facts.naturalTextBlocks.map(\.text) == ["Dream Cafe"])
    #expect(facts.uiTextBlocks.map(\.text) == ["发布"])
}

@Test
func visionSubjectHintAnalyzerProducesChildLikeHints() async throws {
    let analyzer = VisionSubjectHintAnalyzer()
    let subjects = [
        DetectedSubject(
            type: .person,
            confidence: 1,
            attributes: SubjectAttributes(subjectCount: 1),
            pose: nil,
            boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.35, height: 0.6),
            segmentationHint: nil
        )
    ]

    let result = try await analyzer.analyze(
        subjects: subjects,
        rawVision: RawVisionAnalysis(
            classifications: [
                RawClassificationObservation(identifier: "people", confidence: 0.9),
                RawClassificationObservation(identifier: "child", confidence: 0.88)
            ]
        )
    )

    #expect(result.first?.ageLevel == .child)
    #expect(result.first?.subjectRefHints.contains("single_person") == true)
    #expect(result.first?.subjectRefHints.contains("single_person_child_like") == true)
    #expect(result.first?.subjectScaleHint == "medium")
}

@Test
func visionEnvironmentObjectRefinerAddsSpecificOutdoorObjects() async throws {
    let analyzer = VisionEnvironmentObjectRefiner()

    let result = try await analyzer.refine(
        background: BackgroundDescriptor(
            sceneType: "outdoor natural scene",
            locationTags: ["outdoor"],
            environmentObjects: ["plants"]
        ),
        rawVision: RawVisionAnalysis(
            classifications: [
                RawClassificationObservation(identifier: "foliage", confidence: 0.8),
                RawClassificationObservation(identifier: "branch", confidence: 0.5),
                RawClassificationObservation(identifier: "grass", confidence: 0.5)
            ]
        )
    )

    #expect(result.environmentObjects.contains("plants"))
    #expect(result.environmentObjects.contains("tree"))
    #expect(result.environmentObjects.contains("grass"))
    #expect(result.sceneRefHints.contains("tree_line_like"))
    #expect(result.sceneRefHints.contains("park_like"))
}

@Test
func localImageUnderstandingServiceBuildsDescriptorFromRawVisionPipeline() async throws {
    let rawVision = RawVisionAnalysis(
        recognizedTexts: [
            RawRecognizedTextObservation(
                text: "Dream Cafe",
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08),
                confidence: 0.9
            )
        ]
    )
    let subjectDetector = StubSubjectDetector(
        result: [
            DetectedSubject(
                type: .person,
                confidence: 0.95,
                attributes: SubjectAttributes(
                    postureType: "standing",
                    portraitFraming: "medium_shot",
                    subjectCount: 1
                ),
                pose: PoseDescriptor(posture: "standing"),
                boundingBox: CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.7),
                segmentationHint: SegmentationHint(isForegroundClear: true)
            )
        ]
    )

    let service = LocalImageUnderstandingService(
        subjectDetector: subjectDetector,
        backgroundAnalyzer: MockBackgroundAnalyzer(),
        styleAnalyzer: MockStyleAnalyzer(),
        ocrAnalyzer: MockOCRAnalyzer(),
        rawVisionAnalyzer: StubRawVisionAnalyzer(rawVision: rawVision),
        imageFactsAnalyzer: MockImageFactsAnalyzer(),
        portraitAttributeAnalyzer: StubPortraitAttributeAnalyzer(
            result: PortraitAttributeResult(
                postureType: .standing,
                portraitFraming: .mediumShot
            )
        ),
        backgroundComplexityAnalyzer: MockBackgroundComplexityAnalyzer()
    )

    let descriptor = try await service.analyze(
        image: InputImageAsset(
            image: makeTestImage(),
            source: .photoLibrary,
            role: .mainSubject
        )
    )

    #expect(descriptor.rawVision?.recognizedTexts.map(\.text) == ["Dream Cafe"])
    #expect(descriptor.textBlocks.map(\.text) == ["Dream Cafe"])
    #expect(descriptor.imageFacts?.naturalTextBlocks.map(\.text) == ["Dream Cafe"])
    #expect(descriptor.subjects.first?.attributes.postureType == "standing")
    #expect(descriptor.subjects.first?.attributes.subjectRefHints.contains("single_person") == true)
    #expect(descriptor.promptHints?.subjectRefStyle == "single_person_generic")
    #expect(await subjectDetector.callCount() == 1)
}

@Test
func visualPreparationResultEncodingIncludesImageFactsAndExtendedFields() throws {
    let result = VisualPreparationResult(
        generationContext: GenerationContext(
            task: .imageToVideo,
            toolRouteKey: "video_generation",
            toolModeKey: "image_to_video",
            toolModeTitle: "图生视频",
            workflowName: "image_to_video_workflow"
        ),
        visualGrounding: VisualGroundingPayload(
            assetRole: InputImageAsset.ImageRole.mainSubject.rawValue,
            contentType: ContentTypePayload(primaryType: .portraitPhoto),
            subjects: [
                SubjectPayload(
                    id: "subject_0",
                    type: .person,
                    count: 1,
                    coreLabel: "person",
                    posture: "standing",
                    postureType: "standing",
                    portraitFraming: "medium_shot",
                    gender: "unknown",
                    ageLevel: "unknown",
                    subjectRefHints: ["single_person_generic"],
                    subjectScaleHint: "medium"
                )
            ],
            scene: ScenePayload(
                sceneType: "outdoor natural scene",
                sceneRefHints: ["tree_line_like"]
            ),
            composition: CompositionPayload(
                shotType: "medium_shot",
                cameraAngle: "eye_level",
                backgroundType: "simple",
                subjectScaleHint: "medium"
            ),
            imageFacts: ImageFactsPayload(
                environmentType: .outdoor,
                imageBrightness: .bright,
                imageSharpness: .sharp,
                hasOverlayUI: true,
                isMixedPhotoWithUI: true,
                naturalTextBlocks: ["Dream Cafe"],
                uiTextBlocks: ["发布"]
            ),
            promptHints: PromptHintsPayload(
                subjectRefStyle: "single_person_generic",
                subjectSceneBalance: "balanced",
                motionPreference: "portrait_micro_motion"
            )
        ),
        promptHints: PromptHintsPayload(
            subjectRefStyle: "single_person_generic",
            subjectSceneBalance: "balanced",
            motionPreference: "portrait_micro_motion"
        ),
        normalizedIntent: NormalizedVisualIntent(),
        analysisResults: []
    )

    let data = try JSONEncoder().encode(result)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("\"generationContext\""))
    #expect(json.contains("\"promptHints\""))
    #expect(json.contains("\"subjectRefStyle\":\"single_person_generic\""))
    #expect(json.contains("\"task\":\"imageToVideo\""))
    #expect(json.contains("\"toolModeKey\":\"image_to_video\""))
    #expect(json.contains("\"imageFacts\""))
    #expect(json.contains("\"environmentType\":\"outdoor\""))
    #expect(json.contains("\"naturalTextBlocks\":[\"Dream Cafe\"]"))
    #expect(json.contains("\"postureType\":\"standing\""))
    #expect(json.contains("\"portraitFraming\":\"medium_shot\""))
    #expect(json.contains("\"backgroundType\":\"simple\""))
    #expect(json.contains("\"sceneRefHints\":[\"tree_line_like\"]"))
}

@Test
func ruleBasedDefaultIntentGenerationServiceUsesPostureTypeInSourceSummary() async throws {
    let service = RuleBasedDefaultIntentGenerationService()
    let grounding = VisualGroundingPayload(
        assetRole: InputImageAsset.ImageRole.mainSubject.rawValue,
        contentType: ContentTypePayload(primaryType: .portraitPhoto),
        subjects: [
            SubjectPayload(
                id: "subject_0",
                type: .person,
                count: 1,
                coreLabel: "person",
                posture: nil,
                postureType: "standing"
            )
        ],
        motionHints: MotionHintsPayload(
            subjectMotionCandidates: ["subtle_body_motion"],
            environmentMotionCandidates: [],
            cameraMotionCandidates: ["slow_push_in"],
            recommendedMotionProfile: .subtlePortraitMotion,
            motionRiskLevel: .low
        )
    )

    let result = try await service.generateDefaultIntent(
        from: grounding,
        task: .imageToVideo
    )

    #expect(result.cameraMotion == "slow_push_in")
    #expect(result.sourceSummary?.contains("posture=standing") == true)
}

@Test
func visionOverlayUIPartitionAnalyzerSeparatesNaturalAndUIText() async throws {
    let analyzer = VisionOverlayUIPartitionAnalyzer()
    let result = try await analyzer.partition(
        image: makeTestImage(),
        rawVision: RawVisionAnalysis(
            faces: [
                RawFaceObservation(
                    boundingBox: CGRect(x: 0.25, y: 0.18, width: 0.18, height: 0.18),
                    confidence: 0.96
                )
            ],
            recognizedTexts: [
                RawRecognizedTextObservation(
                    text: "Dream Cafe",
                    boundingBox: CGRect(x: 0.10, y: 0.24, width: 0.32, height: 0.08),
                    confidence: 0.92
                ),
                RawRecognizedTextObservation(
                    text: "10:30",
                    boundingBox: CGRect(x: 0.82, y: 0.95, width: 0.10, height: 0.03),
                    confidence: 0.99
                ),
                RawRecognizedTextObservation(
                    text: "发布",
                    boundingBox: CGRect(x: 0.84, y: 0.04, width: 0.08, height: 0.03),
                    confidence: 0.99
                )
            ],
            classifications: [
                RawClassificationObservation(identifier: "person", confidence: 0.91)
            ]
        )
    )

    #expect(result.naturalTextBlocks.map(\.text) == ["Dream Cafe"])
    #expect(result.uiTextBlocks.map(\.text) == ["10:30", "发布"])
    #expect(result.hasOverlayUI == true)
    #expect(result.isMixedPhotoWithUI == true)
}

@Test
func sampleJsonFilesContainExpectedKeyFields() throws {
    let portrait = try String(
        contentsOf: sampleFileURL(named: "sample_output_portrait_photo.json"),
        encoding: .utf8
    )
    let landscape = try String(
        contentsOf: sampleFileURL(named: "sample_output_landscape_photo.json"),
        encoding: .utf8
    )
    let mixed = try String(
        contentsOf: sampleFileURL(named: "sample_output_photo_with_ui_overlay.json"),
        encoding: .utf8
    )

    #expect(portrait.contains("\"postureType\": \"standing\""))
    #expect(portrait.contains("\"portraitFraming\": \"medium_shot\""))
    #expect(landscape.contains("\"environmentType\": \"natural\""))
    #expect(landscape.contains("\"backgroundType\": \"complex\""))
    #expect(mixed.contains("\"hasOverlayUI\": true"))
    #expect(mixed.contains("\"isMixedPhotoWithUI\": true"))
    #expect(mixed.contains("\"uiTextBlocks\": ["))
    #expect(mixed.contains("\"发布\""))
}
