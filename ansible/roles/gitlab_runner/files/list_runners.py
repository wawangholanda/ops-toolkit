#!/usr/bin/env python3
import json
import sys
import tomllib
from pathlib import Path

config = Path("/etc/gitlab-runner/config.toml")

if not config.exists():
    print(json.dumps([]))
    sys.exit(0)

try:
    data = tomllib.loads(config.read_text())
except Exception:
    print("ERROR: Cannot safely parse config.toml.", file=sys.stderr)
    sys.exit(1)

runners = []
for runner in data.get("runners", []):
    runners.append({
        "name": runner.get("name", ""),
        "executor": runner.get("executor", "unknown"),
        "url": runner.get("url", ""),
    })

print(json.dumps(runners))
