"""Export the app's canonical Italian tutorials as a readable delivery manual."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "NeuralNotes/Core/Domain/FeatureGuide.swift").read_text(encoding="utf-8")
practice = (ROOT / "NeuralNotes/Core/Domain/GuidePractice.swift").read_text(encoding="utf-8")
quoted = r'"(?:[^"\\]|\\.)*"'
pattern = re.compile(
    rf'\.init\("([^"]+)", \.(\w+), ({quoted}), ({quoted}), ({quoted}), '
    rf'\[\s*((?:{quoted}\s*,?\s*)+)\]'
)
categories = dict(re.findall(r'(\w+) = "([^"]+)"', source))
rows = list(pattern.finditer(source))
if len(rows) != source.count("        .init("):
    raise SystemExit("Tutorial parser did not cover the complete catalog")
exercise = rf'\.init\(\s*({quoted}),\s*({quoted})\s*\),?'
exercise_rows = re.findall(rf'^        "([\w-]+)": \[\s*((?:{exercise}\s*)+)\]', practice, re.MULTILINE)
exercises = {identity: re.findall(exercise, body) for identity, body, _, _ in exercise_rows}
if (
    len(exercise_rows) != len(exercises)
    or set(exercises) != {row[1] for row in rows}
    or sum(map(len, exercises.values())) != practice.count("            .init(")
):
    raise SystemExit("Every lesson needs its own complete exercise set")

lines = ["# Guida completa di NeuralNotes", "",
         "Apri **Guida completa** dalla libreria oppure da **⋯ → Guida completa** mentre sei nel quaderno. "
         "Puoi chiuderla per fare una prova e ritrovare la lezione con **Riprendi il tutorial**.", "",
         "Crea un quaderno di esercitazione, aggiungi qualche pagina vuota e salva in File un piccolo PDF con testo selezionabile. "
         "Per le prove di audio usa una breve registrazione senza dati personali. Alcuni esercizi richiedono Apple Pencil, tastiera fisica, microfono o un servizio già configurato.", "",
         "Ogni lezione include una prova pratica con un risultato atteso. Se il risultato coincide, spunta **Esito verificato** nell’app. "
         "Completate tutte le prove, usa **Segna come completato**. Puoi fare le lezioni in qualsiasi ordine.", "",
         "Per i gesti nella casella attiva consulta anche la [guida Apple a Scrivi a mano](https://support.apple.com/it-it/guide/ipad/ipad355ab2a7/ipados).", "",
         "## Indice", ""]
for category, label in categories.items():
    if any(row[2] == category for row in rows):
        anchor = label.lower().replace(" ", "-")
        lines.append(f"- [{label}](#{anchor})")
lines.append("")

for category, label in categories.items():
    lessons = [row for row in rows if row[2] == category]
    if not lessons:
        continue
    lines += ["## " + label, ""]
    for row in lessons:
        identity, _, title, _, summary, steps = row.groups()
        lines += ["### " + json.loads(title), "", json.loads(summary), ""]
        for index, step in enumerate(re.findall(quoted, steps), 1):
            lines += [f"{index}. {json.loads(step)}"]
        lines += ["", "#### Esercizi", ""]
        for task, expected in exercises[identity]:
            lines += [f"- [ ] {json.loads(task)}", f"  **Risultato atteso** — {json.loads(expected)}", ""]
destination = ROOT / "docs/GUIDA_FUNZIONI.md"
existing = destination.read_text(encoding="utf-8") if destination.exists() else ""
marker = "## Collaudo dei PDF"
appendix = "\n" + existing[existing.index(marker):] if marker in existing else ""
destination.write_text("\n".join(lines) + appendix, encoding="utf-8")
print(f"Exported {len(rows)} tutorials and {sum(map(len, exercises.values()))} exercises: {destination}")
