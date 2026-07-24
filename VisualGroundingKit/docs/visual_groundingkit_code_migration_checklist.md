# VisualGroundingKit 代码改造清单

## 1. 文档目的

本文档将 [ios_vision_visual_analysis_refactor_plan.md](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/docs/ios_vision_visual_analysis_refactor_plan.md) 进一步落到代码实现层，给出：

- 先改哪些 model
- 先加哪些 analyzer
- 哪些 service 要改造
- 哪些旧 mapper 逻辑先冻结
- 按文件拆分的实施清单

本文档默认目标是：

- 保留现有对外结构：
  - `visualGrounding`
  - `normalizedIntent`
  - `analysisResults`
- 将框架能力中心从“关键词语义映射”迁移到“视觉原生采集 + 确定性测量 + 结构化分层”

---

## 2. 实施总原则

### 2.1 总体顺序

改造顺序建议固定为：

1. 先补基础数据结构
2. 再补 raw analyzer 与 image facts analyzer
3. 再改 `LocalImageUnderstandingService`
4. 最后改 `DefaultVisualGroundingMapper`
5. 旧关键词映射逻辑先冻结，不再扩写

原因：
- 如果先改 mapper，团队会继续沿着关键词规则增强
- 如果先补数据结构和 analyzer，后续服务端就能尽快吃到更干净的结构化数据

### 2.2 兼容原则

整个改造期间：

- `PrepareVisualGenerationUseCase.prepare(...)` 不改签名
- `VisualPreparationResult` 不改顶层字段名
- `VisualGroundingPayload` 不删除旧字段
- `DefaultVisualGroundingMapper` 保留兼容输出能力

---

## 3. Phase 划分

## Phase 0：冻结旧方向

目标：
- 停止继续增强关键词语义映射
- 把团队注意力切到采集层

## Phase 1：补基础 model

目标：
- 增加 raw observation 结构
- 增加 image facts 结构
- 为后续 analyzer 和 mapper 提供落点

## Phase 2：补 analyzer

目标：
- 建立 raw vision 统一采集
- 建立图像基础测量
- 建立 OCR 文本分层
- 建立人像低风险属性分析

## Phase 3：改理解链路

目标：
- 改 `LocalImageUnderstandingService`
- 将新 analyzer 接入 `ImageDescriptor`

## Phase 4：改 mapping 与 facade

目标：
- 保持兼容输出
- 让新增字段进入最终 JSON

## Phase 5：测试与样例

目标：
- 补 3 类样例输出
- 建立回归测试基础

---

## 4. 必须先冻结的旧逻辑

以下文件暂时保留，但从现在开始不再作为增强主线，不再继续加关键词映射规则。

### A. [DefaultVisualGroundingMapper.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Mapper/DefaultVisualGroundingMapper.swift)

冻结内容：
- 不再继续增加 `scene/style/contentType` 的关键词规则
- 不再继续往 `motionHints` 塞新的语义猜测
- 不再继续增强“文本密度 -> 内容语义”的业务性推断

保留原因：
- 仍要承担兼容输出
- 新数据接进来之前，不能直接移除

调整原则：
- 只做兼容
- 不做新方向增强

### B. [VisionBackgroundAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionBackgroundAnalyzer.swift)

冻结内容：
- 不再增加新的场景关键词映射
- 不再扩写天气、时间、光线等语义规则

保留原因：
- 作为兼容背景字段来源继续存在

### C. [VisionStyleAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionStyleAnalyzer.swift)

冻结内容：
- 不再增加风格、美学、情绪、色调规则

保留原因：
- 旧服务端可能仍依赖 `style`
- 但它不应再成为主方向

### D. [VisionClassificationMapping.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionClassificationMapping.swift)

冻结内容：
- 不再继续扩写关键词库

保留原因：
- 兼容旧 analyzer 使用

---

## 5. Phase 1：基础 Model 改造清单

## 5.1 需要新增的文件

### A. 新增 [ImageFacts.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/ImageFacts.swift)

职责：
- 定义顶层 image facts 相关结构和枚举

