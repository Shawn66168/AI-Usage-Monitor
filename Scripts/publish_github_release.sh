#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
APP_NAME="AI Usage Monitor"

REPO=""
VERSION=""
BUILD_NUMBER=""
NOTES_FILE="$ROOT_DIR/RELEASE_NOTES.md"
CREATE_REPO=false
VISIBILITY="private"
DRAFT=false
PRERELEASE=false
SKIP_TESTS=false
DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage:
  ./Scripts/publish_github_release.sh \
    --repo OWNER/REPOSITORY \
    --version X.Y.Z \
    [options]

Required:
  --repo OWNER/REPOSITORY   GitHub repository. Must be passed explicitly.
  --version X.Y.Z           Release version without the leading "v".

Options:
  --build-number N          CFBundleVersion. Defaults to the Git commit count.
  --notes-file PATH         Markdown release notes. Defaults to RELEASE_NOTES.md.
  --create-repo             Create the repository if it does not exist.
  --visibility VALUE        Repository visibility for --create-repo: private or public.
                            Defaults to private.
  --draft                   Create a draft GitHub Release.
  --prerelease              Mark the GitHub Release as a prerelease.
  --skip-tests              Skip Scripts/run_tests.sh (not recommended).
  --dry-run                 Build and validate locally, but do not create/push/publish.
  -h, --help                Show this help message.

Examples:
  ./Scripts/publish_github_release.sh \
    --repo Shawn66168/AI-Usage-Monitor \
    --version 0.1.1 \
    --create-repo \
    --dry-run

  ./Scripts/publish_github_release.sh \
    --repo Shawn66168/AI-Usage-Monitor \
    --version 0.1.1 \
    --create-repo
USAGE
}

log() {
  printf '[release] %s\n' "$*"
}

warn() {
  printf '[release] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[release] ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

run_remote_mutation() {
  if "$DRY_RUN"; then
    printf '[release] DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      REPO="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || die "--version requires a value"
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || die "--build-number requires a value"
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --notes-file)
      [[ $# -ge 2 ]] || die "--notes-file requires a value"
      NOTES_FILE="$2"
      shift 2
      ;;
    --create-repo)
      CREATE_REPO=true
      shift
      ;;
    --visibility)
      [[ $# -ge 2 ]] || die "--visibility requires a value"
      VISIBILITY="$2"
      shift 2
      ;;
    --draft)
      DRAFT=true
      shift
      ;;
    --prerelease)
      PRERELEASE=true
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac
done

[[ -n "$REPO" ]] || die "--repo is required; the script never infers a release repository"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
  || die "Invalid --repo value: $REPO (expected OWNER/REPOSITORY)"

[[ -n "$VERSION" ]] || die "--version is required"
[[ ! "$VERSION" =~ ^v ]] || die "Pass --version without the v prefix (example: 0.1.1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
  || die "Invalid version: $VERSION (expected SemVer such as 0.1.1 or 1.0.0-beta.1)"

[[ "$VISIBILITY" == "private" || "$VISIBILITY" == "public" ]] \
  || die "--visibility must be private or public"

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || true)"
fi
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] \
  || die "Invalid build number: $BUILD_NUMBER (expected a positive integer)"

