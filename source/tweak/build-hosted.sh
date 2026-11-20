#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
    echo "Usage: bash build-hosted.sh https://your-relay.example.com" >&2
    exit 2
fi
relay_origin=$(printf '%s' "$1" | sed 's,/$,,')
if [[ ! $relay_origin =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    echo "Supply the hosted relay's HTTPS origin." >&2
    exit 2
fi

project=$(cd -- "$(dirname -- "$0")/.." && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf -- "$build_dir"' EXIT
cp "$project/tweak/"{Makefile,Tweak.xm,LegacyShazamSmoke.plist,control} "$build_dir/"
cp -R "$project/tweak/layout" "$build_dir/"
cd "$build_dir"
printf '#define LS_RELAY_URL @"%s/recognize"\n#define LS_RELAY_TOKEN @""\n' "$relay_origin" > RelayConfig.h
if [[ -z ${THEOS:-} ]]; then
    export THEOS=/opt/theos
fi
make stage FINALPACKAGE=1
install -D -m 0644 control .theos/_/DEBIAN/control
version=$(sed -n 's/^Version: //p' control | tr -d '\r')
package="$project/org.legacyshazam.smoke_${version}_hosted_iphoneos-arm.deb"
dpkg-deb --root-owner-group -Zgzip --build .theos/_ "$package"