建议内容：
- `ImageFactsDescriptor`
- `ImageFactsPayload`
- `EnvironmentType`
- `ImageBrightnessLevel`
- `ImageSharpnessLevel`
- `BackgroundType`
- `PortraitPostureType`
- `PortraitFramingType`
- 可选 `SubjectGender`
- 可选 `SubjectAgeLevel`

### B. 新增 [RawVisionAnalysis.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/RawVisionAnalysis.swift)

职责：
- 承接 Vision 原生 observation 的中间结构

建议内容：
- `RawVisionAnalysis`
- `RawFaceObservation`
- `RawHumanBodyObservation`
- `RawRecognizedTextObservation`
- `RawClassificationObservation`
- `RawSaliencyRegion`

说明：
- 不要直接把 Vision SDK observation 类型塞进公开模型
- 用自定义 struct 做持久化与调试更稳

## 5.2 需要修改的现有文件

### A. 修改 [ImageDescriptor.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/ImageDescriptor.swift)

需要新增字段：

- `rawVision: RawVisionAnalysis?`
- `imageFacts: ImageFactsDescriptor?`

需要扩充字段：

- `SubjectAttributes`
  - `postureType: String?`
  - `portraitFraming: String?`
  - 可选：
    - `gender: String?`
    - `ageLevel: String?`
- `CompositionDescriptor`
  - `backgroundType: String?`

处理原则：
- 第一阶段不要删除旧字段
- 对旧代码保持默认初始化兼容

### B. 修改 [VisualGroundingPayload.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Grounding/VisualGroundingPayload.swift)

建议新增字段：

- `imageFacts: ImageFactsPayload?`

如果服务端强要求顶层平铺：
- 内部仍建议有 `imageFacts`
- 输出层再做平铺兼容

同时扩充：
- `SubjectPayload`
  - `postureType`
  - `portraitFraming`
  - 可选 `gender`
  - 可选 `ageLevel`
- `CompositionPayload`
  - `backgroundType`

### C. 修改 [VisualAnalysisResult.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Grounding/VisualAnalysisResult.swift)

目标：
- 保持原结构不变
- 不需要新增顶层字段
- 只需确保 `descriptor` 内新增的 `rawVision / imageFacts` 会被编码输出

### D. 修改 [VisualPreparationResult.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/VisualPreparationResult.swift)

目标：
- 默认不改顶层结构
- 如服务端确认需要根级平铺字段，可评估在序列化层处理

建议：
- 不要在这里直接再加多个平铺字段
- 避免污染 `VisualPreparationResult`

---

## 6. Phase 2：Analyzer 改造清单

## 6.1 新增协议文件

建议在 `Infrastructure/Understanding` 目录补协议。

### A. 新增 [RawVisionAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/RawVisionAnalyzer.swift)

定义：
- `RawVisionAnalyzing`

职责：
- 统一采集 Vision 原生 observation

### B. 新增 [ImageFactsAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/ImageFactsAnalyzer.swift)

定义：
- `ImageFactsAnalyzing`

职责：
- 结合 raw vision 与测量生成 `ImageFactsDescriptor`

### C. 新增 [ImageQualityMeasurer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/ImageQualityMeasurer.swift)

定义：
- `ImageQualityMeasuring`

职责：
- 亮度、清晰度测量

### D. 新增 [OverlayUIPartitionAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/OverlayUIPartitionAnalyzer.swift)

定义：
- `OverlayUIPartitionAnalyzing`
- `OverlayUIPartitionResult`

职责：
- 文本双层拆分
- 输出 `hasOverlayUI`
- 输出 `isMixedPhotoWithUI`

### E. 新增 [PortraitAttributeAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/PortraitAttributeAnalyzer.swift)

定义：
- `PortraitAttributeAnalyzing`
- `PortraitAttributeResult`

职责：
- 产出 `postureType`
- 产出 `portraitFraming`
- 可选保留 `gender / ageLevel` 占位

### F. 新增 [BackgroundComplexityAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/BackgroundComplexityAnalyzer.swift)

定义：
- `BackgroundComplexityAnalyzing`

职责：
- 输出 `backgroundType`

## 6.2 新增 Vision 实现文件

建议放到 `Infrastructure/Understanding/Vision/` 下。

### A. 新增 [VisionRawObservationAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionRawObservationAnalyzer.swift)

