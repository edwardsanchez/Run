#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <app>" >&2
    exit 64
fi

source_app=$1
if [[ ! -d $source_app ]]; then
    echo "Missing application bundle: $source_app" >&2
    exit 1
fi

verification_suffix=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d -)
verification_parent="$HOME/Applications"
verification_root="$verification_parent/Run Open Verification $verification_suffix"
mkdir -p "$verification_parent"
mkdir "$verification_root"
if [[ $verification_root != "$verification_parent"/Run\ Open\ Verification\ * ]]; then
    echo "Unexpected verification directory: $verification_root" >&2
    exit 1
fi
verification_app="$verification_root/Run Verification.app"
verification_project="$verification_root/Finder Open.xcodeproj"
verification_bundle_id="app.amorfati.Run.CodexVerification.$verification_suffix"
lsregister_path=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

cleanup() {
    pkill -TERM -f "$verification_app/Contents/MacOS/Run" 2>/dev/null || true
    "$lsregister_path" -u "$verification_app" >/dev/null 2>&1 || true
    defaults delete "$verification_bundle_id" >/dev/null 2>&1 || true
    rm -rf -- "$verification_root"
}
trap cleanup EXIT

ditto "$source_app" "$verification_app"
mkdir "$verification_project"
plutil -replace CFBundleIdentifier -string "$verification_bundle_id" "$verification_app/Contents/Info.plist"
plutil -replace CFBundleName -string "Run Verification" "$verification_app/Contents/Info.plist"
codesign --force --deep --sign - "$verification_app" >/dev/null
"$lsregister_path" -f -R -trusted "$verification_app"

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift -e '
import Foundation
import CoreServices

let bundleID = CommandLine.arguments[1]
for type in ["com.apple.xcode.project", "com.apple.dt.document.workspace"] {
    let contentType = type as NSString as CFString
    let handlers = LSCopyAllRoleHandlersForContentType(contentType, .all)?.takeRetainedValue() as? [String] ?? []
    guard handlers.contains(bundleID) else {
        fatalError("Missing Launch Services handler for \(type): \(handlers)")
    }
}
' "$verification_bundle_id"

open -n -a "$verification_app" "$verification_project"
for _ in {1..40}; do
    if defaults read "$verification_bundle_id" recentProjects >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

opened_path=$(DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift -e '
import Foundation

struct Project: Decodable {
    let url: URL
}

let domain = CommandLine.arguments[1]
let defaults = UserDefaults(suiteName: domain)!
if let data = defaults.data(forKey: "recentProjects"),
   let project = try? JSONDecoder().decode([Project].self, from: data).first {
    print(project.url.path)
}
' "$verification_bundle_id")

if [[ $opened_path != "$verification_project" ]]; then
    echo "External open request was not recorded. Expected $verification_project, got $opened_path" >&2
    exit 1
fi

echo "Verified Launch Services registration and external project selection."
