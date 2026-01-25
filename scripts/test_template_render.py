#!/usr/bin/env python3
import re
import json
from pathlib import Path

def render(content: str, vars: dict, allowed=None):
    allow = set(allowed or []) if allowed is not None else None
    def repl(m):
        k=m.group(1)
        if allow is not None and k not in allow:
            return ''
        return str(vars.get(k,'')) if vars.get(k) is not None else ''
    out=re.sub(r"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}", repl, content or '')
    out=re.sub(r"\{\{[^}]+\}\}","",out)
    return out.strip()

def main():
    data_path = Path(__file__).resolve().parents[1] / 'tests' / 'template_render_cases.json'
    if data_path.exists():
        cases = json.loads(data_path.read_text(encoding='utf-8'))
        for row in cases:
            out = render(row.get('content',''), row.get('vars',{}), allowed=row.get('allowed'))
            exp = row.get('expected','')
            assert out == exp, f"{row.get('label','case')}: '{out}' != '{exp}'"
        print(f"✅ Template render tests OK ({len(cases)} cases)")
        return 0

    # Fallback small suite
    c="Hello {{name}} {{secret}}"
    out=render(c, {"name":"A","secret":"X"}, allowed=["name"])
    assert out=="Hello A", out

    c="✅ (#{{order_id}}).{{eta}}"
    out=render(c, {"order_id":"123"}, allowed=["order_id","eta"])
    assert out=="✅ (#123).", out

    c="X {{unknown}} Y"
    out=render(c, {}, allowed=["name"])
    assert out=="X  Y".strip(), out

    print("✅ Template render unit tests OK")
    return 0

if __name__=='__main__':
    try:
        raise SystemExit(main())
    except AssertionError as e:
        print("❌ Template render unit tests FAILED:", e)
        raise SystemExit(1)