职责：
- 统一执行：
  - `VNDetectFaceRectanglesRequest`
  - `VNDetectHumanBodyPoseRequest`
  - `VNRecognizeTextRequest`
  - `VNClassifyImageRequest`
  - 可选 saliency request

输出：
- `RawVisionAnalysis`

这是整个新链路的核心入口。

### B. 新增 [VisionImageFactsAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionImageFactsAnalyzer.swift)

职责：
- 聚合：
  - 质量测量
  - OCR 分层
  - 环境分桶

输出：
- `ImageFactsDescriptor`

### C. 新增 [CoreImageQualityMeasurer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/CoreImageQualityMeasurer.swift)

职责：
- 图像亮度测量
- 图像清晰度测量

说明：
- 虽然名字不是 Vision，但属于本地确定性测量层

### D. 新增 [VisionOverlayUIPartitionAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionOverlayUIPartitionAnalyzer.swift)

职责：
- 使用 OCR observation、文本框位置分布、边缘区域特征做文本分层

注意：
- 这是结构化分层器
- 不是 prompt 语义判断器

### E. 新增 [VisionPortraitAttributeAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionPortraitAttributeAnalyzer.swift)

职责：
- 根据 face/body 几何关系产出：
  - `postureType`
  - `portraitFraming`

### F. 新增 [VisionBackgroundComplexityAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionBackgroundComplexityAnalyzer.swift)

职责：
- 基于前景框、显著区域、边缘密度输出：
  - `backgroundType`

## 6.3 需要修改的现有 analyzer

### A. 修改 [VisionSubjectDetector.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionSubjectDetector.swift)

改造目标：
- 不再自己重复发起全套 Vision 请求
- 改为优先消费 `RawVisionAnalysis`

建议方式：

1. 第一阶段：
   - 保留旧实现
   - 新增一个接受 `RawVisionAnalysis` 的内部方法
2. 第二阶段：
   - 让 `LocalImageUnderstandingService` 从 raw analyzer 统一传入

新增职责：
- 把 `postureType / portraitFraming` 写入 `SubjectAttributes`

### B. 修改 [VisionOCRAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionOCRAnalyzer.swift)

改造目标：
- 保留兼容整图 OCR 能力
- 不再作为唯一 OCR 出口

建议：
- 未来作为 `VisionRawObservationAnalyzer` 的底层组成之一
- 不再承担文本分层逻辑

### C. 保留但冻结 [VisionBackgroundAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionBackgroundAnalyzer.swift)

状态：
- 保留兼容
- 不再继续增强

### D. 保留但冻结 [VisionStyleAnalyzer.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/Vision/VisionStyleAnalyzer.swift)

状态：
- 保留兼容
- 不再继续增强

---

## 7. Phase 3：理解链路改造清单

## 7.1 核心改造文件

### A. 修改 [LocalImageUnderstandingService.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Understanding/LocalImageUnderstandingService.swift)

这是改造主战场。

当前职责：
- 并行调用：
  - subject
  - background
  - style
  - ocr

目标职责：

1. 统一先采 raw vision
2. 基于 raw vision 做：
   - subject detection
   - image facts
   - background complexity
3. 兼容调用：
   - background analyzer
   - style analyzer
4. 组装新的 `ImageDescriptor`

建议改造步骤：

第一步：扩充构造函数依赖

新增依赖：
- `rawVisionAnalyzer`
- `imageFactsAnalyzer`
- `backgroundComplexityAnalyzer`

第二步：重写 `analyze(image:)`

建议顺序：

```text
rawVision
    ↓
subjects
imageFacts
background
style
    ↓
compose ImageDescriptor
```

第三步：给 `composition.backgroundType` 赋值

第四步：把 `rawVision / imageFacts` 一起塞进 `ImageDescriptor`

### B. 可选修改 [ImageUnderstandingService.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Services/ImageUnderstandingService.swift)

原则：
- 不改公开签名
- 不新增 breaking change

---

## 8. Phase 4：Mapper 与输出层改造清单

## 8.1 核心文件

### A. 修改 [DefaultVisualGroundingMapper.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Mapper/DefaultVisualGroundingMapper.swift)

