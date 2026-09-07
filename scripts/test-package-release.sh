#!/bin/bash
set -euo pipefail

# The same file acts as a scoped hdiutil shim to capture staging and inject faults.
if [[ "${0##*/}" == hdiutil ]]; then
    args=("$@")
    if [[ "$1" == create ]]; then
        for ((i = 0; i < $#; i++)); do
            if [[ "${args[$i]}" == -srcfolder ]]; then
                source_index=$((i + 1))
                break
            fi
        done
        source_folder="${args[$source_index]}"
        ditto "$source_folder/ReTyper.app" "$PACKAGING_TEST_ROOT/staged.app"
        if [[ "${PACKAGING_TEST_FAULT:-}" == dmg-content ]]; then
            ditto "$source_folder" "$PACKAGING_TEST_ROOT/tampered-dmg"
            printf 'Different but validly signed content\n' > "$PACKAGING_TEST_ROOT/tampered-dmg/ReTyper.app/Contents/Resources/payload.txt"
            codesign --force --sign - --timestamp=none "$PACKAGING_TEST_ROOT/tampered-dmg/ReTyper.app"
            args[$source_index]="$PACKAGING_TEST_ROOT/tampered-dmg"
        fi
    elif [[ "$1" == attach && "${PACKAGING_TEST_FAULT:-}" == zip-signature ]]; then
        for argument in "$@"; do
            if [[ "$argument" == *.dmg ]]; then
                zip_path="${argument%.dmg}.zip"
                break
            fi
        done
        ditto -x -k "$zip_path" "$PACKAGING_TEST_ROOT/tampered-zip"
        printf 'Unsigned modification\n' > "$PACKAGING_TEST_ROOT/tampered-zip/ReTyper.app/Contents/Resources/payload.txt"
        rm -f -- "$zip_path"
        ditto -c -k --sequesterRsrc --keepParent "$PACKAGING_TEST_ROOT/tampered-zip/ReTyper.app" "$zip_path"
    fi
    exec /usr/bin/hdiutil "${args[@]}"
fi

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
packager="$script_dir/package-release.sh"
temp_parent="${TMPDIR:-/tmp}"
ls -d -- "$temp_parent" >/dev/null
test_root="$(mktemp -d "$temp_parent/retyper-packaging-test.XXXXXX")"
test_root="$(cd -- "$test_root" && pwd -P)"
mount_dir="$test_root/mount"
cleanup() {
    result=$?
    trap - EXIT
    if /sbin/mount | grep -Fq " on $mount_dir ("; then
        /usr/bin/hdiutil detach "$mount_dir" || /usr/bin/hdiutil detach -force "$mount_dir" || exit 1
    fi
    if [[ "${KEEP_PACKAGING_TEST_ARTIFACTS:-0}" == 1 ]]; then
        printf 'Test artifacts: %s\n' "$test_root"
    else
        rm -rf -- "$test_root"
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ls -d -- "$test_root" >/dev/null
mkdir -p "$test_root/source app.app/Contents/MacOS" "$test_root/source app.app/Contents/Resources" "$test_root/bin" "$mount_dir"
source_app="$test_root/source app.app"
printf 'int main(void) { return 0; }\n' > "$test_root/fixture.c"
xcrun clang -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 -o "$source_app/Contents/MacOS/ReTyper" "$test_root/fixture.c"
/usr/libexec/PlistBuddy \
    -c 'Add :CFBundleIdentifier string com.retyper.packaging-test' \
    -c 'Add :CFBundleExecutable string ReTyper' \
    -c 'Add :CFBundlePackageType string APPL' \
    -c 'Add :CFBundleShortVersionString string 0.0.0' \
    -c 'Add :CFBundleVersion string 0.0.0' \
    "$source_app/Contents/Info.plist"
printf 'Packaging fixture\n' > "$source_app/Contents/Resources/payload.txt"
chmod 640 "$source_app/Contents/Resources/payload.txt"
touch -t 202601020304.05 "$source_app/Contents/Resources/payload.txt"
xattr -w com.retyper.packaging-test preserved "$source_app/Contents/Resources/payload.txt"
ln -s payload.txt "$source_app/Contents/Resources/alias.txt"
codesign --force --sign - --timestamp=none "$source_app"
codesign --verify --deep --strict --all-architectures "$source_app"
ditto "$source_app" "$test_root/source-before.app"

ditto "$source_app" "$test_root/stale-signature.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1.2.3' "$test_root/stale-signature.app/Contents/Info.plist"
if codesign --verify --deep --strict --all-architectures "$test_root/stale-signature.app" > "$test_root/stale-signature.log" 2>&1; then
    fail 'Changing a signed plist unexpectedly preserved the signature'
fi
printf 'PASS: changing a signed plist invalidates the signature\n'

ditto "$0" "$test_root/bin/hdiutil"
chmod +x "$test_root/bin/hdiutil"
export PATH="$test_root/bin:$PATH"
version='1.2.3'

assert_app() {
    local app="$1" reference="$test_root/success output/staged.app" key
    for key in CFBundleShortVersionString CFBundleVersion; do
        [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Contents/Info.plist")" == "$version" ]] || fail "Wrong $key in $app"
    done
    lipo "$app/Contents/MacOS/ReTyper" -verify_arch arm64 x86_64
    codesign --verify --deep --strict --all-architectures "$app"
    diff -r "$reference" "$app"
    [[ -L "$app/Contents/Resources/alias.txt" && "$(readlink "$app/Contents/Resources/alias.txt")" == payload.txt ]] || fail 'Symlink was not preserved'
    [[ "$(stat -f '%Lp %m' "$app/Contents/Resources/payload.txt")" == "$(stat -f '%Lp %m' "$reference/Contents/Resources/payload.txt")" ]] || fail 'File mode or mtime changed'
    [[ "$(xattr -p com.retyper.packaging-test "$app/Contents/Resources/payload.txt")" == preserved ]] || fail 'Extended attribute was not preserved'
}

assert_failure_cleaned() {
    local output="$1"
    [[ ! -e "$output/.version" ]] || fail 'Failed prepare left a success marker'
    [[ ! -e "$output/ReTyper-macOS-universal.dmg" && ! -e "$output/ReTyper-macOS-universal.zip" ]] || fail 'Failed prepare installed artifacts'
    shopt -s nullglob
    local staging=("$output"/.retyper-package.*)
    [[ "${#staging[@]}" == 0 ]] || fail 'Failed prepare left its staging directory'
    if /sbin/mount | grep -Fq " on $output/"; then
        fail 'Failed prepare left a mounted image'
    fi
}

output="$test_root/success output"
mkdir "$output"
PACKAGING_TEST_ROOT="$output" bash "$packager" "$version" "$source_app" "$output" - > "$output/prepare.log" 2>&1
[[ "$(< "$output/.version")" == "$version" ]] || fail 'Missing or incorrect version marker'
assert_app "$output/staged.app"
ditto -x -k "$output/ReTyper-macOS-universal.zip" "$output/zip-extracted"
assert_app "$output/zip-extracted/ReTyper.app"
/usr/bin/hdiutil attach "$output/ReTyper-macOS-universal.dmg" -readonly -nobrowse -noautoopen -mountpoint "$mount_dir"
ditto "$mount_dir/ReTyper.app" "$output/dmg-extracted.app"
/usr/bin/hdiutil detach "$mount_dir"
assert_app "$output/dmg-extracted.app"
printf 'PASS: final DMG and ZIP match signed staging, versions, architectures and metadata\n'

for invalid in invalid-version missing-source; do
    output="$test_root/$invalid"
    mkdir "$output"
    input="$source_app"
    input_version="$version"
    if [[ "$invalid" == invalid-version ]]; then
        input_version='1.2.3; false'
        printf 'stale marker\n' > "$output/.version"
    else
        input="$test_root/missing.app"
    fi
    if bash "$packager" "$input_version" "$input" "$output" - > "$output/prepare.log" 2>&1; then
        fail "Accepted $invalid"
    fi
    assert_failure_cleaned "$output"
    printf 'PASS: rejects %s without a success marker\n' "$invalid"
done

output="$test_root/thin-binary"
mkdir "$output"
ditto "$source_app" "$test_root/thin.app"
lipo "$source_app/Contents/MacOS/ReTyper" -thin arm64 -output "$test_root/thin.app/Contents/MacOS/ReTyper"
if bash "$packager" "$version" "$test_root/thin.app" "$output" - > "$output/prepare.log" 2>&1; then
    fail 'Accepted a non-universal app'
fi
assert_failure_cleaned "$output"
printf 'PASS: rejects a non-universal app\n'

for fault in dmg-content zip-signature; do
    output="$test_root/$fault"
    mkdir "$output"
    printf 'stale marker\n' > "$output/.version"
    if PACKAGING_TEST_ROOT="$output" PACKAGING_TEST_FAULT="$fault" bash "$packager" "$version" "$source_app" "$output" - > "$output/prepare.log" 2>&1; then
        fail "Accepted $fault"
    fi
    assert_failure_cleaned "$output"
    if [[ "$fault" == dmg-content ]]; then
        codesign --verify --deep --strict --all-architectures "$output/tampered-dmg/ReTyper.app"
        grep -q 'differs from signed staging' "$output/prepare.log" || fail 'Did not reject the DMG content mismatch'
    else
        grep -q 'Signature validation failed' "$output/prepare.log" || fail 'Did not reject the invalid ZIP signature'
    fi
    printf 'PASS: rejects %s and cleans staging/mount/marker\n' "$fault"
done

diff -r "$test_root/source-before.app" "$source_app"
codesign --verify --deep --strict --all-architectures "$source_app"
printf 'PASS: the source app remains unchanged and validly signed\n'
