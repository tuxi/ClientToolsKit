# VisualGroundingKit 下一阶段字段设计文档

## 1. 文档目标

本文档用于承接当前 `VisualGroundingKit` 已完成的结构化采集改造，并规划下一阶段最值得补强的客户端能力。

本文档重点回答 4 个问题：

- 下一阶段优先补哪些字段
- 这些字段应落到哪些 Swift model
- 应新增或扩展哪些 analyzer
- 哪些字段可以视为 Vision 原生，哪些只能做保守推断

本文档默认约束：

- 保留现有顶层结构：
  - `generationContext`
  - `visualGrounding`
  - `normalizedIntent`
  - `analysisResults`
- 不在客户端生成 Prompt
- 不在客户端做强语义身份判断
- 优先补“服务端消费价值高”的弱标签与机械属性

---

## 2. 本阶段核心目标

当前 `VisualGroundingKit` 已经能稳定输出：

- `contentType`
- `imageFacts`
- `motionHints`
- `postureType`
- `portraitFraming`
- `backgroundType`
- `generationContext`

但在实际服务端联调中，仍有 3 个明显短板：

1. 主体描述过泛
   - 例如单人图片最终只剩 `person`
   - 服务端容易稳定生成成“一个人物 / 一位人物”

2. 环境对象过粗
   - 例如大量户外场景最终只剩 `plants / outdoor natural scene`
   - 服务端难以自然生成“树前 / 路边 / 草地旁”

3. 人物关系与主体-场景权重表达不足
   - 服务端容易脑补关系
   - 或过度套用“人像模板”

因此下一阶段目标应聚焦为：

1. 强化主体弱标签
2. 强化环境对象细度
3. 增加服务端可直接消费的 `promptHints`
4. 保守补充关系弱提示

---

## 3. 优先级总览

建议优先级固定为：

1. `P0` 主体弱标签增强
2. `P1` 环境对象增强
3. `P2` 服务端消费型 `promptHints`
4. `P3` 人物关系弱提示
5. `P4` 构图补强

原因：

- `P0/P1/P2` 对服务端提示词质量提升最直接
- `P3` 风险稍高，必须保守推进
- `P4` 价值稳定，但优先级略低于主体与环境可读性

---

## 4. Phase P0：主体弱标签增强

## 4.1 目标

让服务端不再只能消费：

- `type = person`
- `count = 1`

而是能拿到更自然的主体路由信号，例如：

- `single_person`
- `child_like`
- `adult_like`
- `adult_child_pair`
- `subject_dominant`

---

## 4.2 建议新增字段

### A. `SubjectAttributes.subjectRefHints`

建议类型：

```swift
public let subjectRefHints: [String]
```

建议枚举值：

- `single_person`
- `single_person_child_like`
- `single_person_adult_like`
- `adult_child_pair`
- `multi_person`
- `single_animal`

说明：

- 这是服务端消费型弱标签
- 不是最终文案
- 不能承诺为 Vision 原生

来源类别：

- `structured_partition`

---

### B. `SubjectAttributes.subjectScaleHint`

建议类型：

```swift
public let subjectScaleHint: String?
```

建议枚举值：

- `small`
- `medium`
- `dominant`

说明：

- 表示主体在画面中的主导程度
- 与 `portraitFraming` 不完全等价
- 服务端可以用它判断主体是否应该成为句子主干

来源类别：

- `deterministic_measure`

---

### C. `SubjectAttributes.ageLevel`

当前已存在字段，但建议正式进入下一阶段主线。

建议枚举值先只支持：

- `child`
- `adult`
- `unknown`

说明：

- 不建议一开始支持 `young / elderly`
- 优先解决“小朋友 / 成人”的基础路由问题

来源类别：

- `structured_partition`

风险说明：

- 不能宣称为 Vision 原生年龄识别
- 只能基于分类标签与脸/人体比例做保守归纳

