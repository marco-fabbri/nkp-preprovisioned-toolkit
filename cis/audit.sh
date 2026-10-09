#!/usr/bin/env bash
# Audit the CIS Level 1 aligned baseline (subset of controls) on the inventory hosts.
# Thin wrapper around "./deploy.sh cis-audit", which runs the controller preflight.
# Exits non-zero when a control fails, unless -e cis_audit_strict=false is given.
#
# Usage:
#   ./cis/audit.sh [ansible-playbook options]
#   ./cis/audit.sh --limit jump_host
#   ./cis/audit.sh -e cis_audit_strict=false
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO_ROOT/deploy.sh" cis-audit "$@"
