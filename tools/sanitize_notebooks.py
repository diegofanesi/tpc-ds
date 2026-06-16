#!/usr/bin/env python3
"""Sanitize Databricks-exported .ipynb notebooks before committing.

Removes environment-specific / secret state that Databricks persists in the
notebook JSON when you export a notebook you have run:

  * cell outputs and execution counts
  * Databricks widget ``currentValue`` state (reset to the widget's
    declared ``defaultValue`` so the published template ships neutral)

It also fails loudly if a credential-shaped string (Databricks PAT, private
key) is found anywhere in the file, so a real secret can never slip through.

Usage:
    python tools/sanitize_notebooks.py [FILE.ipynb ...]   # sanitize given files
    python tools/sanitize_notebooks.py                    # sanitize every *.ipynb

Exit code 1 if a credential-shaped string survives (used by the pre-commit hook).
"""
from __future__ import annotations

import glob
import json
import re
import sys

DBX_META_KEY = "application/vnd.databricks.v1+notebook"

# Patterns that must NEVER appear in a committed notebook.
SECRET_PATTERNS = [
    re.compile(r"dapi[a-z0-9]{32}"),                 # Databricks personal access token
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),  # PEM private key
    re.compile(r"MII[A-Za-z0-9+/]{200,}"),           # raw base64 DER private key blob
]


def reset_widgets(nb: dict) -> bool:
    changed = False
    widgets = (
        nb.get("metadata", {})
        .get(DBX_META_KEY, {})
        .get("widgets", {})
    )
    for info in widgets.values():
        if not isinstance(info, dict):
            continue
        default = ""
        wi = info.get("widgetInfo")
        if isinstance(wi, dict):
            default = wi.get("defaultValue", "") or ""
        if info.get("currentValue", "") != default:
            info["currentValue"] = default
            changed = True
        # widgetInfo.value sometimes mirrors currentValue
        if isinstance(wi, dict) and wi.get("value", default) != default:
            wi["value"] = default
            changed = True
    return changed


def strip_outputs(nb: dict) -> bool:
    changed = False
    for cell in nb.get("cells", []):
        if cell.get("cell_type") == "code":
            if cell.get("outputs"):
                cell["outputs"] = []
                changed = True
            if cell.get("execution_count") is not None:
                cell["execution_count"] = None
                changed = True
    return changed


def find_secrets(text: str) -> list[str]:
    hits = []
    for pat in SECRET_PATTERNS:
        m = pat.search(text)
        if m:
            hits.append(m.group(0)[:24] + "…")
    return hits


def sanitize(path: str) -> tuple[bool, list[str]]:
    with open(path, encoding="utf-8") as fh:
        nb = json.load(fh)
    changed = reset_widgets(nb) | strip_outputs(nb)
    if changed:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(nb, fh, indent=1, ensure_ascii=False)
            fh.write("\n")
    leaks = find_secrets(json.dumps(nb))
    return changed, leaks


def main(argv: list[str]) -> int:
    files = argv or sorted(glob.glob("**/*.ipynb", recursive=True))
    rc = 0
    for path in files:
        if not path.endswith(".ipynb"):
            continue
        changed, leaks = sanitize(path)
        tag = "sanitized" if changed else "clean"
        print(f"[{tag}] {path}")
        if leaks:
            rc = 1
            print(f"  !! CREDENTIAL-SHAPED STRING STILL PRESENT: {leaks}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
