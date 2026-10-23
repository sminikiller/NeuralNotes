"""Verify the previous binary's real SwiftData row and transcript after app replacement."""
import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("container", type=Path)
parser.add_argument("--baseline", type=Path)
parser.add_argument("--output", required=True, type=Path)
args = parser.parse_args()
root = args.container / "Library/Application Support/NeuralNotes-UITests"
store = root / "Library.store"
with sqlite3.connect(f"file:{store}?mode=ro", uri=True) as database:
    tables = [row[0] for row in database.execute("select name from sqlite_master where type='table'")]
    rows = []
    for table in tables:
        quoted = '"' + table.replace('"', '""') + '"'
        columns = {row[1].upper() for row in database.execute("pragma table_info(" + quoted + ")")}
        if {"ZTITLE", "ZDOCUMENTID"} <= columns:
            rows += list(database.execute("select ZTITLE from " + quoted + " where ZTITLE=?", ("Audio UI test",)))
    if len(rows) != 1:
        raise SystemExit("Previous SwiftData notebook row missing or duplicated")
files = {}
for file in sorted((root / "Notebooks").glob("*.nnbook/*.json")):
    files[str(file.relative_to(root))] = hashlib.sha256(file.read_bytes()).hexdigest()
catalogs = list((root / "Notebooks").glob("*.nnbook/catalog.json"))
if len(catalogs) != 1 or "Testo da esportare" not in catalogs[0].read_text():
    raise SystemExit("Previous transcript not present")
if not any(name.endswith("manifest.json") for name in files):
    raise SystemExit("Previous native manifest missing")
report = {"notebooks": len(rows), "files": files}
if args.baseline and report != json.loads(args.baseline.read_text()):
    raise SystemExit("Upgrade altered the seeded manifest/catalog or notebook index")
args.output.write_text(json.dumps(report, indent=2) + "\n")
print("PASS: previous SwiftData notebook, native manifest and transcript retained")
