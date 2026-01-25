#!/usr/bin/env python3
import re
import json
from pathlib import Path


def has_arabic(text: str) -> bool:
    """Return True if text contains Arabic script (same logic as in workflows)."""
    return bool(re.search(r"[؀-ۿݐ-ݿࢠ-ࣿ]", text or ""))


def main() -> int:
    # Prefer curated test data if present
    data_path = Path(__file__).resolve().parents[1] / 'tests' / 'arabic_script_cases.json'
    if data_path.exists():
        raw = json.loads(data_path.read_text(encoding='utf-8'))
        cases = [(r.get('text',''), bool(r.get('hasArabic'))) for r in raw]
    else:
        cases = [
            ("menu svp", False),
            ("Je veux commander", False),
            ("القائمة", True),
            ("منيو", True),
            ("kml", False),
            ("كمل", True),
            ("✅", False),
            ("123", False),
            ("١٢٣", True),  # Arabic-Indic digits are in the Arabic block
            ("Mix: P01 و P02", True),
        ]

    errors = []
    for txt, exp in cases:
        got = has_arabic(txt)
        if got != exp:
            errors.append(f"'{txt}' => {got} (expected {exp})")

    if errors:
        print("❌ L10N script detection tests FAILED")
        for e in errors:
            print(" -", e)
        return 1

    print(f"✅ L10N script detection tests OK ({len(cases)} cases)")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
