#!/bin/sh
set -eu
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec /opt/homebrew/bin/python3.12 "$script_dir/../analyzer/install.py" "$@"
