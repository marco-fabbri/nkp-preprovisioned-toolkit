#!/usr/bin/env bash
# Apply the CIS Level 1 aligned baseline (subset of controls) to the inventory hosts.
# Thin wrapper around "./deploy.sh cis-harden", which runs the controller preflight.
#
# Usage:
#   ./cis/harden.sh [ansible-playbook options]
#   ./cis/harden.sh --limit nkp_nodes
#   ./cis/harden.sh -v
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$REPO_ROOT/deploy.sh" cis-harden "$@"
