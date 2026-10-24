"""Export the app's canonical Italian tutorials as a readable delivery manual."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "NeuralNotes/Core/Domain/FeatureGuide.swift").read_text(encoding="utf-8")
quoted = r'"(?:[^"\\]|\\.)*"'
pattern = re.compile(
    rf'\.init\("([^"]+)", \.(\w+), ({quoted}), ({quoted}), ({quoted}), '
    rf'\[\s*((?:{quoted}\s*,?\s*)+)\]'
)
categories = dict(re.findall(r'(\w+) = "([^"]+)"', source))
rows = list(pattern.finditer(source))
if len(rows) != source.count("        .init("):
    raise SystemExit("Tutorial parser did not cover the complete catalog")
lines = ["# Guida alle funzioni di NeuralNotes", "",
         "Generata dal catalogo dei tutorial incluso nell’app. La guida interattiva è in Libreria → Guida rapida.", "",
         "Le istruzioni dei servizi remoti indicano i requisiti: non significano che il backend pubblico o iCloud firmato siano già attivi.", ""]
previous = None
for row in rows:
    identity, category, title, icon, summary, steps = row.groups()
    if category != previous:
        lines += ["## " + categories[category], ""]
        previous = category
    lines += ["### " + json.loads(title), "", json.loads(summary), ""]
    for index, step in enumerate(re.findall(quoted, steps), 1):
        lines += [f"{index}. {json.loads(step)}"]
    lines.append("")
destination = ROOT / "docs/GUIDA_FUNZIONI.md"
destination.write_text("\n".join(lines), encoding="utf-8")
print(f"Exported {len(rows)} tutorials: {destination}")
