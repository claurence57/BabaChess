#!/usr/bin/env python3
"""Check the bilingual documentation.

Two guarantees, over docs/ and src/doc/:

1. For every ``<name>-fr.md`` there is a ``<name>-en.md`` with the **same
   heading-level sequence** (same sections in both languages).
2. Every **relative Markdown link** in the root and documentation files points
   to an existing file.

Exit 0 when everything is consistent, non-zero (with a report) otherwise. Used
by CI to keep the French and English versions from drifting apart, and to catch
links left behind by a rename.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIRS = [ROOT / "docs", ROOT / "src" / "doc"]

HEAD = re.compile(r"^(#{1,6})\s", re.M)
LINK = re.compile(r"\]\(([^)]+)\)")


def heading_levels(path: Path) -> list[int]:
    return [len(m.group(1)) for m in HEAD.finditer(path.read_text(encoding="utf-8"))]


def check() -> list[str]:
    errors: list[str] = []

    for d in DIRS:
        for fr in sorted(d.glob("*-fr.md")):
            en = fr.with_name(fr.name.replace("-fr.md", "-en.md"))
            if not en.exists():
                errors.append(f"{fr.relative_to(ROOT)}: missing {en.name}")
                continue
            hf, he = heading_levels(fr), heading_levels(en)
            if hf != he:
                errors.append(
                    f"{fr.name} / {en.name}: heading levels differ "
                    f"({hf} vs {he})"
                )

    mds = list(ROOT.glob("*.md"))
    for d in DIRS:
        mds += list(d.glob("*.md"))
    for md in mds:
        for m in LINK.finditer(md.read_text(encoding="utf-8")):
            target = m.group(1).strip()
            if target.startswith(("http://", "https://", "#", "mailto:")):
                continue
            target = target.split("#", 1)[0]
            if not target:
                continue
            if not (md.parent / target).resolve().exists():
                errors.append(
                    f"{md.relative_to(ROOT)}: broken link -> {target}"
                )
    return errors


def main() -> int:
    errors = check()
    if errors:
        print("docs check FAILED:")
        for e in errors:
            print("  -", e)
        return 1
    print("docs check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