---

## 4.3 需要修改的 Swift model

### 修改 [ImageDescriptor.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/ImageDescriptor.swift)

扩展 `SubjectAttributes`：

```swift
public let subjectRefHints: [String]
public let subjectScaleHint: String?
```

说明：

- `ageLevel` 字段已存在，可继续沿用
- 保持默认值兼容，避免影响现有初始化调用

### 修改 [VisualGroundingPayload.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Grounding/VisualGroundingPayload.swift)

扩展 `SubjectPayload`：

```swift
public let subjectRefHints: [String]
public let subjectScaleHint: String?
```

---

## 4.4 建议新增/扩展 analyzer

### 新增 `SubjectHintAnalyzer`

建议路径：

- `Infrastructure/Understanding/SubjectHintAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionSubjectHintAnalyzer.swift`

职责：

- 根据 `DetectedSubject + RawVisionAnalysis + CompositionDescriptor`
- 生成主体弱标签与主体主导程度

建议输出结构：

```swift
public struct SubjectHintResult: Sendable {
    public let subjectRefHints: [String]
    public let subjectScaleHint: SubjectScaleHint?
    public let ageLevel: SubjectAgeLevel?
}
```

建议输入：

- 主体 bounding box
- face observations
- classifications
- `subjectCoverage`

---

## 4.5 能力边界

### 可以做

- `subjectScaleHint`
- `single_person / multi_person`
- `adult_child_pair`
- `child / adult / unknown`

### 只能保守做

- `single_person_child_like`
- `single_person_adult_like`

### 暂不建议做

- `female / male`
- `teenager`
- `elderly`
- `father / mother / daughter / son`

---

## 5. Phase P1：环境对象增强

## 5.1 目标

减少大量环境结果被压成：

- `plants`
- `outdoor natural scene`

让服务端更容易得到：

- `tree`
- `grass`
- `road`
- `path`
- `fence`

---

## 5.2 建议新增字段

### A. `ScenePayload.sceneRefHints`

建议类型：

```swift
public let sceneRefHints: [String]
```

建议枚举值：

- `roadside_like`
- `park_like`
- `tree_line_like`
- `garden_like`

来源类别：

- `structured_partition`

说明：

- 这是弱环境 hint
- 不直接替代 `environmentObjects`

---

### B. 强化 `scene.environmentObjects[]`

不是新增字段，而是增强已有对象输出细度。

优先对象：

- `tree`
- `grass`
- `road`
- `path`
- `wall`
- `building`
- `fence`

说明：

- `plants` 仍可保留
- 但如果能命中更具体对象，应同时输出更具体对象

---

## 5.3 需要修改的 Swift model

### 修改 [VisualGroundingPayload.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Grounding/VisualGroundingPayload.swift)

扩展 `ScenePayload`：

```swift
public let sceneRefHints: [String]
```

### 可选修改 [ImageDescriptor.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/ImageDescriptor.swift)

扩展 `BackgroundDescriptor`：

```swift
public let sceneRefHints: [String]
```

---

## 5.4 建议新增/扩展 analyzer

### 新增 `EnvironmentObjectRefiner`

建议路径：

- `Infrastructure/Understanding/EnvironmentObjectRefining.swift`
- `Infrastructure/Understanding/Vision/VisionEnvironmentObjectRefiner.swift`

职责：

- 基于 `RawVisionAnalysis.classifications`
- 对已有背景对象做细化与补全

建议输出：

```swift
public struct EnvironmentObjectRefineResult: Sendable {
    public let environmentObjects: [String]
    public let sceneRefHints: [String]
}
```

建议规则：

- `tree` 比 `plants` 优先级高
- `fence`、`wall`、`building` 优先直接透传
- `road/path` 只能作为保守 hint 输出

---

## 5.5 能力边界

### 可以做

- `tree`
- `grass`
- `fence`
- `wall`
- `building`

