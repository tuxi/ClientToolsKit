# Core ML Object Detection Model

VisualGroundingKit bundles a quantized YOLOv8n model for general object detection.

## Model Source

- **Model**: YOLOv8n (YOLOv8 nano, ~6.2M parameters)
- **Source**: [Ultralytics YOLOv8](https://github.com/ultralytics/ultralytics)
- **License**: AGPL-3.0 (applies to the model file in this directory)
- **Training data**: COCO 2017 (80 classes)
- **Input size**: 640×640 pixels

## Generating the .mlmodel File

The `.mlmodel` file is generated once, before building, using the Ultralytics Python
package. It is NOT regenerated at build time.

### Prerequisites

```bash
pip install ultralytics
```

### Export

```bash
python -c "
from ultralytics import YOLO
model = YOLO('yolov8n.pt')
model.export(format='coreml', nms=True, imgsz=640)
"
```

This produces `yolov8n.mlmodel` in the current directory.

### Adding to the Project

The export produces a `.mlpackage` (Core ML package format). Copy or move it to:

```
VisualGroundingKit/Sources/VisualGroundingKit/Resources/yolov8n.mlpackage
```

At runtime, the detector tries formats in this order:
1. `.mlmodelc` — compiled by Xcode when building a host app (fastest)
2. `.mlpackage` — raw export, loaded directly by MLModel (SPM development)

The `.pt` PyTorch weights file should NOT be added to Resources; it's only
needed during the export step and can be deleted afterwards.

## Model Details

- **Precision**: Float16 (Core ML quantizes further on Neural Engine)
- **NMS**: Built-in via `nms=True`
- **Output**: `VNRecognizedObjectObservation` — each with bounding box, label,
  and confidence
- **Inference**: < 50ms on Apple Neural Engine (A12+)
- **Size on disk**: ~6.5 MB (.mlpackage), ~12 MB (.pt source weights)

## COCO Classes

The model detects 80 classes:

```
person, bicycle, car, motorcycle, airplane, bus, train, truck, boat,
traffic light, fire hydrant, stop sign, parking meter, bench,
bird, cat, dog, horse, sheep, cow, elephant, bear, zebra, giraffe,
backpack, umbrella, handbag, tie, suitcase, frisbee, skis, snowboard,
sports ball, kite, baseball bat, baseball glove, skateboard, surfboard,
tennis racket, bottle, wine glass, cup, fork, knife, spoon, bowl,
banana, apple, sandwich, orange, broccoli, carrot, hot dog, pizza,
donut, cake, chair, couch, potted plant, bed, dining table, toilet,
tv, laptop, mouse, remote, keyboard, cell phone, microwave, oven,
toaster, sink, refrigerator, book, clock, vase, scissors, teddy bear,
hair drier, toothbrush
```

These are the only classes the detector can identify. Objects outside this
set (e.g., UI elements, specific brand products) will not be detected.

## Last Update

- **Model version**: YOLOv8n (ultralytics 8.x)
- **Build date**: (add when model is generated)
