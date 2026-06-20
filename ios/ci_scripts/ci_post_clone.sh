#!/bin/sh
# Xcode Cloud runs this automatically right after cloning the repo, before
# the build starts. It stamps pubspec.yaml's build number with Xcode
# Cloud's own auto-incrementing CI_BUILD_NUMBER so every TestFlight/App
# Store upload always has a higher build number than the last one.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

BUILD_NUMBER="${CI_BUILD_NUMBER:-$(git rev-list --count HEAD)}"

sed -i '' -E "s/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+/version: \1+${BUILD_NUMBER}/" pubspec.yaml

echo "Set build number to ${BUILD_NUMBER}"
