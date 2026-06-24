#!/usr/bin/env python3
"""Drive the Application Signals Dynamic Instrumentation control plane for the
python-ec2 adot-di E2E test. One verb per workflow step:

  create          POST create-...  for each cell; store LocationHash in $GITHUB_ENV
  verify-created  POST get-...      assert the stored LocationHash comes back
  delete          POST delete-...   assert DeletionStatus == DELETED
  verify-deleted  POST get-...      assert the config is gone (ResourceNotFound)
  render <key>    print a rendered request body (debugging only; no network call)

The 4 cells, one per distinct SDK code path:
  LineBreakpoint        -> views.http_call      (line engine)
  MethodProbe           -> views.aws_sdk_call   (function wrapper, PROBE path)
  MethodBreakpoint      -> views.downstream_service (function wrapper, BREAKPOINT path)
  MethodProbeException  -> views.mysql          (function wrapper throwable capture)

There is no lineProbe: both ADOT Python and ADOT Java force line_number=0 for any
PROBE config, so a (PROBE, line) request degenerates to (PROBE, method). There is no
lineBreakpointException: the line engine has no exception-capture machinery (line
snapshots fire pre-execution and emit no throwable regardless of whether the line raises).

Request bodies + placeholders come from di-api-requests.json (see render()).
Config is read from the environment: DI_API_URL, E2E_TEST_AWS_REGION, SERVICE_NAME,
DI_ENVIRONMENT (create also computes EXPIRES_AT). Hashes flow between steps via
$GITHUB_ENV as <CELL>_LOCATION_HASH (e.g. LINE_BREAKPOINT_LOCATION_HASH).
"""
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REQUESTS = os.path.join(HERE, "di-api-requests.json")

CELLS = ["LineBreakpoint", "MethodProbe", "MethodBreakpoint", "MethodProbeException"]

REGION = os.environ.get("E2E_TEST_AWS_REGION", "")
API_URL = os.environ.get("DI_API_URL", "").rstrip("/")

NOT_FOUND = re.compile(r"ResourceNotFound|not found|does not exist|has been deleted", re.I)


def render(key):
    """Render a request body from di-api-requests.json, substituting env placeholders.

    "$VAR"     -> os.environ["VAR"] as a string
    "$INT:VAR" -> int(os.environ["VAR"]) (e.g. ExpiresAt, which must be epoch seconds)
    """
    with open(REQUESTS) as f:
        obj = json.load(f)[key]

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

    return sub(obj)


def call(action, key):
    """SigV4-sign and POST a rendered body to a control-plane action.

    Returns (parsed_json_or_None, raw_text). awscurl is allowed to exit non-zero
    (e.g. a get on a deleted config returns an error body) — callers inspect the result.
    """
    body = json.dumps(render(key))
    out = subprocess.run(
        ["awscurl", "--service", "application-signals", "--region", REGION,
         "-X", "POST", "-H", "content-type: application/json", "-d", body,
         f"{API_URL}/{action}"],
        capture_output=True, text=True,
    )
    raw = (out.stdout + out.stderr).strip()
    try:
        return json.loads(out.stdout), raw
    except json.JSONDecodeError:
        return None, raw


def hash_var(cell):
    """LineBreakpoint -> LINE_BREAKPOINT_LOCATION_HASH"""
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", cell).upper() + "_LOCATION_HASH"


def set_github_env(name, value):
    path = os.environ.get("GITHUB_ENV")
    if path:
        with open(path, "a") as f:
            f.write(f"{name}={value}\n")


def cells_with_hash():
    """Yield (cell, hash) for cells whose <CELL>_LOCATION_HASH env var is set, exporting
    LOCATION_HASH for the get/delete body templates. Skipping empties lets the post-create
    steps clean up after a partial create (the create step is the gate that all 4 exist)."""
    for cell in CELLS:
        h = os.environ.get(hash_var(cell), "")
        if h:
            os.environ["LOCATION_HASH"] = h
            yield cell, h


def cmd_create():
    os.environ["EXPIRES_AT"] = str(int(time.time()) + 1800)
    for cell in CELLS:
        data, raw = call("create-instrumentation-configuration", f"create{cell}")
        print(f"{cell} Create response: {raw}")
        location_hash = (data or {}).get("LocationHash")
        if not location_hash:
            sys.exit(f"ERROR: {cell} Create did not return LocationHash")
        set_github_env(hash_var(cell), location_hash)
        print(f"{cell} OK: {hash_var(cell)}={location_hash}")


def cmd_verify_created():
    for cell, expected in cells_with_hash():
        data, raw = call("get-instrumentation-configuration", f"get{cell}")
        print(f"{cell} Get response: {raw}")
        got = (data or {}).get("Configuration", {}).get("LocationHash")
        if got != expected:
            sys.exit(f"ERROR: {cell} Get returned hash={got}, expected {expected}")
        print(f"{cell} Get OK")


def cmd_delete():
    for cell, _ in cells_with_hash():
        data, raw = call("delete-instrumentation-configuration", f"delete{cell}")
        print(f"{cell} Delete response: {raw}")
        status = (data or {}).get("DeletionStatus")
        if status != "DELETED":
            sys.exit(f"ERROR: {cell} Delete returned DeletionStatus={status}, expected DELETED")
        print(f"{cell} deleted")


def cmd_verify_deleted():
    for cell, _ in cells_with_hash():
        _, raw = call("get-instrumentation-configuration", f"get{cell}")
        print(f"{cell} post-delete Get: {raw}")
        if not NOT_FOUND.search(raw):
            sys.exit(f"ERROR: {cell} configuration still exists after Delete")
        print(f"{cell} post-delete Get OK")


VERBS = {
    "create": cmd_create,
    "verify-created": cmd_verify_created,
    "delete": cmd_delete,
    "verify-deleted": cmd_verify_deleted,
}

if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "render":
        print(json.dumps(render(sys.argv[2]), indent=2))
    elif arg in VERBS:
        VERBS[arg]()
    else:
        sys.exit(f"usage: di-control-plane.py {{{'|'.join(VERBS)}|render <key>}}")