改造目标：
- 从“主解释器”降级为“兼容映射器”
- 优先透传 `ImageDescriptor` 中的新结构化字段

具体动作：

1. `map(_:)` 中增加 `imageFacts` 映射
2. `mapSubjects` 时增加：
   - `postureType`
   - `portraitFraming`
   - 可选 `gender`
   - 可选 `ageLevel`
3. `mapComposition` 时增加：
   - `backgroundType`
4. 对 `scene/style/contentType` 的旧规则仅做兼容，不再扩写

明确禁止：
- 不再继续新增更多主观语义映射

### B. 修改 [VisualGroundingMapping.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Mapper/VisualGroundingMapping.swift)

原则：
- 优先不改协议
- 若新增 payload 字段足够，不必调整协议层

### C. 可选新增输出适配文件 [VisualGroundingPayloadExportAdapter.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Mapper/VisualGroundingPayloadExportAdapter.swift)

职责：
- 如果服务端强要求根级平铺字段
- 在这里将 `imageFacts` 平铺成：
  - `environmentType`
  - `imageBrightness`
  - `imageSharpness`
  - `hasOverlayUI`
  - `isMixedPhotoWithUI`
  - `naturalTextBlocks`
  - `uiTextBlocks`

建议：
- 优先新增 export adapter
- 不要把平铺逻辑直接塞进所有 model

---

## 9. Phase 4：Facade 与组装改造清单

### A. 修改 [VisualGroundingKit.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Facade/VisualGroundingKit.swift)

目标：
- 将新 analyzer 装配进默认工厂

新增实例化：
- `VisionRawObservationAnalyzer`
- `VisionImageFactsAnalyzer`
- `CoreImageQualityMeasurer`
- `VisionOverlayUIPartitionAnalyzer`
- `VisionPortraitAttributeAnalyzer`
- `VisionBackgroundComplexityAnalyzer`

调整 `LocalImageUnderstandingService(...)` 初始化参数。

### B. 修改 [PromptCacheVersion.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Facade/PromptCacheVersion.swift)

如果缓存 key 或 schema version 与输出内容相关：
- 需要 bump 版本

目标：
- 避免旧缓存污染新 descriptor / payload 输出

### C. 修改 [InMemoryVisualAnalysisCache.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Infrastructure/Cache/InMemoryVisualAnalysisCache.swift)

原则：
- 结构本身未必需要改
- 但要确认新增字段编码后缓存是否正常

---

## 10. Phase 5：测试与样例清单

## 10.1 先修 Package 测试结构

### A. 修改 [Package.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Package.swift)

当前问题：
- `testTarget` 已声明
- 但没有真实 `Tests/VisualGroundingKitTests` 目录
- 当前 `swift build` 会因为 test target source overlap 报错

第一步必须修复：
- 显式指定测试路径
- 新建真实测试目录

## 10.2 新增测试目录

### 新增目录

`/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Tests/VisualGroundingKitTests/`

## 10.3 建议新增测试文件

### A. 新增 [ImageFactsAnalyzerTests.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Tests/VisualGroundingKitTests/ImageFactsAnalyzerTests.swift)

覆盖：
- `imageBrightness`
- `imageSharpness`
- `environmentType`

### B. 新增 [OverlayUIPartitionAnalyzerTests.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Tests/VisualGroundingKitTests/OverlayUIPartitionAnalyzerTests.swift)

覆盖：
- `naturalTextBlocks`
- `uiTextBlocks`
- `hasOverlayUI`
- `isMixedPhotoWithUI`

### C. 新增 [PortraitAttributeAnalyzerTests.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Tests/VisualGroundingKitTests/PortraitAttributeAnalyzerTests.swift)

覆盖：
- `postureType`
- `portraitFraming`

### D. 新增 [DefaultVisualGroundingMapperTests.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Tests/VisualGroundingKitTests/DefaultVisualGroundingMapperTests.swift)

覆盖：
- 新增字段是否正确映射进 payload
- 旧字段兼容性是否保持

### E. 新增 [VisualPreparationResultSnapshotTests.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Tests/VisualGroundingKitTests/VisualPreparationResultSnapshotTests.swift)

