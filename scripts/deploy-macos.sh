#!/bin/sh

set -eu

app_name="HomeStereo"
bundle_identifier="jp.local.HomeStereo.Beta"
destination="/Applications/${app_name}.app"
derived_data="/tmp/HomeStereoDeployDerivedData"
verification_derived_data="/tmp/HomeStereoDerivedData"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(dirname -- "$script_dir")"
build_number="$(date '+%Y%m%d%H%M%S')"
launch_after_deploy=1

usage() {
    echo "usage: $0 [--no-launch]" >&2
}

case "${1:-}" in
    "")
        ;;
    --no-launch)
        launch_after_deploy=0
        ;;
    *)
        usage
        exit 64
        ;;
esac

if [ "$#" -gt 1 ]; then
    usage
    exit 64
fi

info_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

verify_app() {
    app_path="$1"
    expected_build="$2"

    [ -d "$app_path" ] || {
        echo "missing app bundle: $app_path" >&2
        return 1
    }
    [ "$(info_value "$app_path" CFBundleIdentifier)" = "$bundle_identifier" ] || {
        echo "unexpected bundle identifier: $app_path" >&2
        return 1
    }
    [ "$(info_value "$app_path" CFBundleVersion)" = "$expected_build" ] || {
        echo "unexpected build number: $app_path" >&2
        return 1
    }
    codesign --verify --deep --strict --verbose=2 "$app_path"
}

stop_running_copies() {
    running_pids="$(pgrep -x "$app_name" 2>/dev/null || true)"
    [ -n "$running_pids" ] || return 0

    echo "Stopping running ${app_name} copies: $(echo "$running_pids" | tr '\n' ' ')"
    pkill -TERM -x "$app_name"

    attempts=0
    while pgrep -x "$app_name" >/dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 20 ]; then
            echo "${app_name} did not quit; deployment was not started." >&2
            return 1
        fi
        sleep 0.25
    done
}

unregister_indexed_noncanonical_copies() {
    mdfind "kMDItemCFBundleIdentifier == '$bundle_identifier'" | while IFS= read -r app_path; do
        [ "$app_path" != "$destination" ] || continue
        [ -d "$app_path" ] || continue
        [ "$(info_value "$app_path" CFBundleIdentifier 2>/dev/null || true)" = "$bundle_identifier" ] || continue
        echo "Unregistering non-canonical app copy: $app_path"
        "$lsregister" -u "$app_path" >/dev/null 2>&1 || true
    done
}

cd "$project_root"

"$script_dir/install-analyzer.sh"

stop_running_copies
unregister_indexed_noncanonical_copies

echo "Cleaning the Xcode Debug product so it cannot remain as a second app copy..."
xcodebuild \
    -project HomeStereo.xcodeproj \
    -scheme HomeStereo \
    -configuration Debug \
    -destination 'platform=macOS' \
    clean
case "$verification_derived_data" in
    /tmp/HomeStereoDerivedData) rm -rf -- "$verification_derived_data" ;;
esac

echo "Building ${app_name} Release build ${build_number}..."
xcodebuild \
    -project HomeStereo.xcodeproj \
    -scheme HomeStereo \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    CURRENT_PROJECT_VERSION="$build_number" \
    clean build

source_app="$derived_data/Build/Products/Release/${app_name}.app"
verify_app "$source_app" "$build_number"
source_hash="$(shasum -a 256 "$source_app/Contents/MacOS/$app_name" | awk '{print $1}')"

stage_dir="$(mktemp -d "/Applications/.${app_name}Deploy.XXXXXX")"
stage_app="$stage_dir/${app_name}.app"
backup_app="/Applications/.${app_name}.previous.$$"
replacement_started=0

cleanup() {
    status=$?

    if [ "$status" -ne 0 ] && [ "$replacement_started" -eq 1 ] && [ -e "$backup_app" ]; then
        if [ -e "$destination" ]; then
            case "$destination" in
                /Applications/HomeStereo.app) rm -rf -- "$destination" ;;
            esac
        fi
        mv "$backup_app" "$destination"
        replacement_started=0
        echo "Restored the previous ${app_name}.app after a deployment failure." >&2
    fi

    case "$stage_dir" in
        /Applications/.HomeStereoDeploy.*) rm -rf -- "$stage_dir" ;;
    esac
    case "$backup_app" in
        /Applications/.HomeStereo.previous.*) rm -rf -- "$backup_app" ;;
    esac
    case "$derived_data" in
        /tmp/HomeStereoDeployDerivedData)
            if [ -d "$source_app" ]; then
                "$lsregister" -u "$source_app" >/dev/null 2>&1 || true
            fi
            rm -rf -- "$derived_data"
            ;;
    esac

    exit "$status"
}
trap cleanup EXIT HUP INT TERM

ditto "$source_app" "$stage_app"
verify_app "$stage_app" "$build_number"

if [ -d "$destination" ]; then
    "$lsregister" -u "$destination" >/dev/null 2>&1 || true
    mv "$destination" "$backup_app"
    replacement_started=1
fi

mv "$stage_app" "$destination"
verify_app "$destination" "$build_number"
destination_hash="$(shasum -a 256 "$destination/Contents/MacOS/$app_name" | awk '{print $1}')"
[ "$source_hash" = "$destination_hash" ] || {
    echo "deployed executable does not match the Release build" >&2
    exit 1
}

replacement_started=0
rm -rf -- "$backup_app"
"$lsregister" -f "$destination" >/dev/null

echo "Deployed ${destination}"
echo "Bundle version: ${build_number}"
echo "Executable SHA-256: ${destination_hash}"

if [ "$launch_after_deploy" -eq 1 ]; then
    open "$destination"
    echo "Launched the canonical app from ${destination}"
fi
