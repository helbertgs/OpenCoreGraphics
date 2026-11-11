#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fixtures="$root/Tests/ScriptFixtures/SwiftToolchainSelector"
temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT
fake_xcrun="$temporary_root/xcrun"
cp "$fixtures/xcrun" "$fake_xcrun"
chmod +x "$fake_xcrun"

make_xcode_fixture() {
  local xcode="$1"
  local swift_fixture="$2"
  mkdir -p "$xcode/usr/bin"
  cp "$fixtures/$swift_fixture" "$xcode/usr/bin/swift"
  chmod +x "$xcode/usr/bin/swift"
}

make_standalone_fixture() {
  local toolchain="$1"
  local swift_fixture="$2"
  local plist_fixture="$3"
  mkdir -p "$toolchain/usr/bin"
  cp "$fixtures/$swift_fixture" "$toolchain/usr/bin/swift"
  cp "$fixtures/$plist_fixture" "$toolchain/ToolchainInfo.plist"
  chmod +x "$toolchain/usr/bin/swift"
}

run_selector() {
  local xcodes="$1"
  local toolchains="$2"
  SWIFT_SELECTOR_XCODE_DEVELOPERS="$xcodes" \
    SWIFT_SELECTOR_TOOLCHAINS="$toolchains" \
    SWIFT_SELECTOR_XCRUN="$fake_xcrun" \
    bash -c 'source "$1"; printf "RESULT DEVELOPER_DIR=%s TOOLCHAINS=%s\n" "${DEVELOPER_DIR:-}" "${TOOLCHAINS:-}"' _ "$root/scripts/select-swift-toolchain.sh"
}

first_xcode="$temporary_root/Xcode-First/Contents/Developer"
second_xcode="$temporary_root/Xcode-Second/Contents/Developer"
make_xcode_fixture "$first_xcode" swift-6.3
make_xcode_fixture "$second_xcode" swift-6.5

output="$(run_selector "$first_xcode:$second_xcode" "")"
[[ "$output" == *"Xcode): $second_xcode"* ]] || {
  printf 'FAIL: did not continue from invalid Xcode candidate to valid second candidate\n%s\n' "$output" >&2
  exit 1
}
[[ "$output" == *"RESULT DEVELOPER_DIR=$second_xcode TOOLCHAINS="* ]] || {
  printf 'FAIL: selected Xcode DEVELOPER_DIR was not exported\n%s\n' "$output" >&2
  exit 1
}
[[ "$output" == *"Apple Swift version 6.5.0"* ]] || {
  printf 'FAIL: Swift 6.5 candidate was not accepted\n%s\n' "$output" >&2
  exit 1
}
printf 'PASS: invalid first Xcode candidate skipped; second Swift 6.5 candidate selected\n'

fourth_xcode="$temporary_root/Xcode-6.4/Contents/Developer"
make_xcode_fixture "$fourth_xcode" swift-6.4
output="$(run_selector "$fourth_xcode" "")"
[[ "$output" == *"Apple Swift version 6.4.0"* ]] || {
  printf 'FAIL: Swift 6.4 candidate was not accepted\n%s\n' "$output" >&2
  exit 1
}
printf 'PASS: Swift 6.4 minimum candidate accepted\n'

old_standalone="$temporary_root/Toolchain-6.3.xctoolchain"
new_standalone="$temporary_root/Toolchain-6.5.xctoolchain"
make_standalone_fixture "$old_standalone" swift-6.3 toolchain-6.3.plist
make_standalone_fixture "$new_standalone" swift-6.5 toolchain-6.5.plist
output="$(run_selector "" "$old_standalone:$new_standalone")"
[[ "$output" == *"standalone): fixture.swift.6.5"* ]] || {
  printf 'FAIL: did not continue from Swift 6.3 standalone to Swift 6.5\n%s\n' "$output" >&2
  exit 1
}
[[ "$output" == *"RESULT DEVELOPER_DIR= TOOLCHAINS=fixture.swift.6.5"* ]] || {
  printf 'FAIL: selected standalone toolchain was not exported\n%s\n' "$output" >&2
  exit 1
}
[[ "$output" == *"Apple Swift version 6.5.0"* ]] || {
  printf 'FAIL: Swift 6.5 standalone candidate was not accepted\n%s\n' "$output" >&2
  exit 1
}
printf 'PASS: Swift 6.3 standalone candidate rejected; Swift 6.5 candidate selected\n'

set +e
output="$(run_selector "$first_xcode" "$old_standalone" 2>&1)"
status=$?
set -e
if [[ "$status" -eq 0 ]]; then
  printf 'FAIL: selector accepted a host with only Swift 6.3\n%s\n' "$output" >&2
  exit 1
fi
[[ "$output" == *"No installed macOS Swift toolchain compatible"* ]] || {
  printf 'FAIL: missing-compatible-toolchain error was not explicit\n%s\n' "$output" >&2
  exit 1
}
printf 'PASS: no compatible toolchain fails explicitly when only Swift 6.3 is available\n'
