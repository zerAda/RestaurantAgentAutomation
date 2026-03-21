#!/usr/bin/env python3
import json, os, sys, glob, hashlib
from jsonschema import Draft202012Validator, FormatChecker

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SCHEMAS = os.path.join(ROOT, 'schemas', 'inbound')
PAYLOADS = os.path.join(ROOT, 'tests', 'contracts')

def load_json(p):
    with open(p,'r',encoding='utf-8') as f:
        return json.load(f)

def sha256_file(p):
    h = hashlib.sha256()
    with open(p,'rb') as f:
        while True:
            b=f.read(65536)
            if not b: break
            h.update(b)
    return h.hexdigest()

def validate(schema_path, payload_path, should_pass: bool):
    schema = load_json(schema_path)
    payload = load_json(payload_path)
    v = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = sorted(v.iter_errors(payload), key=lambda e: e.path)
    ok = len(errors) == 0
    if ok != should_pass:
        print(f"FAIL: {os.path.basename(payload_path)} expected {'PASS' if should_pass else 'FAIL'} but got {'PASS' if ok else 'FAIL'}")
        for e in errors[:10]:
            print("   -", "/".join(map(str, e.path)), e.message)
        return False
    print(f"OK: {os.path.basename(payload_path)} {'PASS' if ok else 'FAIL'} as expected")
    return True

def main():
    v1 = os.path.join(SCHEMAS, 'v1.json')
    v2 = os.path.join(SCHEMAS, 'v2.json')
    assert os.path.exists(v1) and os.path.exists(v2), "schemas missing"

    print("Schema hashes:")
    print(" - v1:", sha256_file(v1))
    print(" - v2:", sha256_file(v2))

    tests = [
        (v1, os.path.join(PAYLOADS,'valid_v1.json'), True),
        (v2, os.path.join(PAYLOADS,'valid_v2.json'), True),
        (v1, os.path.join(PAYLOADS,'invalid_missing_msg_id.json'), False),
        (v2, os.path.join(PAYLOADS,'invalid_wrong_types.json'), False),
    ]

    ok = True
    for s,p,exp in tests:
        ok = validate(s,p,exp) and ok

    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
