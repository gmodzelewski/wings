"""Generate Red Hat-styled diagram PNGs for the WINGS3 MLflow on RHOAI deck.

Run: python scripts/wings3_diagrams.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WINGS3_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = WINGS3_ROOT / "walkthrough" / "assets" / "diagrams"

RH_RED = (238, 0, 0)
RH_DARK = (17, 17, 17)
RH_GREY = (76, 76, 76)
RH_LIGHT = (245, 245, 245)
RH_MID = (180, 180, 180)
RH_WHITE = (255, 255, 255)
RH_BLUE = (0, 102, 180)
RH_GREEN = (0, 140, 80)
RH_AMBER = (220, 140, 0)
RH_RED_SOFT = (255, 230, 230)
RH_BLUE_SOFT = (226, 236, 245)
RH_GREEN_SOFT = (226, 240, 230)
RH_AMBER_SOFT = (255, 242, 220)

W, H = 1500, 660


def _font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()


def _wrap(text: str, font: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    words = text.split()
    lines, cur = [], ""
    for w in words:
        test = (cur + " " + w).strip()
        if font.getlength(test) <= max_w:
            cur = test
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines or [""]


def _rounded_rect(draw, box, fill, outline=None, width=2, radius=14):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def _centered_text(draw, text, center, font, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((center[0] - tw // 2, center[1] - th // 2), text, font=font, fill=fill)


def _box(draw, box, title, body_lines, title_font, body_font, fill, accent, body_fill=RH_DARK):
    _rounded_rect(draw, box, fill, outline=accent, width=3)
    x0, y0, x1, y1 = box
    pad = 16
    cy = y0 + pad
    for line in _wrap(title, title_font, x1 - x0 - 2 * pad):
        draw.text((x0 + pad, cy), line, font=title_font, fill=accent)
        cy += int(title_font.size * 1.15)
    cy += 4
    for line in body_lines:
        for wl in _wrap(line, body_font, x1 - x0 - 2 * pad):
            draw.text((x0 + pad, cy), wl, font=body_font, fill=body_fill)
            cy += int(body_font.size * 1.1)


def _arrow(draw, start, end, fill=RH_RED, width=4, head=14):
    draw.line([start, end], fill=fill, width=width)
    ang = math.atan2(end[1] - start[1], end[0] - start[0])
    p1 = (end[0] - head * math.cos(ang - 0.4), end[1] - head * math.sin(ang - 0.4))
    p2 = (end[0] - head * math.cos(ang + 0.4), end[1] - head * math.sin(ang + 0.4))
    draw.polygon([end, p1, p2], fill=fill)


def _canvas(title: str | None = None) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", (W, H), RH_LIGHT)
    d = ImageDraw.Draw(img)
    if title:
        _centered_text(d, title, (W // 2, 36), _font(24, True), RH_DARK)
    return img, d


def _save(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    img.save(path, "PNG")
    return path


def diagram_why_native() -> Path:
    img, d = _canvas("Why MLflow on OpenShift AI")
    tf, bf = _font(22, True), _font(16)
    boxes = [
        ("Workspace = project", "RBAC is the OpenShift namespace.\nMLFLOW_WORKSPACE = my-first-model.", RH_RED, RH_RED_SOFT),
        ("Injected tracking URI", "Workbench annotation injects URI\nand Kubernetes auth. No laptop token.", RH_BLUE, RH_BLUE_SOFT),
        ("Not an external tracer", "Same gateway, same project, same\nidentity. Native, not a sidecar SaaS.", RH_GREEN, RH_GREEN_SOFT),
    ]
    cw = (W - 100) // 3
    for i, (title, body, accent, fill) in enumerate(boxes):
        x0 = 30 + i * (cw + 20)
        _box(d, (x0, 100, x0 + cw, H - 70), title, body.split("\n"), tf, bf, fill, accent)
    return _save(img, "why-native.png")


def diagram_rbac_experiment() -> Path:
    img, d = _canvas("Project · Workspace · Experiment")
    tf, bf = _font(20, True), _font(16)
    _box(
        d, (40, 100, 480, 300),
        "Project",
        ["OpenShift namespace", "my-first-model", "dashboard + RBAC"],
        tf, bf, RH_WHITE, RH_RED,
    )
    _box(
        d, (520, 100, 980, 300),
        "Workspace",
        ["MLflow name for that project", "MLFLOW_WORKSPACE", "the RBAC boundary"],
        tf, bf, RH_WHITE, RH_BLUE,
    )
    _box(
        d, (1020, 100, 1460, 300),
        "Experiment",
        ["Named bucket inside workspace", "wings3-agent-tracing", "wings3-agent-eval"],
        tf, bf, RH_WHITE, RH_GREEN,
    )
    _arrow(d, (480, 200), (520, 200), fill=RH_RED, width=4)
    _arrow(d, (980, 200), (1020, 200), fill=RH_BLUE, width=4)
    _rounded_rect(d, (120, 360, W - 120, H - 50), fill=RH_WHITE, outline=RH_GREY, width=2)
    _centered_text(
        d,
        "One project. One workspace. Two experiments. Laptop token is rehearsal-only.",
        (W // 2, 430),
        _font(18, True),
        RH_DARK,
    )
    _centered_text(
        d,
        "Workbench injects MLFLOW_TRACKING_URI — you still set MLFLOW_WORKSPACE.",
        (W // 2, 480),
        bf,
        RH_GREY,
    )
    return _save(img, "rbac-experiment.png")


def diagram_architecture_rhoai_mlflow() -> Path:
    img, d = _canvas("RHOAI + MLflow")
    tf, bf = _font(20, True), _font(15)
    layers = [
        ("OpenShift AI gateway", "/mlflow — Traces, Details & Timeline, Evaluation", RH_RED),
        ("MLflow operator + CR", "Tracking server in redhat-ods-applications", RH_BLUE),
        ("Workbench wings3-demo", "Injected URI · named SA · Jupyter notebooks", RH_GREEN),
        ("KServe vLLM", "llama-32-3b-instruct · one tool call per turn", RH_AMBER),
    ]
    y = 90
    for title, sub, color in layers:
        _rounded_rect(d, (160, y, W - 160, y + 100), fill=RH_WHITE, outline=color, width=3)
        d.text((190, y + 22), title, font=tf, fill=color)
        d.text((190, y + 58), sub, font=bf, fill=RH_DARK)
        if y < 90 + 110 * (len(layers) - 1):
            _arrow(d, (W // 2, y + 100), (W // 2, y + 110), fill=RH_MID, width=3)
        y += 110
    return _save(img, "architecture-rhoai-mlflow.png")


def diagram_install_three_steps() -> Path:
    img, d = _canvas("Act 1 — Verify, do not wait-for-Ready")
    tf, bf = _font(20, True), _font(16)
    steps = [
        ("1", "Operator Managed", "Pre-stage. Live: oc get DSC.", RH_RED),
        ("2", "MLflow CR + pod", "Pre-apply. Live: oc get only.", RH_BLUE),
        ("3", "Standalone /mlflow", "Workspace dropdown → my-first-model.", RH_GREEN),
    ]
    cw = (W - 100) // 3
    for i, (num, title, body, color) in enumerate(steps):
        x0 = 30 + i * (cw + 20)
        d.ellipse((x0 + cw // 2 - 28, 100, x0 + cw // 2 + 28, 156), fill=color)
        _centered_text(d, num, (x0 + cw // 2, 128), _font(24, True), RH_WHITE)
        _box(d, (x0, 180, x0 + cw, H - 60), title, [body], tf, bf, RH_WHITE, color)
        if i < 2:
            _arrow(d, (x0 + cw + 2, H // 2), (x0 + cw + 18, H // 2), fill=color, width=5)
    return _save(img, "install-three-steps.png")


def diagram_autolog_one_liner() -> Path:
    img, d = _canvas("One line → full span tree")
    bf = _font(17)
    _rounded_rect(d, (120, 110, W - 120, 210), fill=RH_WHITE, outline=RH_RED, width=4)
    _centered_text(d, "mlflow.langchain.autolog()", (W // 2, 160), _font(34, True), RH_RED)
    _arrow(d, (W // 2, 215), (W // 2, 270), fill=RH_RED, width=5, head=18)
    spans = ["LangGraph", "ChatOpenAI", "calculator", "ChatOpenAI"]
    sw = (W - 160) // len(spans)
    colors = [RH_BLUE, RH_GREEN, RH_AMBER, RH_GREEN]
    for i, span in enumerate(spans):
        x0 = 80 + i * sw
        _rounded_rect(d, (x0 + 8, 285, x0 + sw - 8, 385), fill=RH_WHITE, outline=colors[i], width=3)
        _centered_text(d, span, (x0 + sw // 2, 335), bf, colors[i])
    _centered_text(d, "Without autolog you miss the calculator span.", (W // 2, 470), _font(20, True), RH_DARK)
    _centered_text(d, "SHOW that line in 01_agent_tracing_autolog.ipynb before you run the query.", (W // 2, 520), bf, RH_GREY)
    return _save(img, "autolog-one-liner.png")


def diagram_contrast_manual_autolog() -> Path:
    img, d = _canvas("Manual spans vs autolog")
    tf, bf = _font(22, True), _font(17)
    _box(
        d, (60, 100, 720, H - 70),
        "Manual",
        ["Custom span per node", "Easy to miss the tool call", "High maintenance"],
        tf, bf, RH_RED_SOFT, RH_RED,
    )
    _box(
        d, (780, 100, 1440, H - 70),
        "Autolog",
        ["mlflow.langchain.autolog()", "LangGraph · LLM · calculator", "One line, before the agent runs"],
        tf, bf, RH_GREEN_SOFT, RH_GREEN,
    )
    return _save(img, "contrast-manual-autolog.png")


def diagram_eval_improvement_loop() -> Path:
    img, d = _canvas("Prompt change · substring scorer · n=4")
    tf, bf = _font(20, True), _font(16)
    loop = [
        ("v1 prompt", "You are a helper. Answer briefly.", RH_RED),
        ("Score", "contains_expected substring", RH_BLUE),
        ("v2 prompt", "Always use calculator. State the number.", RH_GREEN),
        ("Direction", "25% → 50% rehearsal. Not an SLO.", RH_AMBER),
    ]
    cx, cy, r = W // 2, H // 2 + 20, 200
    for i, (title, sub, color) in enumerate(loop):
        ang = -math.pi / 2 + i * (2 * math.pi / len(loop))
        x = cx + int(r * math.cos(ang))
        y = cy + int(r * math.sin(ang))
        _box(d, (x - 170, y - 55, x + 170, y + 55), title, [sub], tf, bf, RH_WHITE, color)
    d.ellipse((cx - 48, cy - 48, cx + 48, cy + 48), outline=RH_RED, width=3)
    _centered_text(d, "n=4", (cx, cy), _font(20, True), RH_RED)
    return _save(img, "eval-improvement-loop.png")


def diagram_personas_three_hats() -> Path:
    img, d = _canvas("Three hats, one thread")
    tf, bf = _font(20, True), _font(16)
    hats = [
        ("Platform", "Act 1 — oc get + /mlflow\nYou can see the agent", RH_RED),
        ("Developer", "Act 2 — SHOW autolog\nYou can debug it", RH_BLUE),
        ("Data scientist", "Act 3 — SHOW evaluate\nYou can prove a prompt moved", RH_GREEN),
    ]
    cw = (W - 80) // 3
    for i, (role, tasks, color) in enumerate(hats):
        x0 = 30 + i * (cw + 10)
        d.ellipse((x0 + cw // 2 - 36, 90, x0 + cw // 2 + 36, 162), fill=color)
        _centered_text(d, str(i + 1), (x0 + cw // 2, 126), _font(26, True), RH_WHITE)
        _box(d, (x0, 190, x0 + cw, H - 50), role, tasks.split("\n"), tf, bf, RH_WHITE, color)
    return _save(img, "personas-three-hats.png")


def diagram_agenda_one_hour() -> Path:
    img, d = _canvas("Sixty minutes — three PAUSE marks")
    tf, bf = _font(20, True), _font(16)
    blocks = [
        ("0:00", "Intro + why native + hats", "6 min", RH_DARK),
        ("0:06", "Act 1 — verify  ·  PAUSE /mlflow", "8 min", RH_RED),
        ("0:14", "Act 2 — autolog  ·  PAUSE notebook", "22 min", RH_BLUE),
        ("0:36", "Act 3 — eval  ·  PAUSE notebook", "15 min", RH_GREEN),
        ("0:51", "Production CR + Q&A", "9 min", RH_AMBER),
    ]
    y = 90
    for start, label, mins, color in blocks:
        _rounded_rect(d, (80, y, 1420, y + 90), fill=RH_WHITE, outline=color, width=3)
        d.text((110, y + 28), start, font=tf, fill=color)
        d.text((280, y + 28), label, font=tf, fill=RH_DARK)
        d.text((1220, y + 28), mins, font=bf, fill=RH_GREY)
        y += 100
    return _save(img, "agenda-one-hour.png")


def diagram_production_cr_fields() -> Path:
    img, d = _canvas("Dev CR vs production CR")
    tf, bf = _font(20, True), _font(16)
    _box(
        d, (50, 100, 720, H - 80),
        "Demo (mlflow-dev.yaml)",
        ["backendStoreUri: sqlite", "artifactsDestination: file://", "replicas: 1 · PVC"],
        tf, bf, RH_WHITE, RH_GREY,
    )
    _box(
        d, (780, 100, 1450, H - 80),
        "Prod (mlflow-prod.example.yaml)",
        ["backendStoreUriFrom: Postgres secret", "artifactsDestination: s3://…", "replicas > 1 needs remote storage"],
        tf, bf, RH_GREEN_SOFT, RH_GREEN,
    )
    return _save(img, "production-cr-fields.png")


def main() -> None:
    generators = [
        diagram_why_native,
        diagram_rbac_experiment,
        diagram_architecture_rhoai_mlflow,
        diagram_install_three_steps,
        diagram_autolog_one_liner,
        diagram_contrast_manual_autolog,
        diagram_eval_improvement_loop,
        diagram_personas_three_hats,
        diagram_agenda_one_hour,
        diagram_production_cr_fields,
    ]
    paths = [fn() for fn in generators]
    print(f"Generated {len(paths)} diagrams in {OUT_DIR}:")
    for p in paths:
        print(f"  {p}")


if __name__ == "__main__":
    main()
