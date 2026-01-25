#!/usr/bin/env python3
import json
import sys
from pathlib import Path

DARJA_MENU = [
  'chno kayn',
  'chnou kayen',
  'chno kayen',
  'wach kayn',
  'wesh kayn',
  'menu',
  'menou',
  'minou',
  'lmnu',
  'lmenu',
  'carte',
  'nchouf menu',
  'nchouf lmenu',
  'nchoof menu',
  'nchoof lmenu',
  'show menu',
  'bghit menu',
  'bghit nchoof menu',
  'bghit nchouf menu',
  'menu svp',
  'menu daba',
  'menu please',
  'carte svp',
]
DARJA_CHECKOUT = [
  'kml',
  'kammel',
  'kmel',
  'kml commande',
  'kmel commande',
  'kml daba',
  'kmel daba',
  'tchekout',
  'checkout',
  'check out',
  'confirm',
  'confirmer',
  'valider',
  'validé',
  'bghit ncommandi',
  'bghit ncommandi daba',
  'ncommandi',
  'ncmdi',
  'order',
  'passer commande',
  'commande',
  'finaliser',
  'payer',
  'cmd',
]

def normalize(text: str) -> str:
    lower = (text or '').strip().lower()
    normalized = lower
    if any(p in normalized for p in DARJA_MENU):
        normalized = 'menu'
    if any(p in normalized for p in DARJA_CHECKOUT):
        normalized = 'checkout'
    return normalized

def main():
    path = Path(__file__).resolve().parents[1] / 'tests' / 'darja_phrases.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    errors = []
    for i, row in enumerate(data, 1):
        txt = row['text']
        exp = row['expect']
        got = normalize(txt)
        if got != exp:
            errors.append(f"[{i}] '{txt}' => '{got}' (expected '{exp}')")
    if errors:
        print("❌ Darija intent tests FAILED")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    print(f"✅ Darija intent tests OK ({len(data)} phrases)")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
