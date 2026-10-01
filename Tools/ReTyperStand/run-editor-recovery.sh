#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ $# -lt 3 ]]; then
    echo 'Usage: bash Tools/ReTyperStand/run-editor-recovery.sh PID /absolute/test/repro.txt /absolute/output [repeats]' >&2
    exit 2
fi
mkdir -p "$DIR/build"
swiftc -O "$DIR/EditorRecoveryDriver.swift" -o "$DIR/build/editor-recovery-driver"
"$DIR/build/editor-recovery-driver" "$@"
