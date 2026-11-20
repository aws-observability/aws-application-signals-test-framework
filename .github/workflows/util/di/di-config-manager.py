#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
import time


def create_di_request_body(key):
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

    requests_file = os.environ.get("DI_REQUESTS_FILE", "di-api-requests-python.json")
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), requests_file)) as f:
        return sub(json.load(f)[key])


def call_di(action, key):
    out = subprocess.run(
        ["awscurl", "--service", "application-signals",
         "--region", os.environ.get("E2E_TEST_AWS_REGION", ""),
         "-X", "POST", "-H", "content-type: application/json",
         "-d", json.dumps(create_di_request_body(key)),
         f"{os.environ.get('DI_API_URL', '').rstrip('/')}/{action}"],
        capture_output=True, text=True,
    )
    raw = (out.stdout + out.stderr).strip()
    try:
        return json.loads(out.stdout), raw
    except json.JSONDecodeError:
        return None, raw


def hash_var(cell):
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", cell).upper() + "_LOCATION_HASH"


def cells():
    requests_file = os.environ.get("DI_REQUESTS_FILE", "di-api-requests-python.json")
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), requests_file)) as f:
        return [k[len("create"):] for k in json.load(f) if k.startswith("create")]


def cells_with_hash():
    for cell in cells():
        h = os.environ.get(hash_var(cell), "")
        if h:
            os.environ["LOCATION_HASH"] = h
            yield cell, h


def cmd_create():
    os.environ["EXPIRES_AT"] = str(int(time.time()) + 1800)
    for cell in cells():
        data, raw = call_di("create-instrumentation-configuration", f"create{cell}")
        print(f"{cell} Create response: {raw}")
        location_hash = (data or {}).get("LocationHash")
        if not location_hash:
            sys.exit(f"ERROR: {cell} Create did not return LocationHash")
        github_env = os.environ.get("GITHUB_ENV")
        if github_env:
            with open(github_env, "a") as f:
                f.write(f"{hash_var(cell)}={location_hash}\n")
        print(f"{cell} OK: {hash_var(cell)}={location_hash}")


def cmd_verify_created():
    for cell, expected in cells_with_hash():
        data, raw = call_di("get-instrumentation-configuration", f"get{cell}")
        print(f"{cell} Get response: {raw}")
        got = (data or {}).get("Configuration", {}).get("LocationHash")
        if got != expected:
            sys.exit(f"ERROR: {cell} Get returned hash={got}, expected {expected}")
        print(f"{cell} Get OK")


def cmd_delete():
    for cell, _ in cells_with_hash():
        data, raw = call_di("delete-instrumentation-configuration", f"delete{cell}")
        print(f"{cell} Delete response: {raw}")
        status = (data or {}).get("DeletionStatus")
        if status != "DELETED":
            sys.exit(f"ERROR: {cell} Delete returned DeletionStatus={status}, expected DELETED")
        print(f"{cell} deleted")


def cmd_verify_deleted():
    for cell, _ in cells_with_hash():
        _, raw = call_di("get-instrumentation-configuration", f"get{cell}")
        print(f"{cell} post-delete Get: {raw}")
        if not re.search(r"ResourceNotFound|not found|does not exist|has been deleted", raw, re.I):
            sys.exit(f"ERROR: {cell} configuration still exists after Delete")
        print(f"{cell} post-delete Get OK")


if __name__ == "__main__":
    verbs = {
        "create": cmd_create,
        "verify-created": cmd_verify_created,
        "delete": cmd_delete,
        "verify-deleted": cmd_verify_deleted,
    }
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "render":
        print(json.dumps(create_di_request_body(sys.argv[2]), indent=2))
    elif arg in verbs:
        verbs[arg]()
    else:
        sys.exit(f"usage: di-config-manager.py {{{'|'.join(verbs)}|render <key>}}")
