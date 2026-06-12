#!/usr/bin/env python3
"""Render a request body from di-api-requests.json with placeholder substitution.

Usage: python3 di-payload.py <key>
  where <key> is one of: createBreakpoint createProbe getBreakpoint getProbe deleteBreakpoint deleteProbe

Placeholders:
  "$VAR"      -> os.environ["VAR"] as a string
  "$INT:VAR"  -> int(os.environ["VAR"]) (used for ExpiresAt which must be epoch seconds)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "di-api-requests.json")) as f:
    doc = json.load(f)

key = sys.argv[1]
obj = doc[key]


def sub(v):
    if isinstance(v, dict):
        return {k: sub(x) for k, x in v.items()}
    if isinstance(v, list):
        return [sub(x) for x in v]
    if isinstance(v, str):
        m = re.fullmatch(r"\$INT:([A-Z_][A-Z0-9_]*)", v)
        if m:
            return int(os.environ[m.group(1)])
        m = re.fullmatch(r"\$([A-Z_][A-Z0-9_]*)", v)
        if m:
            return os.environ[m.group(1)]
    return v


print(json.dumps(sub(obj)))
