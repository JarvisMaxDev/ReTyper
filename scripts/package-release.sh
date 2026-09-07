#!/bin/bash
set -euo pipefail

fail() { printf 'Release packaging: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 4 ]] || fail 'Usage: package-release.sh VERSION SOURCE_APP OUTPUT_DIR SIGNING_IDENTITY'
version="$1"
source_app="$2"
output_dir="$3"
identity="$4"
archive_name='ReTyper-macOS-universal'

[[ -d "$output_dir" ]] || fail 'Output directory must already exist'
output_dir="$(cd -- "$output_dir" && pwd -P)"
if [[ -d "$source_app" ]]; then
    source_app="$(cd -- "$source_app" && pwd -P)"
    [[ "$output_dir/" != "$source_app/"* ]] || fail 'Output directory must be outside the source app'
fi
for name in .version "$archive_name.dmg" "$archive_name.zip"; do
    path="$output_dir/$name"
    [[ ! -L "$path" && ( ! -e "$path" || -f "$path" ) ]] || fail "Refusing non-regular output: $path"
done
rm -f -- "$output_dir/.version"

[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]] || fail 'Invalid release version'
[[ -n "$identity" && ( "$identity" == - || "$identity" != -* ) ]] || fail 'Invalid signing identity'
[[ "$source_app" == *.app && -d "$source_app" ]] || fail 'Source must be an existing .app bundle'
for name in Contents Contents/MacOS Contents/Info.plist; do
    [[ ! -L "$source_app/$name" ]] || fail "Refusing symlinked $name"
done
[[ -f "$source_app/Contents/Info.plist" ]] || fail 'Missing Info.plist'
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$source_app/Contents/Info.plist")"
case "$executable" in
    ''|.|..|*/*) fail 'CFBundleExecutable must be a file name' ;;
esac
[[ -f "$source_app/Contents/MacOS/$executable" && -x "$source_app/Contents/MacOS/$executable" && ! -L "$source_app/Contents/MacOS/$executable" ]] || fail 'Missing or symlinked executable'

ls -d -- "$output_dir" >/dev/null
work_dir="$(mktemp -d "$output_dir/.retyper-package.XXXXXX")"
mount_dir="$work_dir/mount"
cleanup() {
    local result=$?
    trap - EXIT
    if /sbin/mount | grep -Fq " on $mount_dir ("; then
        if ! hdiutil detach "$mount_dir" && ! hdiutil detach -force "$mount_dir"; then
            printf 'Could not detach owned mount; retained staging: %s\n' "$work_dir" >&2
            rm -f -- "$output_dir/.version"
            exit 1
        fi
    fi
    rm -rf -- "$work_dir" || result=1
    if [[ "$result" != 0 ]]; then
        rm -f -- "$output_dir/.version"
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ls -d -- "$work_dir" >/dev/null
mkdir "$work_dir/dmg" "$work_dir/zip" "$mount_dir"
staged_app="$work_dir/dmg/ReTyper.app"
ditto "$source_app" "$staged_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$staged_app/Contents/Info.plist"
sign_options=(--force --sign "$identity")
if [[ "$identity" == - ]]; then
    sign_options+=(--timestamp=none)
fi
codesign "${sign_options[@]}" "$staged_app"

verify_app() {
    local app="$1" key link relative
    for key in CFBundleShortVersionString CFBundleVersion; do
        [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$app/Contents/Info.plist")" == "$version" ]] || fail "Wrong $key in $app"
    done
    lipo "$app/Contents/MacOS/$executable" -verify_arch arm64 x86_64 || fail "Missing universal architectures in $app"
    codesign --verify --deep --strict --all-architectures "$app" || fail "Signature validation failed: $app"
    if [[ "$app" != "$staged_app" ]]; then
        diff -r "$staged_app" "$app" || fail "$app differs from signed staging"
        # diff follows symlinks, so also check their type and target explicitly.
        while IFS= read -r -d '' link; do
            relative="${link#"$staged_app"/}"
            [[ -L "$app/$relative" && "$(readlink "$link")" == "$(readlink "$app/$relative")" ]] || fail "$app symlink differs from signed staging: $relative"
        done < <(find "$staged_app" -type l -print0)
    fi
}

verify_app "$staged_app"
dmg="$work_dir/$archive_name.dmg"
zip="$work_dir/$archive_name.zip"
hdiutil create -volname ReTyper -srcfolder "$work_dir/dmg" -format UDZO "$dmg"
ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$zip"

hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$mount_dir"
verify_app "$mount_dir/ReTyper.app"
hdiutil detach "$mount_dir"
ditto -x -k "$zip" "$work_dir/zip"
verify_app "$work_dir/zip/ReTyper.app"

mv -f -- "$dmg" "$output_dir/$archive_name.dmg"
mv -f -- "$zip" "$output_dir/$archive_name.zip"
printf 'Validated DMG and ZIP for version %s; no publication performed.\n' "$version"
# This marker records successful preparation, not publication.
printf '%s\n' "$version" > "$output_dir/.version"