覆盖 3 类样例 JSON：
- 纯人像照片
- 风景/静物照片
- 照片 + UI 混合截图

---

## 11. 推荐实施顺序

下面是最建议的真实开发顺序。

### Step 1

先修测试结构：
- `Package.swift`
- `Tests/VisualGroundingKitTests/`

### Step 2

新增基础 model：
- `ImageFacts.swift`
- `RawVisionAnalysis.swift`

并修改：
- `ImageDescriptor.swift`
- `VisualGroundingPayload.swift`

### Step 3

新增 analyzer 协议与实现：
- `RawVisionAnalyzer.swift`
- `ImageFactsAnalyzer.swift`
- `ImageQualityMeasurer.swift`
- `OverlayUIPartitionAnalyzer.swift`
- `PortraitAttributeAnalyzer.swift`
- `BackgroundComplexityAnalyzer.swift`
- `VisionRawObservationAnalyzer.swift`
- `VisionImageFactsAnalyzer.swift`
- `CoreImageQualityMeasurer.swift`
- `VisionOverlayUIPartitionAnalyzer.swift`
- `VisionPortraitAttributeAnalyzer.swift`
- `VisionBackgroundComplexityAnalyzer.swift`

### Step 4

改造理解链路：
- `LocalImageUnderstandingService.swift`
- `VisionSubjectDetector.swift`

### Step 5

改造输出与装配：
- `DefaultVisualGroundingMapper.swift`
- `VisualGroundingKit.swift`
- `PromptCacheVersion.swift`

### Step 6

补测试与 JSON 样例。

---

## 12. 任务拆分建议

如果按并行开发拆任务，建议这样分。

### 任务 A：基础模型层

负责文件：
- `Domain/Models/ImageFacts.swift`
- `Domain/Models/RawVisionAnalysis.swift`
- `Domain/Models/ImageDescriptor.swift`
- `Domain/Grounding/VisualGroundingPayload.swift`

### 任务 B：Raw Vision 采集层

负责文件：
- `Infrastructure/Understanding/RawVisionAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionRawObservationAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionOCRAnalyzer.swift`

### 任务 C：Image Facts 与图像测量层

负责文件：
- `Infrastructure/Understanding/ImageFactsAnalyzer.swift`
- `Infrastructure/Understanding/ImageQualityMeasurer.swift`
- `Infrastructure/Understanding/OverlayUIPartitionAnalyzer.swift`
- `Infrastructure/Understanding/BackgroundComplexityAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionImageFactsAnalyzer.swift`
- `Infrastructure/Understanding/Vision/CoreImageQualityMeasurer.swift`
- `Infrastructure/Understanding/Vision/VisionOverlayUIPartitionAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionBackgroundComplexityAnalyzer.swift`

### 任务 D：主体属性层

负责文件：
- `Infrastructure/Understanding/PortraitAttributeAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionPortraitAttributeAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionSubjectDetector.swift`

### 任务 E：整合与兼容输出层

负责文件：
- `Infrastructure/Understanding/LocalImageUnderstandingService.swift`
- `Domain/Mapper/DefaultVisualGroundingMapper.swift`
- `Facade/VisualGroundingKit.swift`
- 可选 `Domain/Mapper/VisualGroundingPayloadExportAdapter.swift`

### 任务 F：测试与样例

负责文件：
- `Package.swift`
- `Tests/VisualGroundingKitTests/*`

---

## 13. 最终结论

这次代码改造的关键，不是去“优化几条规则”，而是明确把代码重心迁走：

从：

- `Vision 分类标签`
- `关键词规则解释`
- `客户端语义化 mapper`

迁移到：

- `Raw observation 采集`
- `图像基础测量`
- `文本/UI 结构化分层`
- `低风险主体属性补充`

具体执行上最重要的三条是：

1. 先冻结旧的 `background/style` 关键词增强
2. 先补 `RawVisionAnalysis + ImageFactsDescriptor`
3. 再改 `LocalImageUnderstandingService`，最后才碰 `DefaultVisualGroundingMapper`

只有按这个顺序做，`VisualGroundingKit` 才会真正从“本地 prompt 解释器遗留架构”转向“服务端 LLM 可消费的本地事实采集层”。
