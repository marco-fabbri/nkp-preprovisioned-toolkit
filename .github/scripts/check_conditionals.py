#!/usr/bin/env python3
"""Fail when a when/that/failed_when/changed_when/until item is not a string.

An unquoted condition that contains ": " is read by YAML as a mapping; Ansible
only rejects it at run time, and neither ansible-lint nor --syntax-check notice.
"""
import glob
import sys

import yaml

KEYS = {"when", "that", "failed_when", "changed_when", "until"}
found = []


def walk(node, path, name):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in KEYS:
                for item in value if isinstance(value, list) else [value]:
                    if not isinstance(item, (str, bool)):
                        found.append(f"{name}: {path}/{key}: {item!r}")
            walk(value, f"{path}/{key}", name)
    elif isinstance(node, list):
        for index, item in enumerate(node):
            walk(item, f"{path}[{index}]", name)


for name in sorted(glob.glob("ansible/**/*.yml", recursive=True) + glob.glob("cis/**/*.yml", recursive=True)):
    with open(name, encoding="utf-8") as handle:
        walk(yaml.safe_load(handle), "", name)

for line in found:
    print(line)
sys.exit(1 if found else 0)
