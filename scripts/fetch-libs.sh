#!/usr/bin/env bash
# Fetch the embedded libraries into Libs/ for local development.
# Released packages get the same libraries from the packager (see .pkgmeta).
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone -q --depth 1 https://github.com/WoWUIDev/Ace3 "$tmp/ace3"
git clone -q --depth 1 https://github.com/tekkub/libdatabroker-1-1 "$tmp/ldb"
svn export -q https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0 "$tmp/LibDBIcon-1.0"

mkdir -p Libs
for lib in LibStub CallbackHandler-1.0 AceComm-3.0; do
	rm -rf "Libs/$lib"
	cp -R "$tmp/ace3/$lib" "Libs/$lib"
done
rm -rf Libs/LibDataBroker-1.1 Libs/LibDBIcon-1.0
mkdir -p Libs/LibDataBroker-1.1
cp "$tmp/ldb/LibDataBroker-1.1.lua" Libs/LibDataBroker-1.1/
cp -R "$tmp/LibDBIcon-1.0" Libs/LibDBIcon-1.0

echo "Libraries in Libs/:"
ls Libs
