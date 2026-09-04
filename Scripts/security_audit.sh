#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR=""

usage() {
  cat <<'USAGE'
Usage: ./Scripts/security_audit.sh [--artifacts PATH]

Scans the current source tree and all Git history without printing matched secret
values. When --artifacts is provided, also extracts and scans release ZIP files,
the .app bundle, and compiled executable paths.
USAGE
}

log() {
  printf '[security] %s\n' "$*"
}

die() {
  printf '[security] ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifacts)
      [[ $# -ge 2 ]] || die "--artifacts requires a path"
      ARTIFACTS_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git is required"
command -v grep >/dev/null 2>&1 || die "grep is required"

cd "$ROOT_DIR"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "Project is not a Git repository"

SECRET_RE='(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|sk-ant-(api|admin)-?[A-Za-z0-9_-]{12,}|sk-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+[A-Za-z0-9_./+=-]{12,})'
ABSOLUTE_PATH_RE='(/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/)'
SENSITIVE_FILE_RE='(^|/)(\.env($|\.)|credentials?\.json$|Cookies?$|History$|.*\.(pem|key|p8|p12|mobileprovision)$|id_(rsa|ed25519)$)'

report_file_matches() {
  local title="$1"
  local matches="$2"
  if [[ -n "$matches" ]]; then
    printf '[security] ERROR: %s\n' "$title" >&2
    printf '%s\n' "$matches" >&2
    return 1
  fi
  log "PASS: $title"
}

log "Scanning current source tree for secret patterns."
CURRENT_SECRET_FILES="$(
  grep -RIlE "$SECRET_RE" . \
    --exclude-dir=.git \
    --exclude-dir=.build \
    --exclude-dir=Build \
    2>/dev/null || true
)"
report_file_matches "no secret patterns in current source" "$CURRENT_SECRET_FILES"

log "Scanning all Git commits for secret patterns."
HISTORY_SECRET_FILES="$(
  while IFS= read -r commit; do
    git grep -Il -E "$SECRET_RE" "$commit" -- . 2>/dev/null || true
  done < <(git rev-list --all) \
    | sed 's/^[^:]*://' \
    | sort -u
)"
report_file_matches "no secret patterns in Git history" "$HISTORY_SECRET_FILES"

log "Scanning the current project for sensitive filenames."
CURRENT_SENSITIVE_FILES="$(
  find . \
    -path './.git' -prune -o \
    -path './.build' -prune -o \
    -path './Build' -prune -o \
    -type f -print \
    | grep -Ei "$SENSITIVE_FILE_RE" || true
)"
report_file_matches "no credential, key, cookie, or provisioning files" "$CURRENT_SENSITIVE_FILES"

log "Scanning all Git history for sensitive filenames."
HISTORY_SENSITIVE_FILES="$(
  git log --all --name-only --pretty=format: \
    | sort -u \
    | grep -Ei "$SENSITIVE_FILE_RE" || true
)"
report_file_matches "no sensitive filenames in Git history" "$HISTORY_SENSITIVE_FILES"

log "Scanning current public source for personal absolute paths."
CURRENT_ABSOLUTE_PATH_FILES="$(
  grep -RIlE "$ABSOLUTE_PATH_RE" . \
    --exclude-dir=.git \
    --exclude-dir=.build \
    --exclude-dir=Build \
    2>/dev/null || true
)"
report_file_matches "no personal absolute paths in current source" "$CURRENT_ABSOLUTE_PATH_FILES"

if [[ -n "$ARTIFACTS_DIR" ]]; then
  if [[ "$ARTIFACTS_DIR" != /* ]]; then
    ARTIFACTS_DIR="$ROOT_DIR/$ARTIFACTS_DIR"
  fi
  [[ -d "$ARTIFACTS_DIR" ]] || die "Artifacts directory not found: $ARTIFACTS_DIR"

  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-security-audit.XXXXXX")"
  trap 'rm -rf "$TEMP_DIR"' EXIT

  log "Extracting release ZIP files for artifact scanning."
  while IFS= read -r archive; do
    destination="$TEMP_DIR/$(basename "$archive" .zip)"
    mkdir -p "$destination"
    ditto -x -k "$archive" "$destination"
  done < <(find "$ARTIFACTS_DIR" -maxdepth 1 -type f -name '*.zip' -print)

  log "Scanning extracted release assets for secret patterns."
  ARTIFACT_SECRET_FILES="$(grep -RIlE "$SECRET_RE" "$TEMP_DIR" 2>/dev/null || true)"
  report_file_matches "no secret patterns in release assets" "$ARTIFACT_SECRET_FILES"

  log "Scanning extracted release assets for sensitive filenames."
  ARTIFACT_SENSITIVE_FILES="$(
    find "$TEMP_DIR" -type f -print \
      | grep -Ei "$SENSITIVE_FILE_RE" || true
  )"
  report_file_matches "no sensitive files in release assets" "$ARTIFACT_SENSITIVE_FILES"

  log "Scanning release source archives for personal absolute paths."
  ARTIFACT_ABSOLUTE_PATH_FILES="$(grep -RIlE "$ABSOLUTE_PATH_RE" "$TEMP_DIR" 2>/dev/null || true)"
  report_file_matches "no personal absolute paths in release assets" "$ARTIFACT_ABSOLUTE_PATH_FILES"

  log "Scanning compiled app binary strings for personal build paths."
  BINARY_PATH_FILES=""
  while IFS= read -r executable; do
    if strings "$executable" | grep -Eq "$ABSOLUTE_PATH_RE"; then
      BINARY_PATH_FILES+="${executable#$TEMP_DIR/}"$'\n'
    fi
  done < <(find "$TEMP_DIR" -type f -path '*/Contents/MacOS/AIUsageMonitor' -print)
  report_file_matches "no personal absolute paths in compiled binaries" "${BINARY_PATH_FILES%$'\n'}"
fi

log "SECURITY AUDIT PASSED"
