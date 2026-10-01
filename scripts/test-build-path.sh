#!/bin/bash
set -euo pipefail

# Isolated build-path regression: a successful build must not select a stale conventional path.
project="$(cd "$(dirname "$0")/.." && pwd)"
root="$(mktemp -d "${TMPDIR:-/tmp}/retyper-build-path.XXXXXX")"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/project/.build/debug" "$root/bin" "$root/output with spaces"
cp "$project/build.sh" "$root/project/build.sh"
printf 'stale\n' > "$root/project/.build/debug/ReTyper"
cat > "$root/bin/swift" <<'SH'
#!/bin/bash
set -eu
[[ "$*" == *"--build-system native"* ]] || exit 91
if [[ "$*" == *"--show-bin-path"* ]]; then
    printf '%s\n' "$TEST_OUTPUT"
elif [[ "${TEST_FAIL:-0}" == 1 ]]; then
    exit 92
elif [[ "${TEST_MISSING:-0}" != 1 ]]; then
    printf 'fresh\n' > "$TEST_OUTPUT/ReTyper"
    chmod +x "$TEST_OUTPUT/ReTyper"
fi
SH
cat > "$root/bin/codesign" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$root/bin/swift" "$root/bin/codesign"
export PATH="$root/bin:$PATH" TEST_OUTPUT="$root/output with spaces" RETYPER_BUILD_SYSTEM=native
bash "$root/project/build.sh" >/dev/null
cmp "$TEST_OUTPUT/ReTyper" "$root/project/ReTyper.app/Contents/MacOS/ReTyper"
[[ "$(cat "$root/project/ReTyper.app/Contents/MacOS/ReTyper")" == fresh ]]
printf 'PASS: resolved output is packaged instead of stale .build/debug\n'
if TEST_FAIL=1 bash "$root/project/build.sh" >/dev/null 2>&1; then
    echo 'FAIL: ignored build failure' >&2; exit 1
fi
printf 'PASS: failed build cannot package cached output\n'
rm "$TEST_OUTPUT/ReTyper"
if TEST_MISSING=1 bash "$root/project/build.sh" >/dev/null 2>&1; then
    echo 'FAIL: accepted missing executable' >&2; exit 1
fi
[[ "$(cat "$root/project/ReTyper.app/Contents/MacOS/ReTyper")" == fresh ]]
printf 'PASS: missing output preserves the installed bundle\n'
