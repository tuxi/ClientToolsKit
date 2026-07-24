# iOS 端 Vision 视觉分析采集改造技术方案

## 1. 文档目标

本文档用于将当前 `VisualGroundingKit` 从“本地关键词映射与结构化解释”调整为“本地视觉采集与低语义结构化分层”。

改造后的职责边界如下：

- 客户端负责：
  - Apple Vision 原生 observation 采集
  - 确定性图像测量
  - 低语义结构化分层
  - 与现有输出结构兼容的 JSON 组织
- 客户端不负责：
  - Prompt 生成
  - 文案摘要
  - 情绪、氛围、电影感、冷暖色调等主观判断
  - 服务端业务规则拼装
- 服务端负责：
  - 基于结构化事实做语义理解
  - Prompt 生成
  - 模型适配与业务规则演进

---

## 2. 设计原则

### 2.1 强制原则

1. 保留现有返回结构
   - `normalizedIntent`
   - `visualGrounding`
   - `analysisResults`
   以上字段全部保留，不删、不改名、不重命名。

2. 新能力只做增量字段补充
   - 在顶层和 `visualGrounding` 内追加字段
   - 原有 `contentType / motionHints / preservationHints / normalizedIntent` 保持兼容

3. 客户端只做三类工作
   - Vision 原生采集
   - 确定性测量
   - 结构化分层

4. 不在客户端做以下工作
   - prompt 片段拼接
   - 风格、情绪、氛围推断
   - 主观摘要
   - 服务端业务规则前置

### 2.2 能力边界定义

为避免字段语义混乱，新增字段必须明确归属到下列三类来源之一：

1. `vision_native`
   - 直接来自 Apple Vision observation 或原生识别结果
   - 例如：人脸框、人体关键点、OCR 识别文本、图像分类标签

2. `deterministic_measure`
   - 通过图像处理算法直接测量得到
   - 不依赖业务语义
   - 例如：亮度、清晰度、边缘密度、背景复杂度

3. `structured_partition`
   - 基于原生 observation 与测量结果做低语义分层
   - 例如：`uiTextBlocks / naturalTextBlocks / hasOverlayUI / isMixedPhotoWithUI / portraitFraming`

说明：
- `structured_partition` 不是 Prompt 语义推理
- 但它也不是 Apple Vision 直接返回的原生字段
- 文档、代码注释、接口说明中必须明确区分

---

## 3. 现有框架问题与改造方向

### 3.1 当前问题

当前 `VisualGroundingKit` 主要问题不在整体分层，而在分析链路过度依赖关键词映射：

1. `scene` 与 `style` 大量依赖分类标签的关键词规则映射
2. `ImageDescriptor` 预留了多个字段，但采集层未真正填充
3. OCR 仅有整图文本输出，没有 UI 文本与自然文本分层
4. 主体检测以“单个合并主体”为主，不利于扩充人像属性
5. 缺少画面基础测量层，无法稳定提供亮度、清晰度、背景复杂度

### 3.2 改造目标

将当前链路从：

`Vision 标签 -> 规则解释 -> 语义化 grounding`

调整为：

`Vision 原生 observation -> 测量与分层 -> 结构化 facts -> 服务端 LLM`

---

## 4. 字段保留与改造结论

## 4.1 必须保留的现有字段

以下字段保留，不删除、不改名：

- 顶层：
  - `normalizedIntent`
  - `visualGrounding`
  - `analysisResults`
- `visualGrounding` 内：
  - `contentType`
  - `subjects`
  - `scene`
  - `style`
  - `composition`
  - `text`
  - `motionHints`
  - `preservationHints`
  - `debug`

说明：
- `scene / style` 在第一阶段可以继续输出，用于兼容
- 但后续不再作为重点增强方向
- 新方案的主增强方向是“原生 facts 采集 + 分层”

## 4.2 建议改定义的字段

以下字段可以保留名字或新增，但定义必须调整，不能再描述为“Vision 原生直接给出”。

### A. `environmentType`

建议定义：

- 含义：画面环境的低语义分桶结果
- 枚举：
  - `indoor`
  - `outdoor`
  - `natural`
  - `urban`
  - `room`
  - `plain`
- 来源类别：`structured_partition`

说明：
- 不是 Vision 原生枚举
- 是基于分类 observation、显著区域、对象存在性与版面特征做低语义分桶

### B. `imageBrightness`

建议定义：

- 含义：整图亮度分桶
- 枚举：
  - `bright`
  - `normal`
  - `dark`
