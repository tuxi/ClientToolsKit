#!/usr/bin/env python3
"""Build dataset-v2 from immutable v1 images plus calibrated ground truth.

Images are copied byte-for-byte from v1. Corrections are limited to:
- removing text/containers outside the topmost active overlay from OCR/container GT;
- recording visual rectangle GT independently from semantic containers;
- retaining repeated-group member boxes for width/lead-edge diagnostics.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path
from typing import Any

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from generate_dataset import INIT_SCRIPT, PAGES, html_for  # noqa: E402

V1 = ROOT / "dataset"
V2 = ROOT / "dataset-v2"
OVERLAY_ROOTS = {
    "sheet_delete_modal": "delete_modal",
    "sheet_filters_mobile": "filter_sheet",
    "modal_payment_mobile": "payment_sheet",
    "search_command_dark": "command_palette",
}

AUDIT_JS = r"""
() => {
  const round = n => Math.round(n * 1e6) / 1e6;
  const rawVisibleRatio = el => {
    const r = el.getBoundingClientRect();
    const visibleWidth = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
    const visibleHeight = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
    return r.width > 0 && r.height > 0 ? (visibleWidth * visibleHeight) / (r.width * r.height) : 0;
  };
  const box = el => {
    const r = el.getBoundingClientRect();
    const left = Math.max(0, Math.min(innerWidth, r.left));
    const top = Math.max(0, Math.min(innerHeight, r.top));
    const right = Math.max(0, Math.min(innerWidth, r.right));
    const bottom = Math.max(0, Math.min(innerHeight, r.bottom));
    return {
      x: round(left / innerWidth),
      y: round(top / innerHeight),
      width: round((right - left) / innerWidth),
      height: round((bottom - top) / innerHeight)
    };
  };
  const visible = el => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width >= 4 && r.height >= 4 && rawVisibleRatio(el) >= 0.5 && s.display !== 'none' &&
      s.visibility !== 'hidden' && Number(s.opacity) > 0.05;
  };
  const overlay = document.querySelector('.modal, .sheet, .command-palette');
  const selector = [
    '.sidebar', '.topbar', '.searchbox', '.button', '.toolbar-strip', '.settings-nav',
    '.card', '.metric', '.setting-row', '.security-row', '.security-icon', '.switch',
    '.post', '.post-art', '.right-rail .card', '.news-lead', '.lead-image', '.news-card',
    '.news-image', '.segmented', '.editor-toolbar', '.outline', '.paper', '.comments',
    '.file-tree', '.code-panel', '.tabs', '.inspector', '.console', '.form-card', '.summary',
    '.field input', '.field select', '.field textarea', '.mobile-head', '.mobile-card',
    '.mobile-list', '.notice', '.payment-method', '.demo-card', '.receipt', '.chart-card',
    '.table-card', '.service-panel', '.region-panel', '.incident-card', '.service', '.modal',
    '.sheet', '.filter-section', '.chip', '.owner-row', '.table-shell', '.wide-table',
    '.notification', '.notification-icon', '.search-hero', '.big-search', '.results', '.result',
    '.result-icon', '.mail-app', '.mail-folders', '.mail-list', '.mail-row', '.mail-reader',
    '.reply-box', '.media-main', '.preview-frame', '.clip-list', '.clip', '.thumb', '.legal-toc',
    '.legal-doc', '.legal-note', '.soft-card', '.soft-field input', '.soft-button',
    '.view-toolbar', '.calendar-shell', '.weekdays', '.calendar-day', '.mobile-post',
    '.mobile-photo', '.story', '.tabbar', '.command-palette', '.command-input', '.command-row',
    '.command-footer', 'kbd', '.team-row', '.policy-panel'
  ].join(',');
  const seen = new Set();
  const rectangles = [];
  for (const el of document.querySelectorAll(selector)) {
    if (!visible(el)) continue;
    if (overlay && !overlay.contains(el)) continue;
    const b = box(el);
    if (b.width <= 0 || b.height <= 0 || b.width * b.height < 0.0004) continue;
    const key = `${b.x}:${b.y}:${b.width}:${b.height}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const tag = el.tagName.toLowerCase();
    const cls = [...el.classList].slice(0, 2).join('.');
    rectangles.push({
      id: `rect_${rectangles.length + 1}`,
      source: cls ? `${tag}.${cls}` : tag,
      bbox: b
    });
  }
  const groups = [...document.querySelectorAll('[data-gt-group]')].map((el, index) => {
    const members = [...el.querySelectorAll('[data-gt-group-member]')].filter(visible).map((member, memberIndex) => ({
      id: `member_${memberIndex + 1}`,
      text: (member.textContent || '').replace(/\s+/g, ' ').trim(),
      tag: member.tagName.toLowerCase(),
      class: [...member.classList].join(' '),
      bbox: box(member)
    }));
    if (members.length < 2) return null;
    const x = Math.min(...members.map(m => m.bbox.x));
    const y = Math.min(...members.map(m => m.bbox.y));
    const right = Math.max(...members.map(m => m.bbox.x + m.bbox.width));
    const bottom = Math.max(...members.map(m => m.bbox.y + m.bbox.height));
    return {
      id: el.getAttribute('data-gt-group') || `group_${index + 1}`,
      axis: el.getAttribute('data-gt-group-axis') || 'vertical',
      members,
      bbox: {x: round(x), y: round(y), width: round(right - x), height: round(bottom - y)}
    };
  }).filter(Boolean);
  return {vision_rectangles: rectangles, groups};
}
"""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clip_box(box: dict[str, float]) -> dict[str, float]:
    x0 = max(0.0, min(1.0, float(box["x"])))
    y0 = max(0.0, min(1.0, float(box["y"])))
    x1 = max(0.0, min(1.0, float(box["x"]) + float(box["width"])))
    y1 = max(0.0, min(1.0, float(box["y"]) + float(box["height"])))
    return {"x": x0, "y": y0, "width": max(0.0, x1 - x0), "height": max(0.0, y1 - y0)}


def visible_ratio(box: dict[str, float]) -> float:
    clipped = clip_box(box)
    area = float(box["width"]) * float(box["height"])
    return (clipped["width"] * clipped["height"]) / area if area > 0 else 0.0


def center_inside(box: dict[str, float], root: dict[str, float]) -> bool:
    cx = box["x"] + box["width"] / 2
    cy = box["y"] + box["height"] / 2
    return (
        root["x"] <= cx <= root["x"] + root["width"]
        and root["y"] <= cy <= root["y"] + root["height"]
    )


def iou(a: dict[str, float], b: dict[str, float]) -> float:
    x0, y0 = max(a["x"], b["x"]), max(a["y"], b["y"])
    x1 = min(a["x"] + a["width"], b["x"] + b["width"])
    y1 = min(a["y"] + a["height"], b["y"] + b["height"])
    intersection = max(0.0, x1 - x0) * max(0.0, y1 - y0)
    union = a["width"] * a["height"] + b["width"] * b["height"] - intersection
    return intersection / union if union else 0.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="Replace dataset-v2")
    args = parser.parse_args()
    if V2.exists() and not args.force:
        raise SystemExit("dataset-v2 already exists; refusing to overwrite")
    if V2.exists():
        shutil.rmtree(V2)
    (V2 / "images").mkdir(parents=True)
    (V2 / "ground_truth").mkdir(parents=True)

    v1_manifest = json.loads((V1 / "manifest.json").read_text())
    pages_by_id = {page["id"]: page for page in PAGES}
    rendered: dict[str, dict[str, Any]] = {}
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        for spec in v1_manifest["images"]:
            page_spec = pages_by_id[spec["id"]]
            page = browser.new_page(
                viewport={"width": page_spec["size"][0], "height": page_spec["size"][1]},
                device_scale_factor=1,
            )
            page.set_content(html_for(page_spec), wait_until="load")
            page.add_script_tag(content=INIT_SCRIPT)
            page.evaluate("() => window.__cloudbaseClean()")
            page.wait_for_timeout(40)
            rendered[spec["id"]] = page.evaluate(AUDIT_JS)
            page.close()
        browser.close()

    entries = []
    corrections = {}
    for spec in v1_manifest["images"]:
        image_id = spec["id"]
        src_image = V1 / spec["image"]
        dst_image = V2 / spec["image"]
        shutil.copyfile(src_image, dst_image)
        v1_gt = json.loads((V1 / spec["ground_truth"]).read_text())
        audit = rendered[image_id]

        root_id = OVERLAY_ROOTS.get(image_id)
        root = None
        if root_id:
            root = next(
                (container["bbox"] for container in v1_gt.get("containers", []) if container["id"] == root_id),
                None,
            )
            if root is None:
                raise RuntimeError(f"Missing overlay root {root_id} for {image_id}")

        excluded_text = []
        corrected_text = []
        for label in v1_gt["text"]:
            if visible_ratio(label["bbox"]) < 0.5:
                excluded_text.append({
                    **label,
                    "bbox": clip_box(label["bbox"]),
                    "exclusion_reason": "less_than_half_visible_in_capture_viewport",
                })
            elif root is not None and not center_inside(label["bbox"], root):
                excluded_text.append({
                    **label,
                    "bbox": clip_box(label["bbox"]),
                    "exclusion_reason": "dimmed_or_blurred_underlay_outside_active_overlay",
                })
            else:
                corrected_text.append({**label, "bbox": clip_box(label["bbox"])})

        semantic_containers = []
        excluded_containers = []
        for container in v1_gt.get("containers", []):
            if visible_ratio(container["bbox"]) < 0.5:
                excluded_containers.append({
                    **container,
                    "bbox": clip_box(container["bbox"]),
                    "exclusion_reason": "less_than_half_visible_in_capture_viewport",
                })
            elif root is not None and not center_inside(container["bbox"], root):
                excluded_containers.append({
                    **container,
                    "bbox": clip_box(container["bbox"]),
                    "exclusion_reason": "dimmed_or_blurred_underlay_outside_active_overlay",
                })
            else:
                semantic_containers.append({**container, "bbox": clip_box(container["bbox"])})

        repeated_groups = []
        for group in v1_gt.get("repeated_groups", []):
            candidates = [
                candidate
                for candidate in audit["groups"]
                if candidate["id"] == group["id"] and candidate["axis"] == group["axis"]
            ]
            if not candidates:
                continue
            best = max(candidates, key=lambda candidate: iou(candidate["bbox"], group["bbox"]))
            if root is not None and not center_inside(best["bbox"], root):
                continue
            enriched = {
                **group,
                "bbox": clip_box(best["bbox"]),
                "member_count": len(best["members"]),
                "members": best["members"],
            }
            repeated_groups.append(enriched)

        gt_v2 = {
            "schema": "ui_evidence_benchmark_ground_truth.v2",
            "id": image_id,
            "category": v1_gt["category"],
            "tags": v1_gt["tags"],
            "viewport": v1_gt["viewport"],
            "image": spec["image"],
            "mime_type": spec["mime_type"],
            "source_kind": spec["source_kind"],
            "crops": spec["crops"],
            "text": corrected_text,
            "excluded_text": excluded_text,
            "semantic_containers": semantic_containers,
            "excluded_semantic_containers": excluded_containers,
            "vision_rectangles": audit["vision_rectangles"],
            "repeated_groups": repeated_groups,
            "occlusion_correction": {
                "applied": root is not None or bool(excluded_text) or bool(excluded_containers),
                "active_overlay_container_id": root_id,
                "text_removed": len(excluded_text),
                "text_removed_outside_viewport": sum(
                    1 for item in excluded_text
                    if item["exclusion_reason"] == "less_than_half_visible_in_capture_viewport"
                ),
                "text_removed_under_overlay": sum(
                    1 for item in excluded_text
                    if item["exclusion_reason"] == "dimmed_or_blurred_underlay_outside_active_overlay"
                ),
                "semantic_containers_removed": len(excluded_containers),
                "semantic_containers_removed_outside_viewport": sum(
                    1 for item in excluded_containers
                    if item["exclusion_reason"] == "less_than_half_visible_in_capture_viewport"
                ),
                "semantic_containers_removed_under_overlay": sum(
                    1 for item in excluded_containers
                    if item["exclusion_reason"] == "dimmed_or_blurred_underlay_outside_active_overlay"
                ),
                "policy": "at_least_half_visible_and_active_overlay_center_inside",
            },
        }
        gt_path = V2 / spec["ground_truth"]
        gt_path.write_text(json.dumps(gt_v2, indent=2, ensure_ascii=False) + "\n")
        corrections[image_id] = gt_v2["occlusion_correction"]
        entries.append({
            "id": image_id,
            "image": spec["image"],
            "ground_truth": spec["ground_truth"],
            "mime_type": spec["mime_type"],
            "source_kind": spec["source_kind"],
            "source_sha256": sha256(dst_image),
            "ground_truth_sha256": sha256(gt_path),
            "crops": spec["crops"],
        })

    parts = [f'{item["id"]}:{item["source_sha256"]}:{item["ground_truth_sha256"]}' for item in entries]
    aggregate = hashlib.sha256("\n".join(parts).encode()).hexdigest()
    manifest = {
        "schema_version": "ui_evidence_benchmark_dataset.v2",
        "name": "P1-C UI Evidence Quality Benchmark — calibrated GT",
        "dataset_version": "2.0.0",
        "created_at": "2026-11-12",
        "immutable": True,
        "source_dataset_sha256": v1_manifest["dataset_sha256"],
        "image_count": len(entries),
        "dataset_sha256": aggregate,
        "images": entries,
        "occlusion_corrections": corrections,
    }
    (V2 / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"dataset-v2: {len(entries)} images, sha256={aggregate}")
    for image_id, correction in corrections.items():
        if correction["applied"]:
            print(f"  {image_id}: removed text={correction['text_removed']} semantic_containers={correction['semantic_containers_removed']}")


if __name__ == "__main__":
    main()
