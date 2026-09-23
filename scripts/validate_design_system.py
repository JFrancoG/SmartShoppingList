#!/usr/bin/env python3
"""Validate the opaque sRGB pairs specified in docs/design-system.md.

No third-party dependencies. Default: read-only validation, including report drift.
--write: regenerate the Markdown report (also reports and fails invalid pairs).
"""

import argparse
import hashlib
import re
import sys
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/design-system.md"
REPORT = ROOT / "docs/validation/design-system-contrast.md"
PREVIEW = ROOT / "docs/assets/design-system-preview.svg"
MODES = ("Light", "Dark", "HC Light", "HC Dark")


def table_rows(document, section):
    start = f"<!-- {section}:start -->"
    end = f"<!-- {section}:end -->"
    if document.count(start) != 1 or document.count(end) != 1:
        raise ValueError(f"Expected one {section} table")
    block = document.split(start, 1)[1].split(end, 1)[0].strip()
    lines = block.splitlines()
    if len(lines) < 3 or not all(line.startswith("|") and line.endswith("|") for line in lines):
        raise ValueError(f"Malformed {section} table")
    return [[cell.strip() for cell in line.strip("|").split("|")] for line in lines[2:]]


def luminance(hex_color):
    rgb = [int(hex_color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in rgb]
    return sum(value * weight for value, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(first, second):
    low, high = sorted((luminance(first), luminance(second)))
    return (high + 0.05) / (low + 0.05)


def evaluate(document):
    palette_rows = table_rows(document, "palette")
    pair_rows = table_rows(document, "pairs")
    palette = {}
    for row in palette_rows:
        if len(row) != 5 or not re.fullmatch(r"[a-z]+(?:-[a-z]+)*", row[0]):
            raise ValueError(f"Malformed palette row: {row}")
        if row[0] in palette or not all(re.fullmatch(r"#[0-9A-F]{6}", value) for value in row[1:]):
            raise ValueError(f"Duplicate token or invalid sRGB value: {row}")
        palette[row[0]] = row[1:]
    pairs = []
    seen = set()
    for row in pair_rows:
        if len(row) != 3 or row[2] not in ("text", "ui", "decorative"):
            raise ValueError(f"Malformed pair row: {row}")
        foregrounds, backgrounds = ([value.strip() for value in cell.split(",")] for cell in row[:2])
        for foreground in foregrounds:
            for background in backgrounds:
                if foreground not in palette or background not in palette:
                    raise ValueError(f"Unknown pair token: {foreground}/{background}")
                key = (foreground, background, row[2])
                if key in seen:
                    raise ValueError(f"Duplicate pair: {key}")
                seen.add(key)
                pairs.append(key)
    results = []
    failures = []
    for foreground, background, kind in pairs:
        ratios = []
        for index, mode in enumerate(MODES):
            ratio = contrast(palette[foreground][index], palette[background][index])
            threshold = (7 if index >= 2 else 4.5) if kind == "text" else 3 if kind == "ui" else None
            passed = threshold is None or ratio >= threshold
            if not passed:
                failures.append(f"{mode}: {foreground}/{background} ({kind}) {ratio:.8f} < {threshold}")
            ratios.append((ratio, passed))
        results.append((foreground, background, kind, ratios))
    canonical = repr((palette_rows, pair_rows)).encode("utf-8")
    return results, failures, hashlib.sha256(canonical).hexdigest()


def render(results, failures, fingerprint):
    essential = sum(row[2] != "decorative" for row in results) * len(MODES)
    decorative = sum(row[2] == "decorative" for row in results) * len(MODES)
    lines = [
        "# Validación de contraste del sistema de diseño", "",
        "Informe generado desde las tablas de [tokens y pares](../design-system.md). No editar a mano.", "",
        f"Resultado: **{'FALLO' if failures else 'PASA'}** · {essential - len(failures)}/{essential} comprobaciones con umbral; "
        f"{decorative} mediciones decorativas sin umbral.", "",
        f"Huella SHA-256 de las tablas: `{fingerprint}`.", "",
        "## Método y alcance", "",
        "Colores opacos sRGB de 8 bits. Canal c = byte/255; linealización: c/12,92 si c ≤ 0,04045, "
        "en otro caso ((c + 0,055)/1,055)^2,4. L = 0,2126 R + 0,7152 G + 0,0722 B. "
        "Ratio = (L mayor + 0,05)/(L menor + 0,05). Se compara sin redondear; la tabla muestra dos decimales.", "",
        "`text`: objetivo propio 4,5:1 Light/Dark y 7:1 HC, incluso si el texto es grande. "
        "`ui`: 3:1 en los cuatro modos. `decorative`: no se usa para identificar un control o estado. "
        "La fórmula y criterios proceden de [WCAG 2.2](https://www.w3.org/TR/WCAG22/#dfn-relative-luminance); "
        "el umbral HC es una decisión del proyecto.", "",
        "Sólo se acreditan estos pares nominales. No se ha ejecutado la app ni medido materiales, "
        "antialiasing, assets, controles nativos, Dynamic Type, foco o VoiceOver. "
        "No equivale a conformidad AA/AAA del producto.", "",
        "## Mínimos entre los pares exigidos", "",
        "| Modo | Texto mínimo | Par de texto limitante | UI mínimo |",
        "|---|---|---|---|",
    ]
    for index, mode in enumerate(MODES):
        text_min = min((row[3][index][0], row[0], row[1]) for row in results if row[2] == "text")
        ui_min = min(row[3][index][0] for row in results if row[2] == "ui")
        lines.append(f"| {mode} | {text_min[0]:.2f}:1 | {text_min[1]} / {text_min[2]} | {ui_min:.2f}:1 |")
    lines += ["", "## Todos los pares", "",
              "Cada celda sin marca de fallo supera su umbral; en filas decorativas el resultado es N/A.", "",
              "| Foreground | Background | Clase | Light | Dark | HC Light | HC Dark |",
              "|---|---|---|---|---|---|---|"]
    for foreground, background, kind, ratios in results:
        cells = [f"{ratio:.2f}:1" + (" N/A" if kind == "decorative" else " FALLO" if not passed else "")
                 for ratio, passed in ratios]
        lines.append("| " + " | ".join([foreground, background, kind, *cells]) + " |")
    if failures:
        lines += ["", "## Fallos", "", *[f"- {failure}" for failure in failures]]
    lines += ["", "## Reproducción", "", "Desde la raíz del repositorio, Python 3 sin paquetes externos:", "",
              "```bash", "python3 scripts/validate_design_system.py", "```", "",
              "Tras editar tokens o pares:", "", "```bash", "python3 scripts/validate_design_system.py --write", "```", "",
              "La ejecución normal falla si algún par no pasa o el informe no coincide con las tablas. "
              "La opción `--write` regenera el informe y también devuelve error si hay pares fallidos. "
              "Las comprobaciones de interfaz se conservan en el [protocolo de accesibilidad](../accessibility.md).", ""]
    return "\n".join(lines)


def render_preview(document):
    """A diagram of approved opaque pairs, not a simulation of native controls."""
    palette = {row[0]: row[1:] for row in table_rows(document, "palette")}
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="1560" height="880" viewBox="0 0 1560 880" role="img" aria-labelledby="title desc">',
        '<title id="title">SmartShoppingList: cuatro apariencias</title>',
        '<desc id="desc">La misma lista de compra en claro, oscuro y ambas variantes con contraste aumentado. Dos productos seleccionados pendientes de confirmar. Diagrama de colores opacos, no captura de la app.</desc>',
        '<rect width="1560" height="880" fill="#F7FAF7"/>',
    ]

    def rect(x, y, width, height, fill, stroke="none", radius=12):
        parts.append(f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')

    def label(x, y, value, color, size=18, weight=400):
        parts.append(f'<text x="{x}" y="{y}" fill="{color}" font-family="-apple-system, BlinkMacSystemFont, Arial, sans-serif" font-size="{size}" font-weight="{weight}">{escape(value)}</text>')

    label(28, 43, "SmartShoppingList · cuatro apariencias", "#14291C", 30, 700)
    label(28, 72, "Referencia de color · superficies opacas · no es una captura ni una auditoría de la app", "#405746", 18)
    for index, mode in enumerate(MODES):
        p = {key: values[index] for key, values in palette.items()}
        x = 28 + index * 383
        rect(x, 100, 355, 746, p["canvas"], p["border"], 20)
        label(x + 20, 136, mode, p["text-secondary"], 17, 600)
        label(x + 20, 181, "Comprar", p["text-primary"], 30, 700)
        label(x + 20, 215, "Mercadona", p["text-primary"], 22, 600)
        label(x + 20, 244, "3 pendientes · 2 seleccionados", p["text-secondary"], 17)
        for row, (name, detail, selected) in enumerate([
            ("Tomates", "1 kg · Seleccionado", True),
            ("Pan integral", "1 unidad · Seleccionado", True),
            ("Yogures", "Sin seleccionar", False),
        ]):
            y = 268 + row * 90
            background = p["accent-soft"] if selected else p["surface"]
            rect(x + 16, y, 323, 78, background)
            rect(x + 30, y + 23, 30, 30, p["accent"] if selected else background, p["accent"] if selected else p["border"], 7)
            if selected:
                parts.append(f'<path d="M {x + 37} {y + 38} l 6 6 l 11 -14" fill="none" stroke="{p["on-accent"]}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>')
            label(x + 76, y + 30, name, p["text-primary"], 20, 600)
            label(x + 76, y + 57, detail, p["accent"] if selected else p["text-secondary"], 16)
        label(x + 20, 565, "Pendientes de confirmar", p["text-secondary"], 17)
        rect(x + 16, 585, 323, 58, p["accent"], radius=14)
        label(x + 35, 621, "Finalizar compra · 2 productos", p["on-accent"], 18, 600)
        rect(x + 16, 661, 323, 62, p["warning-soft"])
        label(x + 30, 686, "!  Sin conexión", p["warning"], 17, 600)
        label(x + 30, 710, "La selección se conserva", p["text-primary"], 16)
        label(x + 20, 754, "Marca y estados", p["text-secondary"], 16)
        for swatch, token in enumerate(("accent", "brand-yellow", "success", "danger", "info")):
            rect(x + 20 + swatch * 65, 767, 54, 22, p[token], radius=5)
        minimum = min(contrast(p[fg], p[bg]) for fg in ("text-primary", "text-secondary", "text-tertiary") for bg in ("canvas", "surface", "surface-muted"))
        label(x + 20, 823, f"Texto neutro mínimo: {minimum:.2f}:1", p["text-secondary"], 16)
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Regenerate the Markdown report and SVG reference")
    args = parser.parse_args()
    try:
        document = SOURCE.read_text(encoding="utf-8")
        results, failures, fingerprint = evaluate(document)
        report = render(results, failures, fingerprint)
        for path, content in ((REPORT, report), (PREVIEW, render_preview(document))):
            if args.write:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            elif not path.exists() or path.read_text(encoding="utf-8") != content:
                failures.append(f"{path.name} missing or stale; run with --write and review the diff")
        if failures:
            print("\n".join(failures), file=sys.stderr)
            return 1
        print(f"PASS: {len(results)} pairs × 4 modes; report and SVG match canonical tables")
        return 0
    except (ValueError, OSError) as error:
        print(f"Validation error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