- 来源类别：`deterministic_measure`

说明：
- 不应写成“Vision 原生亮度识别”
- 应通过图像亮度测量实现

### C. `imageSharpness`

建议定义：

- 含义：整图清晰度分桶
- 枚举：
  - `sharp`
  - `normal`
  - `blurry`
- 来源类别：`deterministic_measure`

说明：
- 不应写成“Vision 原生清晰度识别”
- 应通过边缘能量或拉普拉斯方差测量实现

### D. `hasOverlayUI`

建议定义：

- 含义：画面中是否存在明显 UI 层文本或控件元素
- 来源类别：`structured_partition`

说明：
- 不是 Vision 原生布尔值
- 是基于 OCR 框分布、边缘区域、文本样式分布等结构化分层结果

### E. `isMixedPhotoWithUI`

建议定义：

- 含义：底层存在实景图像内容，同时上层存在明显 UI 干扰
- 来源类别：`structured_partition`

说明：
- 不应描述为“Vision 原生混合图识别”
- 应描述为“结构化混合画面分层结论”

### F. `backgroundType`

建议定义：

- 含义：背景复杂度/纯净度的机械分桶结果
- 枚举：
  - `blurred`
  - `simple`
  - `complex`
  - `pure`
- 来源类别：`deterministic_measure` + `structured_partition`

说明：
- 不是 Vision 原生字段
- 由背景区域纹理复杂度、边缘密度、主体前景占比、显著性分布共同得出

### G. `portraitFraming`

建议定义：

- 含义：人像景别的机械分桶
- 枚举：
  - `close_up`
  - `medium_shot`
  - `full_body`
- 来源类别：`structured_partition`

说明：
- 由人脸框占比、人体框占比、关键点完整度计算
- 不属于主观语义推理

### H. `postureType`

建议定义：

- 含义：人物静态姿态分桶
- 枚举：
  - `standing`
  - `sitting`
  - `walking`
  - `static`
- 来源类别：`structured_partition`

说明：
- 基于人体关键点几何关系得出
- 不做动作剧情判断

## 4.3 不能承诺为 Vision 原生字段

以下字段不应在文档、代码、接口说明中标记为“Apple Vision 原生结果”：

- `environmentType`
- `imageBrightness`
- `imageSharpness`
- `hasOverlayUI`
- `isMixedPhotoWithUI`
- `naturalTextBlocks`
- `uiTextBlocks`
- `postureType`
- `portraitFraming`
- `backgroundType`

其中：
- `naturalTextBlocks / uiTextBlocks` 的文本内容来自 OCR 原生识别
- 但“分层归类”不是 Vision 直接输出

## 4.4 不建议承诺输出的字段

以下字段不建议作为稳定事实字段在客户端强承诺：

### A. `gender`

原因：
- Apple Vision 没有稳定公开的人脸性别原生输出
- 误判代价高
- 容易造成接口事实层污染

建议：
- 若产品必须保留字段，则仅允许输出 `unknown`
- 更推荐不新增该字段

### B. `ageLevel`

原因：
- Apple Vision 没有稳定公开的人脸年龄段原生输出
- 年龄推断属于高风险属性判断
- 远景、遮挡、化妆、角度都会导致误判

建议：
- 若产品必须保留字段，则仅允许输出 `unknown`
- 更推荐不新增该字段

结论：
- 本技术方案不建议在第一阶段实现 `gender / ageLevel`
- 若业务层强制要求，必须在接口文档中明确其为“预留字段，默认 unknown”

---

## 5. 建议新增的数据结构

以下方案遵循“兼容现有结构，只增量加字段”。

## 5.1 顶层新增 `imageFacts`

建议新增一个顶层聚合结构，而不是把所有字段平铺在根级别。

原因：
- 降低顶层污染
- 便于区分新增采集层与现有 `visualGrounding`
- 后续扩展更安全

建议结构：

```swift
public struct ImageFactsPayload: Sendable, Hashable, Codable {
    public let environmentType: EnvironmentType?
    public let imageBrightness: ImageBrightnessLevel?
    public let imageSharpness: ImageSharpnessLevel?
    public let hasOverlayUI: Bool?
    public let isMixedPhotoWithUI: Bool?
    public let naturalTextBlocks: [String]
    public let uiTextBlocks: [String]
}
```

如必须与现有服务端字段保持一致，也可以在序列化层平铺输出到根级别：

