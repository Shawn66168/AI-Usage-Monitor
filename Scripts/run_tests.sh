#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/verification"
mkdir -p "$BUILD_DIR"

COMMON_SOURCES=(
  "$ROOT_DIR/Sources/AIUsageMonitor/Models.swift"
  "$ROOT_DIR/Sources/AIUsageMonitor/UsageProvider.swift"
  "$ROOT_DIR/Sources/AIUsageMonitor/ProcessRunner.swift"
  "$ROOT_DIR/Sources/AIUsageMonitor/ClaudeProvider.swift"
)

printf '%s\n' '== Unit tests =='
swiftc \
  -warnings-as-errors \
  -swift-version 6 \
  -parse-as-library \
  "${COMMON_SOURCES[@]}" \
  "$ROOT_DIR/Sources/AIUsageMonitor/KeychainStore.swift" \
  "$ROOT_DIR/Tests/UnitTestsMain.swift" \
  -o "$BUILD_DIR/AIUsageUnitTests" \
  -framework SwiftUI \
  -framework Security
"$BUILD_DIR/AIUsageUnitTests"

printf '%s\n' '== App update tests =='
swiftc \
  -warnings-as-errors \
  -swift-version 6 \
  -parse-as-library \
  "$ROOT_DIR/Sources/AIUsageMonitor/AppUpdateStore.swift" \
  "$ROOT_DIR/Tests/UpdateTestsMain.swift" \
  -o "$BUILD_DIR/AppUpdateTests" \
  -framework Combine
"$BUILD_DIR/AppUpdateTests"

printf '%s\n' '== Live provider diagnostics =='
swiftc \
  -warnings-as-errors \
  -swift-version 6 \
  -parse-as-library \
  "${COMMON_SOURCES[@]}" \
  "$ROOT_DIR/Sources/AIUsageMonitor/CodexProvider.swift" \
  "$ROOT_DIR/Sources/AIUsageMonitor/AntigravityProvider.swift" \
  "$ROOT_DIR/Sources/AIUsageMonitor/KeychainStore.swift" \
  "$ROOT_DIR/Sources/AIUsageMonitor/AdminAPIProviders.swift" \
  "$ROOT_DIR/Tests/DiagnosticsMain.swift" \
  -o "$BUILD_DIR/AIUsageDiagnostics" \
  -framework SwiftUI \
  -framework Security
"$BUILD_DIR/AIUsageDiagnostics" | tee "$BUILD_DIR/diagnostics.json"

printf '%s\n' '== Full Swift 6 type and warning verification =='
swiftc \
  -O \
  -whole-module-optimization \
  -warnings-as-errors \
  -swift-version 6 \
  -parse-as-library \
  "$ROOT_DIR"/Sources/AIUsageMonitor/*.swift \
  -o "$BUILD_DIR/AIUsageMonitor" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework Security \
  -framework ServiceManagement \
  -framework UserNotifications

printf '%s\n' '== Privacy scan =='
if grep -RInE '(\.credentials\.json|Session Storage/(Cookies|Local Storage)|transcript_path|history\.jsonl|payload\.(message|content)|Authorization: Bearer [A-Za-z0-9_-]+)' "$ROOT_DIR/Sources" "$ROOT_DIR/Tests"; then
  echo 'Privacy scan failed.' >&2
  exit 1
fi

printf '%s\n' '== Repository security audit =='
bash "$ROOT_DIR/Scripts/security_audit.sh"

printf '%s\n' 'ALL TESTS PASSED'
