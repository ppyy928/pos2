"""Audit QML string keys against the merged catalogue.

Collects every literal key passed to Strings.t / Strings.tf / Strings.t2 in the
QML tree, merges pos's _STRINGS with pos2's EXTRA (the same two tables
app.bridge.i18n._build flattens), and reports:

  MISSING   key is in no table -> the English fallback shows in every language
  NO_AR     key exists but has no "ar" entry -> English shows in Arabic
  NO_FR     key exists but has no "fr" entry -> English shows in French
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / "qml"
sys.path.insert(0, str(ROOT))

from app.bridge.i18n import EXTRA
from app.bridge.legacy import catalogue

TABLE = catalogue()
MERGED: dict[str, dict] = {}
MERGED.update(TABLE)
MERGED.update(EXTRA)

CALL = re.compile(r'Strings\.t(?:f|2)?\(\s*"([^"]+)"')
used: dict[str, list[str]] = {}
for path in sorted(QML.rglob("*.qml")):
    text = path.read_text(encoding="utf-8")
    for key in CALL.findall(text):
        used.setdefault(key, []).append(path.name)

# The fallback English text of each key, quoted straight from the call site, for
# the keys the catalogue is missing: that text is what a translator translates.
FALLBACK = re.compile(
    r'Strings\.t(?:f|2)?\(\s*"(?P<key>[^"]+)"\s*,\s*(?P<rest>.*?)\n', re.DOTALL
)
fallbacks: dict[str, str] = {}
for path in sorted(QML.rglob("*.qml")):
    text = path.read_text(encoding="utf-8")
    for m in FALLBACK.finditer(text):
        rest = " ".join(m.group("rest").split())
        fallbacks.setdefault(m.group("key"), rest)

missing = sorted(k for k in used if k not in MERGED)
no_ar = sorted(k for k in used if k in MERGED and not MERGED[k].get("ar"))
no_fr = sorted(k for k in used if k in MERGED and not MERGED[k].get("fr"))

print(f"keys used in QML : {len(used)}")
print(f"catalogue entries: {len(MERGED)}")
print(f"\nMISSING ({len(missing)}) — English fallback in every language:")
for key in missing:
    print(f"  {key}\n      {fallbacks.get(key, '?')}")
print(f"\nNO_AR ({len(no_ar)}) — English shows in Arabic:")
for key in no_ar:
    print(f"  {key}")
print(f"\nNO_FR ({len(no_fr)}) — English shows in French:")
for key in no_fr:
    print(f"  {key}")