- `environmentType`
- `imageBrightness`
- `imageSharpness`
- `hasOverlayUI`
- `isMixedPhotoWithUI`
- `naturalTextBlocks`
- `uiTextBlocks`

建议内部模型保留 `ImageFactsPayload`，输出层再决定是否平铺。

## 5.2 在 `ImageDescriptor` 中新增原始采集层

建议新增：

```swift
public struct RawVisionAnalysis: Sendable, Codable {
    public let faces: [RawFaceObservation]
    public let humanBodies: [RawHumanBodyObservation]
    public let recognizedTexts: [RawRecognizedTextObservation]
    public let classifications: [RawClassificationObservation]
    public let saliencyRegions: [RawSaliencyRegion]
}
```

并在 `ImageDescriptor` 中追加：

```swift
public let rawVision: RawVisionAnalysis?
public let imageFacts: ImageFactsDescriptor?
```

## 5.3 新增 `ImageFactsDescriptor`

```swift
public struct ImageFactsDescriptor: Sendable, Codable {
    public let environmentType: EnvironmentType?
    public let imageBrightness: ImageBrightnessLevel?
    public let imageSharpness: ImageSharpnessLevel?
    public let hasOverlayUI: Bool?
    public let isMixedPhotoWithUI: Bool?
    public let naturalTextBlocks: [RecognizedTextBlock]
    public let uiTextBlocks: [RecognizedTextBlock]
}
```

说明：
- `Descriptor` 层保留带框文本块
- `Payload` 层可以只输出字符串数组

## 5.4 在 `DetectedSubject` 上追加保守人像字段

建议追加：

```swift
public struct SubjectAttributes: Sendable, Codable {
    ...
    public let postureType: String?
    public let portraitFraming: String?
    public let gender: String?
    public let ageLevel: String?
}
```

落地建议：
- 第一阶段：
  - `postureType`
  - `portraitFraming`
- `gender / ageLevel` 不建议真正实现
- 若必须保留字段：
  - 仅在 person 主体下输出
  - 默认值为 `unknown`

## 5.5 扩充 `CompositionDescriptor`

建议追加：

```swift
public struct CompositionDescriptor: Sendable, Codable {
    public let shotType: String?
    public let angle: String?
    public let framing: String?
    public let subjectPosition: String?
    public let depthHint: String?
    public let backgroundType: String?
}
```

---

## 6. 建议新增的 Analyzer

## 6.1 `VisionRawObservationAnalyzer`

职责：
- 统一采集所有原生 Vision observation

建议输出：
- face observations
- body pose observations
- text observations
- image classifications
- saliency observations

建议接口：

```swift
public protocol RawVisionAnalyzing: Sendable {
    func analyze(in image: VisualImage) async throws -> RawVisionAnalysis
}
```

说明：
- 当前 `VisionSubjectDetector / VisionOCRAnalyzer / VisionBackgroundAnalyzer / VisionStyleAnalyzer` 是拆散的
- 新增统一 raw analyzer 后，后续 analyzer 可以共享结果，避免重复请求

## 6.2 `ImageFactsAnalyzer`

职责：
- 基于 raw observations 与图像测量生成 `ImageFactsDescriptor`

建议接口：

```swift
public protocol ImageFactsAnalyzing: Sendable {
    func analyze(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> ImageFactsDescriptor
}
```

包含能力：
- `environmentType`
- `imageBrightness`
- `imageSharpness`
- `hasOverlayUI`
- `isMixedPhotoWithUI`
- `naturalTextBlocks`
- `uiTextBlocks`

## 6.3 `ImageQualityMeasurer`

职责：
- 做纯测量，不做语义解释

建议接口：

```swift
public protocol ImageQualityMeasuring: Sendable {
    func brightness(of image: VisualImage) async throws -> ImageBrightnessLevel?
    func sharpness(of image: VisualImage) async throws -> ImageSharpnessLevel?
}
```

实现建议：
- 亮度：平均 luminance / histogram
- 清晰度：Laplacian variance / gradient energy

## 6.4 `OverlayUIPartitionAnalyzer`

职责：
- 将 OCR 文本分成自然文本与 UI 文本
- 输出 `hasOverlayUI` 与 `isMixedPhotoWithUI`

建议接口：

```swift
public protocol OverlayUIPartitionAnalyzing: Sendable {
    func partition(
        image: VisualImage,
        rawVision: RawVisionAnalysis
    ) async throws -> OverlayUIPartitionResult
}
```

输出：

