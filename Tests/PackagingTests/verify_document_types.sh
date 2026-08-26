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

if [[ ! -f $info_plist ]]; then
    echo "Missing application Info.plist: $info_plist" >&2
    exit 1
fi

document_types=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" "$info_plist")

for content_type in com.apple.xcode.project com.apple.dt.document.workspace; do
    if [[ $document_types != *"$content_type"* ]]; then
        echo "The application does not register $content_type." >&2
        exit 1
    fi
done

alternate_count=$(printf '%s\n' "$document_types" | grep -c 'LSHandlerRank = Alternate')
if [[ $alternate_count -ne 2 ]]; then
    echo "Expected both Xcode document types to be alternate handlers." >&2
    exit 1
fi

echo "Verified Finder Open With support for Xcode projects and workspaces."