### 只能保守做

- `road`
- `path`
- `roadside_like`
- `park_like`

### 暂不建议做

- `city square`
- `suburban street`
- `forest trail`

这类过强场景语义建议仍交给服务端 LLM。

---

## 6. Phase P2：服务端消费型 Prompt Hints

## 6.1 目标

给服务端比底层 observation 更直接的路由信号，但不在客户端生成 prompt。

---

## 6.2 建议新增字段

### 新增顶层 `promptHints`

建议新增在 `VisualPreparationResult` 顶层：

```swift
public let promptHints: PromptHintsPayload?
```

建议结构：

```swift
public struct PromptHintsPayload: Sendable, Codable, Hashable {
    public let subjectRefStyle: String?
    public let subjectSceneBalance: String?
    public let motionPreference: String?
}
```

建议枚举值：

#### `subjectRefStyle`

- `single_person_generic`
- `single_person_child_like`
- `single_person_adult_like`
- `multi_person`
- `adult_child_pair`
- `animal_subject`
- `scene_dominant`

#### `subjectSceneBalance`

- `subject_dominant`
- `balanced`
- `scene_dominant`

#### `motionPreference`

- `portrait_micro_motion`
- `group_micro_motion`
- `ambient_scene_motion`
- `static_preserve`

来源类别：

- `structured_partition`

---

## 6.3 需要修改的 Swift model

### 修改 [VisualPreparationResult.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/VisualPreparationResult.swift)

新增：

```swift
public let promptHints: PromptHintsPayload?
```

### 新增文件

- `Domain/Models/PromptHints.swift`

建议内容：

- `PromptHintsPayload`
- `SubjectRefStyle`
- `SubjectSceneBalance`
- `MotionPreference`

---

## 6.4 建议新增 analyzer

### 新增 `PromptHintAnalyzer`

建议路径：

- `Infrastructure/Understanding/PromptHintAnalyzer.swift`
- `Infrastructure/Understanding/PromptHintDeriver.swift`

职责：

- 基于 `contentType + subjects + scene + composition + motionHints`
- 产出更适合服务端消费的高层弱提示

说明：

- 这不是 prompt 生成器
- 只是路由 hint derivation

---

## 6.5 能力边界

### 可以做

- `subjectSceneBalance`
- `motionPreference`
- `single_person_generic`
- `multi_person`

### 只能保守做

- `single_person_child_like`
- `adult_child_pair`

### 暂不建议做

- `beauty_portrait`
- `travel_street_style`
- `cinematic_outdoor_portrait`

这类已经接近风格 prompt，应继续留在服务端。

---

## 7. Phase P3：人物关系弱提示

## 7.1 目标

在多人图中给服务端一些关系弱信号，减少完全无引导时的脑补。

---

## 7.2 建议新增字段

### 扩展 `SubjectPayload.interactionHints`

建议扩充枚举值：

- `group_pose`
- `side_by_side`
- `close_contact`
- `holding_like`

### 可选新增 `proximityHints`

```swift
public let proximityHints: [String]
```

建议枚举值：

- `tight_pair`
- `separated_pair`

来源类别：

- `structured_partition`

---

## 7.3 需要修改的 Swift model

### 修改 [ImageDescriptor.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/ImageDescriptor.swift)

扩展 `SubjectAttributes.relationshipHints`

现有字段可继续沿用，但需要明确词表升级。

### 修改 [VisualGroundingPayload.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Grounding/VisualGroundingPayload.swift)

扩展 `SubjectPayload`：

```swift
public let proximityHints: [String]
```

---

## 7.4 建议新增 analyzer

### 新增 `SubjectRelationAnalyzer`

建议路径：

- `Infrastructure/Understanding/SubjectRelationAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionSubjectRelationAnalyzer.swift`

职责：

- 分析多主体 bbox 距离
- 分析 face/body 相对位置
- 输出非常保守的关系弱提示