```swift
public struct OverlayUIPartitionResult: Sendable, Codable {
    public let naturalTextBlocks: [RecognizedTextBlock]
    public let uiTextBlocks: [RecognizedTextBlock]
    public let hasOverlayUI: Bool
    public let isMixedPhotoWithUI: Bool
}
```

说明：
- 这是结构化分层器，不是 prompt 规则器

## 6.5 `PortraitAttributeAnalyzer`

职责：
- 为 person 主体补充低风险机械属性

建议接口：

```swift
public protocol PortraitAttributeAnalyzing: Sendable {
    func analyze(
        image: VisualImage,
        faces: [RawFaceObservation],
        bodies: [RawHumanBodyObservation]
    ) async throws -> PortraitAttributeResult
}
```

输出：
- `postureType`
- `portraitFraming`
- 可选 `gender`
- 可选 `ageLevel`

实施建议：
- 第一阶段只实现 `postureType / portraitFraming`
- `gender / ageLevel` 不默认实现

## 6.6 `BackgroundComplexityAnalyzer`

职责：
- 生成 `backgroundType`

建议接口：

```swift
public protocol BackgroundComplexityAnalyzing: Sendable {
    func analyze(
        image: VisualImage,
        subjectBoxes: [CGRect],
        saliencyRegions: [RawSaliencyRegion]
    ) async throws -> BackgroundType?
}
```

说明：
- 该 analyzer 不输出“美学风格”
- 只输出背景结构复杂度

---

## 7. 推荐的枚举定义

```swift
public enum EnvironmentType: String, Sendable, Codable {
    case indoor
    case outdoor
    case natural
    case urban
    case room
    case plain
}

public enum ImageBrightnessLevel: String, Sendable, Codable {
    case bright
    case normal
    case dark
}

public enum ImageSharpnessLevel: String, Sendable, Codable {
    case sharp
    case normal
    case blurry
}

public enum PortraitPostureType: String, Sendable, Codable {
    case standing
    case sitting
    case walking
    case static
}

public enum PortraitFramingType: String, Sendable, Codable {
    case closeUp = "close_up"
    case mediumShot = "medium_shot"
    case fullBody = "full_body"
}

public enum BackgroundType: String, Sendable, Codable {
    case blurred
    case simple
    case complex
    case pure
}
```

关于 `gender / ageLevel`：

```swift
public enum SubjectGender: String, Sendable, Codable {
    case male
    case female
    case unknown
}

public enum SubjectAgeLevel: String, Sendable, Codable {
    case child
    case young
    case adult
    case elderly
    case unknown
}
```

建议：
- 枚举可以先定义
- 第一阶段不实际输出，或仅输出 `unknown`

---

## 8. 与现有代码的对接方案

## 8.1 保持现有入口不变

继续保留：

```swift
let useCase = VisualGroundingKitFactory.makeDefaultUseCase()
```

`PrepareVisualGenerationUseCase.prepare(...)` 接口不变。

## 8.2 `LocalImageUnderstandingService` 调整方向

当前：
- 分别调用 subject/background/style/ocr

建议调整为：

1. 统一先采 `rawVision`
2. 再做以下派生分析：
   - subject detection
   - image facts
   - composition enhancement
   - background complexity
3. 原有 `background/style` analyzer 保留兼容输出，但不再作为主增强方向

推荐新链路：

```text
ImagePreprocessor
    ↓
VisionRawObservationAnalyzer
    ↓
├─ SubjectAnalyzer
├─ ImageFactsAnalyzer
├─ BackgroundComplexityAnalyzer
├─ OCR Partition Analyzer
└─ Compatibility Background/Style Analyzer
    ↓
ImageDescriptor
    ↓
DefaultVisualGroundingMapper
```

## 8.3 `DefaultVisualGroundingMapper` 改造方向

改造原则：

1. 继续保留现有字段映射，保证兼容
2. 减少新的关键词语义规则
3. 优先将 `ImageDescriptor.imageFacts` 和增强后的 `DetectedSubject / CompositionDescriptor` 原样透传到 payload

推荐新增 payload 映射点：

- 顶层：
  - `imageFacts`
  - 或序列化时平铺为根级字段
- `visualGrounding.subjects[]`
  - `postureType`
  - `portraitFraming`
  - 可选 `gender`
  - 可选 `ageLevel`
- `visualGrounding.composition`
  - `backgroundType`

---

## 9. 建议的最终 JSON Schema

