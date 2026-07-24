# VisualGroundingKit
`VisualGroundingKit` 是一个面向图像生成/视频生成前置控制的结构化视觉理解库。

它负责：
- 从图片中提取稳定的结构化 grounding 信息
- 将用户输入归一化为结构化动作意图
- 输出供服务端或模型侧使用的控制参数

它不负责：
- 规则拼接自然语言 Prompt
- 文案润色
- 最终模型提示词生成

---

## ✨ 项目定位

本库解决的是一个更基础、也更关键的问题：

> 如何把图片里的主体、场景、风格、文本与用户动作意图，稳定地抽取为结构化控制信号，而不是直接在客户端硬拼最终 Prompt？

不同于“图片 → 提示词”的黑盒路径，本项目采用：

👉 **视觉结构化提取 + 意图归一化 + 服务端适配生成 的工程方案**

---

## 🎯 目标（Goals）

本项目的目标是构建一个：

- 可复用的图像结构化理解核心库
- 可插拔的本地 AI / Vision 架构
- 可缓存、可解释、可调试的视觉控制层
- 面向图生视频 / 图生图 / 特效生成的前置控制系统
- 为服务端 Prompt Builder、模型适配器、LLM 重写层提供稳定输入

---

## 🧠 核心思路

本项目**不再把“客户端直接生成最终提示词”作为核心目标**。

而是拆成四层：

1. Image Preprocessing（图片预处理）
2. Visual Grounding（视觉结构化提取）
3. Intent Normalization（用户意图归一化）
4. Control Export（导出供服务端消费的控制数据）

---

## 🏗 架构设计

```text
UI / App Layer
    ↓
GenerateVisualControlUseCase
    ↓
ImagePreprocessing
    ↓
ImageUnderstandingService
    ↓
GroundingMappingService
    ↓
UserIntentNormalizingService
    ↓
VisualControlBundle
```
--- 

Layer 1: Visual Facts
- 主体
- 场景
- 风格
- OCR
- 构图

Layer 2: Generation Hints
- 内容类型
- 动态候选
- 保持约束
- 风险等级

Layer 3: Server-Side Prompt Adaptation
- 由服务端根据不同模型做提示词生成与增强

## 📦 项目结构
```text
VisualGroundingKit/
├── Domain/
│   ├── Models/
│   ├── Services/
│   └── UseCases/
├── Infrastructure/
│   ├── Preprocessing/
│   ├── Vision/
│   ├── Grounding/
│   ├── Intent/
│   ├── Cache/
│   └── Debug/
├── Facade/
└── Extensions/
```
---

## 🧩 核心数据结构
### InputImageAsset

表示输入图片及其角色：
- mainSubject
- secondarySubject
- backgroundReference
- styleReference

---
### ImageDescriptor

单张图片的原始结构化分析结果：
- 主体检测结果（人物 / 动物 / 物体 / 未知）
- 主体数量
- 主体姿态
- 边界框
- 背景标签
- 风格标签
- OCR 文本
- 调试信息
---

### VisualGroundingPayload

面向生成控制使用的统一结构化结果：
- subjects
- scene
- style
- recognizedTexts
- debugSummary

它不是最终 Prompt，而是更稳定的中间控制层。

---
### NormalizedIntentPayload

用户输入归一化后的意图结构：
- subjectMotion
- cameraMotion
- environmentMotion
- styleIntent
- facialExpression
- sourceSummary

它的职责不是生成文案，而是表达：
- 用户希望谁动
- 怎么动
- 镜头是否变化
- 环境是否变化
- 是否存在风格倾向

---

### VisualControlBundle

最终导出的控制数据，用于给服务端消费：
- grounding
- normalizedIntent
- controlParameters
- debugSummary

未来可直接作为：
- 视频 Prompt Builder 输入
- 多模型适配层输入
- 本地 LLM / 服务端 LLM 上下文输入
- 调试日志与评测输入

---

## 🚀 使用方式
### 创建 UseCase
```swift
let useCase = VisualGroundingKitFactory.makeDefaultUseCase()
```
--- 

### 构造输入
```swift
let assets = [
    InputImageAsset(
        image: image1,
        source: .photoLibrary,
        role: .mainSubject
    )
]
```
---

### 生成结构化控制结果
```swift
let result = try await useCase.execute(
    images: assets,
    userIntent: "看向镜头并挥手",
    language: .chinese,
    task: .imageToVideo
)

print(result.grounding)
print(result.normalizedIntent)
print(result.controlParameters)
```
---

## 🔧 当前实现边界（当前方向）
### 本库负责
- 图片主体提取
- 图片场景提取
- 图片风格提取
- OCR 文本提取与截图/文档降级识别
- 用户动作意图归一化
- 可调试、可缓存的结构化控制输出

---

### 本库不负责
- 客户端直接生成高质量最终 Prompt
- 客户端规则拼接自然语言成品提示词
- 与具体视频模型强耦合的最终文案适配
- 创意写作型提示词生成

--

