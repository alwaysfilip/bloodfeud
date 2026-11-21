#!/usr/bin/env bash
# Build the release package locally without uploading anything, to check
# what the packager will ship. Needs bash 4+ (brew install bash on macOS).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .release
if [ ! -f .release/release.sh ]; then
	curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh -o .release/release.sh
fi
bash .release/release.sh -d -g forever "$@"
echo
echo "Package contents:"
find .release/BloodFeud -maxdepth 2 | sort | sed 's#^.release/##'
