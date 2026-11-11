#!/usr/bin/env bash

set -euo pipefail

swift_selector_error() {
  echo "::error::$1" >&2
  return 1
}

swift_selector_version_is_compatible() {
  local version_output="$1"
  local version
  local major
  local minor

  version="$(sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+)([^[:space:]]*).*/\1.\2\3/p' <<< "$version_output" | head -n 1)"
  [[ -n "$version" ]] || return 1
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%[^0-9]*}"
  (( major > 6 || (major == 6 && minor >= 4) ))
}

swift_selector_read_identifier() {
  local toolchain="$1"
  local metadata

  for metadata in "$toolchain/ToolchainInfo.plist" "$toolchain/Info.plist"; do
    [[ -f "$metadata" ]] || continue
    if [[ -n "${SWIFT_SELECTOR_PLISTBUDDY:-}" ]]; then
      if [[ "$metadata" == */ToolchainInfo.plist ]]; then
        "$SWIFT_SELECTOR_PLISTBUDDY" -c 'Print :Identifier' "$metadata" 2>/dev/null && return 0
      fi
      "$SWIFT_SELECTOR_PLISTBUDDY" -c 'Print :CFBundleIdentifier' "$metadata" 2>/dev/null && return 0
    else
      if [[ "$metadata" == */ToolchainInfo.plist ]]; then
        /usr/libexec/PlistBuddy -c 'Print :Identifier' "$metadata" 2>/dev/null && return 0
      fi
      /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$metadata" 2>/dev/null && return 0
    fi
  done
  return 1
}

swift_selector_export_selection() {
  local selected_swift="$1"
  local selection_kind="$2"
  local selection_value="$3"

  printf 'Selected Swift toolchain (%s): %s\n' "$selection_kind" "$selection_value"
  "$selected_swift" --version
  export PATH="$(dirname "$selected_swift"):$PATH"

  if [[ "$selection_kind" == "Xcode" ]]; then
    unset TOOLCHAINS || true
    export DEVELOPER_DIR="$selection_value"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
      echo "DEVELOPER_DIR=$selection_value" >> "$GITHUB_ENV"
    fi
  else
    unset DEVELOPER_DIR || true
    export TOOLCHAINS="$selection_value"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
      echo "TOOLCHAINS=$selection_value" >> "$GITHUB_ENV"
    fi
  fi

  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$(dirname "$selected_swift")" >> "$GITHUB_PATH"
  fi
}

swift_selector_find_xcode() {
  local developer_dir
  local swift_binary
  local version_output
  local xcrun_command="${SWIFT_SELECTOR_XCRUN:-xcrun}"
  local found_swift

  for developer_dir in "${swift_selector_xcode_developers[@]:-}"; do
    [[ -d "$developer_dir" ]] || continue

    if ! found_swift="$(DEVELOPER_DIR="$developer_dir" "$xcrun_command" --find swift 2>/dev/null)"; then
      continue
    fi
    [[ -x "$found_swift" ]] || continue

    if ! version_output="$("$found_swift" --version 2>&1)" ||
      ! swift_selector_version_is_compatible "$version_output"; then
      continue
    fi

    swift_selector_export_selection "$found_swift" "Xcode" "$developer_dir"
    return 0
  done
  return 1
}

swift_selector_find_standalone() {
  local toolchain
  local swift_binary
  local identifier
  local version_output

  for toolchain in "${swift_selector_toolchains[@]:-}"; do
    swift_binary="$toolchain/usr/bin/swift"
    [[ -x "$swift_binary" ]] || continue
    identifier="$(swift_selector_read_identifier "$toolchain")" || continue

    if ! version_output="$("$swift_binary" --version 2>&1)" ||
      ! swift_selector_version_is_compatible "$version_output"; then
      continue
    fi

    swift_selector_export_selection "$swift_binary" "standalone" "$identifier"
    return 0
  done
  return 1
}

swift_selector_xcode_developers=()
swift_selector_toolchains=()

if [[ -n "${SWIFT_SELECTOR_XCODE_DEVELOPERS+x}" ]]; then
  IFS=: read -r -a swift_selector_xcode_developers <<< "$SWIFT_SELECTOR_XCODE_DEVELOPERS"
else
  swift_selector_xcode_developers=(/Applications/Xcode*.app/Contents/Developer)
fi

if [[ -n "${SWIFT_SELECTOR_TOOLCHAINS+x}" ]]; then
  IFS=: read -r -a swift_selector_toolchains <<< "$SWIFT_SELECTOR_TOOLCHAINS"
else
  swift_selector_toolchains=(
    /Library/Developer/Toolchains/*.xctoolchain
    "$HOME"/Library/Developer/Toolchains/*.xctoolchain
  )
fi

if swift_selector_find_xcode || swift_selector_find_standalone; then
  return 0 2>/dev/null || exit 0
fi

swift_selector_error "No installed macOS Swift toolchain compatible with Swift tools version 6.4 or later was found."
return 1 2>/dev/null || exit 1