建议输出：

```swift
public struct SubjectRelationResult: Sendable {
    public let interactionHints: [String]
    public let proximityHints: [String]
}
```

---

## 7.5 能力边界

### 可以做

- `group_pose`
- `side_by_side`
- `close_contact`

### 只能保守做

- `holding_like`

### 暂不建议做

- `father_daughter`
- `mother_child`
- `friends`
- `couple`

---

## 8. Phase P4：构图补强

## 8.1 目标

让服务端更少误写“中景/全景/主体主导程度”。

---

## 8.2 建议新增字段

### 扩展 `CompositionPayload`

新增：

```swift
public let subjectScaleHint: String?
public let edgePlacement: String?
public let verticalPlacement: String?
```

建议枚举值：

#### `subjectScaleHint`

- `small`
- `medium`
- `dominant`

#### `edgePlacement`

- `left`
- `center`
- `right`

#### `verticalPlacement`

- `top`
- `middle`
- `bottom`

来源类别：

- `deterministic_measure`

---

## 8.3 需要修改的 Swift model

### 修改 [ImageDescriptor.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/ImageDescriptor.swift)

扩展 `CompositionDescriptor`

### 修改 [VisualGroundingPayload.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Grounding/VisualGroundingPayload.swift)

扩展 `CompositionPayload`

---

## 8.4 建议新增 analyzer

### 新增 `CompositionHintAnalyzer`

建议路径：

- `Infrastructure/Understanding/CompositionHintAnalyzer.swift`
- `Infrastructure/Understanding/Vision/VisionCompositionHintAnalyzer.swift`

职责：

- 基于主体 bbox、face bbox、subjectCoverage
- 生成服务端更容易消费的构图 hints

---

## 9. 推荐实施顺序

建议按下面顺序推进：

1. `SubjectHintAnalyzer`
2. `EnvironmentObjectRefiner`
3. `PromptHintAnalyzer`
4. `CompositionHintAnalyzer`
5. `SubjectRelationAnalyzer`

原因：

- 先解决服务端“一个人物 / plants / 户外自然场景”这类泛化问题
- 再补服务端直接可消费的 route hints
- 最后再做关系弱提示

---

## 10. 代码落地建议

### 第一批建议修改的 model 文件

- [ImageDescriptor.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/ImageDescriptor.swift)
- [VisualGroundingPayload.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Grounding/VisualGroundingPayload.swift)
- [VisualPreparationResult.swift](/Users/xiaoyuan/Documents/work/git/Dreamlog/Packages/VisualGroundingKit/Sources/VisualGroundingKit/Domain/Models/VisualPreparationResult.swift)

### 第一批建议新增的 model 文件

- `Domain/Models/PromptHints.swift`

### 第一批建议新增的 analyzer 文件

- `Infrastructure/Understanding/SubjectHintAnalyzer.swift`
- `Infrastructure/Understanding/EnvironmentObjectRefining.swift`
- `Infrastructure/Understanding/PromptHintAnalyzer.swift`

### 第二批再上的 analyzer

- `Infrastructure/Understanding/CompositionHintAnalyzer.swift`
- `Infrastructure/Understanding/SubjectRelationAnalyzer.swift`

---

## 11. 明确不做的内容

本阶段明确不做：

- 客户端生成 prompt
- 客户端输出风格文案
- 客户端强推性别判断
- 客户端强推家庭/亲缘关系
- 客户端输出情绪、氛围、电影感结论

---

## 12. 最终目标

下一阶段完成后，客户端输出应该从当前的：

- `person`
- `plants`
- `outdoor natural scene`

逐步升级为：

- `person + child_like + subject_dominant`
- `tree + road + fence`
- `subjectRefStyle + motionPreference + subjectSceneBalance`

这样服务端就能在不依赖大段调试 JSON 的情况下，生成更自然、更少模板感、也更少脑补的提示词。
