#!/usr/bin/env bash
# Make the game load this working copy: a symlink in the WoW: Forever AddOns
# folder that points at the repository. Pass another AddOns path as $1.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
addons="${1:-/Applications/World of Warcraft/_forever_/Interface/AddOns}"
target="$addons/BloodFeud"

if [ ! -d "$addons" ]; then
	echo "AddOns folder not found: $addons" >&2
	exit 1
fi
if [ -L "$target" ]; then
	echo "Already linked: $target -> $(readlink "$target")"
	exit 0
fi
if [ -e "$target" ]; then
	echo "Something that is not a link already exists at $target; leaving it alone." >&2
	exit 1
fi
ln -s "$repo" "$target"
echo "Linked $target -> $repo"
