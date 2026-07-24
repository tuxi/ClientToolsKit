# ClientToolsKit

Client-side tools for capabilities that are unavailable or inappropriate in the
embedded Go filesystem layer. All file inputs and outputs use paths relative to
the workspace root from the execution context.

## Tools

- read_pdf: extract selectable PDF text and metadata.
- render_pdf_pages: render PDF pages to PNG/JPEG for OCR or visual analysis.
- record_audio: record microphone audio to an M4A workspace asset.
- transcribe_audio: transcribe workspace audio with Apple Speech.
- extract_archive: safely extract standard stored/DEFLATE ZIP files.
- scan_document: present Apple's multi-page document camera and save PDF/JPEG output.
- get_device_info: return static device information and optional dynamic status.
- Existing camera, screenshot, download, and image-analysis tools remain available.

The embedded Go filesystem tools should continue to handle ordinary UTF-8 reads,
file creation and editing. The Swift tools cover native frameworks and semantic
formats rather than duplicating those operations.

## Host App configuration

An App that registers audio or scanning tools must add user-facing values for
NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription, and
NSCameraUsageDescription to its Info.plist.

transcribe_audio defaults to require_on_device=true. It fails when the selected
locale has no on-device recognizer; it does not silently switch to server-based
recognition.

Example registration:

    await registry.register(ReadPDFTool())
    await registry.register(RenderPDFPagesTool())
    await registry.register(RecordAudioTool())
    await registry.register(TranscribeAudioTool())
    await registry.register(ExtractArchiveTool())
    await registry.register(DeviceInfoTool())

On iOS, register ScanDocumentTool as well. It requires AgentKit to bind a
ClientToolPresentationCoordinator to the active scene.

extract_archive rejects encrypted ZIPs, ZIP64, symbolic links, unsafe paths,
duplicate paths, unsupported compression methods, excessive entry counts, and
excessive expanded size.
