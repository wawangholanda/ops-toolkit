#!/usr/bin/env python3
"""Identify a local GitLab Runner by token and safely manage its name."""
import datetime
import json
import re
import shutil
import sys
from pathlib import Path

CONFIG = Path("/etc/gitlab-runner/config.toml")
request = json.load(sys.stdin)
token = request.get("token", "")
name = request.get("name", "")

if not token or not name:
    print(json.dumps({"action": "error", "message": "Runner token and name are required."}))
    sys.exit(2)

content = CONFIG.read_text() if CONFIG.exists() else ""
blocks = re.split(r"(?m)(?=^\[\[runners\]\]\s*$)", content)
runners = []

for index, block in enumerate(blocks):
    if not re.match(r"(?m)^\[\[runners\]\]\s*$", block):
        continue

    token_match = re.search(
        r'(?m)^\s*token\s*=\s*("(?:\\.|[^"\\])*")\s*$', block
    )
    name_match = re.search(
        r'(?m)^(\s*)name\s*=\s*("(?:\\.|[^"\\])*")\s*$', block
    )

    try:
        current_token = json.loads(token_match.group(1)) if token_match else ""
        current_name = json.loads(name_match.group(2)) if name_match else ""
    except (ValueError, TypeError):
        print(json.dumps({
            "action": "error",
            "message": "Could not parse a runner token or name; refusing to edit config.toml."
        }))
        sys.exit(2)

    runners.append((index, block, current_token, current_name, name_match))

matching_token = next((r for r in runners if r[2] == token), None)
name_conflict = next(
    (r for r in runners if r[3] == name and r[2] != token), None
)

if name_conflict:
    print(json.dumps({
        "action": "name_conflict",
        "message": "Runner name already exists. Choose another name."
    }))
    sys.exit(3)

if matching_token:
    index, block, _, current_name, name_match = matching_token

    if current_name == name:
        print(json.dumps({
            "action": "already_configured",
            "message": "Token and local name already match."
        }))
        sys.exit(0)

    if not name_match:
        print(json.dumps({
            "action": "error",
            "message": "Matching runner has no parseable name field; refusing to edit."
        }))
        sys.exit(2)

    replacement = f"{name_match.group(1)}name = {json.dumps(name)}"
    blocks[index] = block[:name_match.start()] + replacement + block[name_match.end():]

    backup = CONFIG.with_name(
        "config.toml.backup-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    )
    shutil.copy2(CONFIG, backup)
    CONFIG.write_text("".join(blocks))

    print(json.dumps({
        "action": "renamed",
        "message": "Updated only the runner matching this token."
    }))
    sys.exit(0)

print(json.dumps({
    "action": "register",
    "message": "Token is not registered locally and the name is available."
}))
