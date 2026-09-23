#!/bin/sh

set -eu

mode="${1:-full}"

run_fast() {
    git diff --check
    swift test
}

case "$mode" in
    fast)
        run_fast
        ;;
    full)
        run_fast
        xcodebuild \
            -project HomeStereo.xcodeproj \
            -scheme HomeStereo \
            -configuration Debug \
            -destination 'platform=macOS' \
            -derivedDataPath /tmp/HomeStereoDerivedData \
            build
        ;;
    *)
        echo "usage: $0 [fast|full]" >&2
        exit 64
        ;;
esac