说明：
- 以下为推荐的最终对外结构
- 为兼容现有服务端，可以保留根级平铺字段
- 若内部实现使用 `imageFacts` 聚合，也建议在输出层平铺映射

```json
{
  "environmentType": "outdoor",
  "imageBrightness": "normal",
  "imageSharpness": "sharp",
  "hasOverlayUI": false,
  "isMixedPhotoWithUI": false,
  "naturalTextBlocks": [
    "Dream Cafe"
  ],
  "uiTextBlocks": [
    "10:30",
    "发布"
  ],
  "normalizedIntent": {
    "styleTokens": ["realistic"],
    "cameraMotion": "slow_push_in",
    "subjectMotionTokens": ["start standing pose", "subtle standing motion"]
  },
  "visualGrounding": {
    "contentType": {
      "primaryType": "portraitPhoto",
      "secondaryTypes": [],
      "isScreenshotLike": false,
      "isDocumentLike": false,
      "isUILayoutLike": false,
      "isPhotoLike": true
    },
    "subjects": [
      {
        "id": "subject_0",
        "type": "person",
        "coreLabel": "person",
        "count": 1,
        "postureType": "standing",
        "portraitFraming": "medium_shot",
        "boundingBoxes": [],
        "confidence": 0.92
      }
    ],
    "composition": {
      "shotType": "medium_shot",
      "cameraAngle": "eye_level",
      "backgroundType": "blurred"
    },
    "motionHints": {
      "recommendedMotionProfile": "subtlePortraitMotion"
    },
    "preservationHints": {},
    "debug": {}
  },
  "analysisResults": [
    {
      "descriptor": {
        "rawVision": {
          "faces": [],
          "humanBodies": [],
          "recognizedTexts": [],
          "classifications": [],
          "saliencyRegions": []
        },
        "imageFacts": {
          "environmentType": "outdoor",
          "imageBrightness": "normal",
          "imageSharpness": "sharp",
          "hasOverlayUI": false,
          "isMixedPhotoWithUI": false,
          "naturalTextBlocks": [
            {
              "text": "Dream Cafe",
              "boundingBox": "{{rect}}"
            }
          ],
          "uiTextBlocks": [
            {
              "text": "10:30",
              "boundingBox": "{{rect}}"
            }
          ]
        }
      },
      "visualGrounding": {}
    }
  ]
}
```

---

## 10. 字段输出约束

### 10.1 仅在有值时输出

应遵循：
- 非必要字段无值不输出
- 减少报文体积
- 保证字段语义稳定

### 10.2 人像字段输出约束

仅当主体为 `person` 时输出：
- `postureType`
- `portraitFraming`
- `gender`
- `ageLevel`

其中：
- 第一阶段推荐只实际输出前两项
- 后两项默认不输出或仅 `unknown`

### 10.3 文本分层输出约束

- OCR 原文不改写
- 不删除原文中的特殊字符
- 不做润色
- 只做分层归类

---

## 11. 分阶段实施建议

## Phase 1：基础采集改造

目标：
- 建立 `RawVisionAnalysis`
- 建立 `ImageFactsDescriptor`
- 跑通新的采集链路

交付：
- raw observation 采集
- OCR 文本保留
- 亮度与清晰度测量

## Phase 2：文本分层与混合图识别

目标：
- 实现 `naturalTextBlocks / uiTextBlocks`
- 实现 `hasOverlayUI / isMixedPhotoWithUI`

交付：
- 纯照片
- 纯截图
- 照片 + UI 混合图
三类样例稳定区分

## Phase 3：人像与构图增强

目标：
- 实现 `postureType`
- 实现 `portraitFraming`
- 实现 `backgroundType`

## Phase 4：兼容层清理

目标：
- 减少对 `scene/style` 关键词映射的依赖
- 保持对旧服务端的兼容输出

---

## 12. 最终结论

本次改造不建议继续沿着“关键词映射 -> 客户端语义解释”方向增强 `VisualGroundingKit`。

推荐的最终定位是：

`VisualGroundingKit = 本地视觉原生采集层 + 确定性图像测量层 + 结构化低语义分层层`

能力重心应放在：

1. 原始 observation 采集面补齐
2. OCR 文本双层拆分
3. 图像基础属性测量
4. 人像机械属性补充
5. 与现有 schema 的兼容透传

而不是继续增强：

1. 风格关键词映射
2. 场景情绪推断
3. 客户端 prompt 解释逻辑

这条路径更符合当前产品目标，也更适合后续服务端 LLM 统一承接 Prompt 生成。
