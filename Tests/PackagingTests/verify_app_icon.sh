#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <app-or-xcarchive>" >&2
    exit 64
fi

product_path=$1

if [[ $product_path == *.xcarchive ]]; then
    applications_path="$product_path/Products/Applications"
    shopt -s nullglob
    applications=("$applications_path"/*.app)
    shopt -u nullglob

    if [[ ${#applications[@]} -ne 1 ]]; then
        echo "Expected one archived application in $applications_path, found ${#applications[@]}." >&2
        exit 1
    fi

    product_path=${applications[0]}
fi

info_plist="$product_path/Contents/Info.plist"
resources_path="$product_path/Contents/Resources"

if [[ ! -f $info_plist ]]; then
    echo "Missing application Info.plist: $info_plist" >&2
    exit 1
fi

icon_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$info_plist" 2>/dev/null || true)
if [[ -z $icon_name ]]; then
    icon_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$info_plist" 2>/dev/null || true)
fi

if [[ -z $icon_name ]]; then
    echo "The application has no primary icon metadata." >&2
    exit 1
fi

if [[ $icon_name != *.icns ]]; then
    icon_name="$icon_name.icns"
fi

icon_path="$resources_path/$icon_name"
if [[ ! -s $icon_path ]]; then
    echo "The primary icon resource is missing or empty: $icon_path" >&2
    exit 1
fi

pixel_width=$(sips -g pixelWidth "$icon_path" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')
if [[ ! $pixel_width =~ ^[1-9][0-9]*$ ]]; then
    echo "The primary icon resource is not readable as an image: $icon_path" >&2
    exit 1
fi

echo "Verified primary app icon: $icon_path (${pixel_width}px representation)"