if [[ "$NOTES_FILE" != /* ]]; then
  NOTES_FILE="$ROOT_DIR/$NOTES_FILE"
fi
[[ -f "$NOTES_FILE" ]] || die "Release notes file not found: $NOTES_FILE"
[[ -s "$NOTES_FILE" ]] || die "Release notes file is empty: $NOTES_FILE"
grep -F "$VERSION" "$NOTES_FILE" >/dev/null 2>&1 \
  || die "Release notes do not mention version $VERSION: $NOTES_FILE"

require_command git
require_command gh
require_command swiftc
require_command codesign
require_command plutil
require_command ditto
require_command shasum

cd "$ROOT_DIR"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "Project is not a Git repository: $ROOT_DIR"

CURRENT_BRANCH="$(git branch --show-current)"
[[ -n "$CURRENT_BRANCH" ]] || die "Detached HEAD is not supported for a release"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  die "Working tree is not clean. Commit or stash all changes before publishing."
fi

HEAD_SHA="$(git rev-parse HEAD)"
TAG="v$VERSION"
TARGET_GIT_URL="git@github.com:$REPO.git"

log "Repository: $REPO"
log "Branch: $CURRENT_BRANCH"
log "Commit: $HEAD_SHA"
log "Version: $VERSION (build $BUILD_NUMBER)"
log "Tag: $TAG"
log "Release notes: $NOTES_FILE"
log "Mode: $(if "$DRY_RUN"; then echo 'dry run'; else echo 'publish'; fi)"

gh auth status -h github.com >/dev/null 2>&1 \
  || die "GitHub CLI is not authenticated. Run: gh auth login"

REPO_EXISTS=false
if gh repo view "$REPO" --json nameWithOwner >/dev/null 2>&1; then
  REPO_EXISTS=true
  ACTUAL_REPO="$(gh repo view "$REPO" --json nameWithOwner --jq .nameWithOwner)"
  [[ "$ACTUAL_REPO" == "$REPO" ]] \
    || die "Repository identity mismatch: requested $REPO, resolved $ACTUAL_REPO"
  log "Verified existing GitHub repository: $ACTUAL_REPO"
else
  "$CREATE_REPO" \
    || die "GitHub repository $REPO does not exist or is inaccessible. Create it first or add --create-repo."
  log "Repository does not exist; it will be created as $VISIBILITY."
fi

if "$REPO_EXISTS" && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  die "GitHub Release $TAG already exists in $REPO. Refusing to overwrite an existing release."
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  LOCAL_TAG_SHA="$(git rev-list -n 1 "$TAG")"
  [[ "$LOCAL_TAG_SHA" == "$HEAD_SHA" ]] \
    || die "Local tag $TAG points to $LOCAL_TAG_SHA, not current HEAD $HEAD_SHA"
  log "Local tag $TAG already points to current HEAD."
fi

if "$REPO_EXISTS"; then
  REMOTE_TAG_SHA="$(git ls-remote "$TARGET_GIT_URL" "refs/tags/$TAG^{}" | awk 'NR == 1 { print $1 }')"
  if [[ -z "$REMOTE_TAG_SHA" ]]; then
    REMOTE_TAG_SHA="$(git ls-remote "$TARGET_GIT_URL" "refs/tags/$TAG" | awk 'NR == 1 { print $1 }')"
  fi
  if [[ -n "$REMOTE_TAG_SHA" && "$REMOTE_TAG_SHA" != "$HEAD_SHA" ]]; then
    die "Remote tag $TAG points to $REMOTE_TAG_SHA, not current HEAD $HEAD_SHA"
  fi
fi

if ! "$SKIP_TESTS"; then
  log "Running unit, provider, compiler, privacy, and secret tests."
  "$ROOT_DIR/Scripts/run_tests.sh"
else
  warn "Tests were skipped by explicit request."
fi

log "Building the signed macOS app bundle."
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" "$ROOT_DIR/Scripts/build_app.sh"

APP_ZIP="$BUILD_DIR/AI-Usage-Monitor-macOS-arm64-v$VERSION.zip"
SOURCE_ZIP="$BUILD_DIR/AI-Usage-Monitor-Source-v$VERSION.zip"
CHECKSUMS_FILE="$BUILD_DIR/SHA256SUMS-v$VERSION.txt"

[[ -s "$APP_ZIP" ]] || die "App archive was not created: $APP_ZIP"

log "Creating source archive from committed HEAD."
rm -f "$SOURCE_ZIP" "$CHECKSUMS_FILE"
git archive \
  --format=zip \
  --prefix="AI-Usage-Monitor-$TAG/" \
  --output="$SOURCE_ZIP" \
  HEAD

(
  cd "$BUILD_DIR"
  shasum -a 256 \
    "$(basename "$APP_ZIP")" \
    "$(basename "$SOURCE_ZIP")" \
    > "$(basename "$CHECKSUMS_FILE")"
)

[[ -s "$SOURCE_ZIP" ]] || die "Source archive was not created: $SOURCE_ZIP"
[[ -s "$CHECKSUMS_FILE" ]] || die "Checksum file was not created: $CHECKSUMS_FILE"

log "Release assets:"
ls -lh "$APP_ZIP" "$SOURCE_ZIP" "$CHECKSUMS_FILE"
cat "$CHECKSUMS_FILE"

log "Running final security audit against source history and this release's assets."
(
  AUDIT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-usage-release-assets.XXXXXX")"
  trap 'rm -rf "$AUDIT_DIR"' EXIT
  cp "$APP_ZIP" "$SOURCE_ZIP" "$AUDIT_DIR/"
  bash "$ROOT_DIR/Scripts/security_audit.sh" --artifacts "$AUDIT_DIR"
)

if "$DRY_RUN"; then
  log "Dry run completed. No repository, branch, tag, or GitHub Release was changed."
  if ! "$REPO_EXISTS"; then
    run_remote_mutation gh repo create "$REPO" "--$VISIBILITY" \
      --description "Native macOS menu bar app for monitoring AI usage, quotas, tokens, context, and reset times."
  fi
  run_remote_mutation git push "$TARGET_GIT_URL" "HEAD:refs/heads/$CURRENT_BRANCH"
  if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    run_remote_mutation git tag -a "$TAG" -m "$APP_NAME $TAG"
  fi
  run_remote_mutation git push "$TARGET_GIT_URL" "refs/tags/$TAG"
  RELEASE_PREVIEW=(
    gh release create "$TAG"
    "$APP_ZIP#macOS Apple Silicon App"
    "$SOURCE_ZIP#Source Code"
    "$CHECKSUMS_FILE#SHA-256 Checksums"
    --repo "$REPO"
    --verify-tag
    --fail-on-no-commits
    --title "$APP_NAME $TAG"
    --notes-file "$NOTES_FILE"
  )
  "$DRAFT" && RELEASE_PREVIEW+=(--draft)
  if "$PRERELEASE" || [[ "$VERSION" == *-* ]]; then
    RELEASE_PREVIEW+=(--prerelease)
  fi
  run_remote_mutation "${RELEASE_PREVIEW[@]}"
  exit 0
fi

if ! "$REPO_EXISTS"; then
  log "Creating $VISIBILITY GitHub repository $REPO."
  gh repo create "$REPO" "--$VISIBILITY" \
    --description "Native macOS menu bar app for monitoring AI usage, quotas, tokens, context, and reset times."
fi

log "Pushing current branch to the explicit target repository."
git push "$TARGET_GIT_URL" "HEAD:refs/heads/$CURRENT_BRANCH"

if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  log "Creating annotated local tag $TAG."
  git tag -a "$TAG" -m "$APP_NAME $TAG"
fi

REMOTE_TAG_SHA="$(git ls-remote "$TARGET_GIT_URL" "refs/tags/$TAG^{}" | awk 'NR == 1 { print $1 }')"
if [[ -z "$REMOTE_TAG_SHA" ]]; then
  REMOTE_TAG_SHA="$(git ls-remote "$TARGET_GIT_URL" "refs/tags/$TAG" | awk 'NR == 1 { print $1 }')"
fi

if [[ -z "$REMOTE_TAG_SHA" ]]; then
  log "Pushing tag $TAG."
  git push "$TARGET_GIT_URL" "refs/tags/$TAG"
elif [[ "$REMOTE_TAG_SHA" == "$HEAD_SHA" ]]; then
  log "Remote tag $TAG already points to current HEAD; continuing."
else
  die "Remote tag $TAG changed during publishing; aborting."
fi

RELEASE_COMMAND=(
  gh release create "$TAG"
  "$APP_ZIP#macOS Apple Silicon App"
  "$SOURCE_ZIP#Source Code"
  "$CHECKSUMS_FILE#SHA-256 Checksums"
  --repo "$REPO"
  --verify-tag
  --fail-on-no-commits
  --title "$APP_NAME $TAG"
  --notes-file "$NOTES_FILE"
)

"$DRAFT" && RELEASE_COMMAND+=(--draft)
if "$PRERELEASE" || [[ "$VERSION" == *-* ]]; then
  RELEASE_COMMAND+=(--prerelease)
fi

log "Creating GitHub Release $TAG."
"${RELEASE_COMMAND[@]}"

RELEASE_URL="$(gh release view "$TAG" --repo "$REPO" --json url --jq .url)"
log "Published successfully: $RELEASE_URL"