这些能力未来应放在：
- 服务端 Prompt Builder
- 服务端模型适配器
- 云端或本地 LLM Rewrite 层

--- 

### 🧠 设计原则

#### 1. 结构化优先，而不是文案优先

本项目优先产出：
- 稳定
- 可解释
- 可验证
- 可缓存

的视觉控制数据，而不是追求客户端“直接写出好看的提示词”。

---

#### 2. Grounding 与 Prompt 解耦

采用：
- 图片 → Descriptor → Grounding
- 用户输入 → Intent
- Grounding + Intent → 服务端 Prompt Builder

而不是在客户端走：
- 图片 → 规则拼提示词

---

#### 3. 本地优先，但职责克制

未来支持：
- Vision
- Core ML
- Apple Foundation Models
- 本地小模型 / 本地 LLM

但本地模型优先用于：
- 视觉理解增强
- 用户意图归一化增强
- 轻量候选意图生成

而不是在客户端承担复杂的最终 Prompt 写作职责。

---

#### 4. 服务端做模型适配

不同视频模型对提示词组织方式不同。
因此最终 Prompt 生成应放在服务端完成，由服务端基于统一结构化输入，适配不同模型：
- Seedance
- Google Veo
- OpenAI 视频模型
- 其他第三方视频模型

---

#### 5. 可评测优先

本项目的价值不应靠“感觉”，而应通过评测验证：
- 主体一致性是否更稳
- 背景漂移是否更少
- 主体数量是否更稳定
- 用户动作命中率是否更高
- 是否比“只喂原图 + 用户原文”更好

如果结构化输入对结果没有提升，这条路线就应及时收缩。

---

## 📌 当前核心需求

一、图片结构化信息提取（必须保留）

这是本项目的核心基础能力，必须做，并且要持续完善。

目标包括：
- 主体类型识别
- 主体数量识别
- 主体优先级判断
- 场景与背景识别
- 风格与氛围标签提取
- OCR 文本识别
- 截图 / 文档 / UI 场景降级识别
- 稳定输出统一 Grounding Schema

---

二、用户输入意图归一化（必须保留）

用户输入不是最终 Prompt，而是“动作倾向”。

例如：
- 点头
- 挥手
- 看向镜头
- 转身
- 动起来
- 轻微互动

这些输入需要根据 Grounding 做约束与过滤：
- 动物不能直接套用人的动作
- 截图 / 文档不能套用人物动作
- unknown / object 场景要谨慎降级
- scene 类图片优先转为环境动态，而不是主体动作

---

三、客户端自动生成意图提示词（可选能力）

这个需求不是必须做成规则系统。

结论如下：
- 如果本地模型可以稳定根据图片或 Grounding 生成“意图提示词候选”，就保留
- 如果本地做不到稳定输出，就不做这个需求
- 不再用大规模规则系统硬拼
- 不再把客户端“文案生成”当作主链核心

---

## 🧪 推荐输出模式

客户端输出

客户端只输出：
1.    ImageGroundingPayload
2.    NormalizedIntentPayload
3.    ControlParameters

服务端输入

服务端消费这些结构后，再做：
- Prompt Builder
- Model Adapter
- Prompt Rewrite
- 生成策略控制

---

## 🛣 Roadmap

Phase 1（当前）
- 架构重命名与职责收敛
- Vision 结构化提取稳定化
- User Intent Normalization 稳定化
- 去掉客户端规则拼 Prompt 主链

Phase 2
- 主体优先级与显著性判断优化
- 动物 / 人物 / 物体 / 截图 / 文档分类完善
- OCR 密度与截图场景降级策略完善
- Grounding Schema 固化

Phase 3
- 本地模型辅助意图生成验证
- 对比“纯图输入”与“结构化输入”效果差异
- 建立结构化输入评测体系

Phase 4
- 服务端 Prompt Builder 接入
- 多模型适配（Seedance / Veo / OpenAI 等）
- Prompt Rewrite / Model Adapter 完整打通

---

## ⚠️ 当前限制
- Vision 检测对复杂图片仍可能误判
- 动物 / 人物 / 小脸干扰等问题仍需继续优化
- 截图 / 文档 / UI 类图片仍需更强降级识别
- 用户动作归一化词表覆盖还不够完整
- 当前尚未完成服务端 Prompt Builder 验证
- 尚未证明结构化输入对具体视频模型的收益上限

---

## 📌 使用场景
- 图生视频前置控制
- 图生图前置控制
- 特效模板控制输入
- 多模型 Prompt 适配前的数据准备
- 本地视觉理解与生成控制系统

---

## 🧑‍💻 作者说明

本项目面向：
- iOS / 客户端本地 AI 产品
- 图像到视频生成链路
- 轻量、可解释、可调试的视觉控制架构

它不是一个“黑盒提示词生成器”，
而是一个更底层、更工程化的：

视觉结构化与生成控制基础库

---

## 📄 License

本项目遵循MIT许可证协议 - 详情请参阅[LICENSE](LICENSE)文件
