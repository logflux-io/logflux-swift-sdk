#!/usr/bin/env bash
set -euo pipefail

# Publish LogFlux Swift SDK to a local public repository directory.
# Extracts sdks/swift/ from the monorepo, squashes into a single clean commit,
# and syncs to the local public repo.
#
# Usage:
#   ./scripts/publish.sh [--dry-run] [--tag v1.2.3] [--push]
#
# Prerequisites:
#   - git-filter-repo (brew install git-filter-repo)

SDK_PATH="sdks/swift"
DRY_RUN=false
PUSH=false
TAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --push) PUSH=true; shift ;;
        --tag) TAG="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

MONO_ROOT="$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)"
PUBLIC_DIR="$(dirname "$MONO_ROOT")/logflux-public/logflux-swift-sdk"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Cloning monorepo into temp dir..."
git clone --no-local "$MONO_ROOT" "$WORK_DIR/mono"
cd "$WORK_DIR/mono"

echo "==> Extracting $SDK_PATH with git-filter-repo..."
git filter-repo \
    --subdirectory-filter "$SDK_PATH" \
    --force

echo "==> Squashing into single commit..."
TREE="$(git log --format='%T' -1 HEAD)"
COMMIT_MSG="LogFlux Swift SDK"
if [ -n "$TAG" ]; then
    COMMIT_MSG="LogFlux Swift SDK $TAG"
fi
NEW_COMMIT="$(echo "$COMMIT_MSG" | git commit-tree "$TREE")"
git reset --hard "$NEW_COMMIT"

echo "==> Verifying clean state..."
if git log HEAD --format="%b%s" | grep -qiE "co-authored|claude|anthropic"; then
    echo "ERROR: Sensitive content in commit message"
    exit 1
fi

echo "==> Single squashed commit: $(git log --oneline -1)"

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "==> DRY RUN: would sync to $PUBLIC_DIR"
    echo "    Files:"
    ls -1
    if [ -n "$TAG" ]; then
        echo "    Would tag: $TAG"
    fi
    exit 0
fi

if [ -d "$PUBLIC_DIR/.git" ]; then
    echo "==> Updating existing public repo at $PUBLIC_DIR..."
    git remote add public "$PUBLIC_DIR"
    git push public main --force
else
    echo "==> Creating public repo at $PUBLIC_DIR..."
    mkdir -p "$PUBLIC_DIR"
    git clone --no-local "$WORK_DIR/mono" "$PUBLIC_DIR"
    cd "$PUBLIC_DIR"
    git remote remove origin 2>/dev/null || true
    git remote add origin git@github.com:logflux-io/logflux-swift-sdk.git
fi

cd "$PUBLIC_DIR"

if [ -n "$TAG" ]; then
    echo "==> Tagging $TAG..."
    git tag -a "$TAG" -m "Release $TAG" --force
fi

echo ""
echo "==> Done. Public repo at: $PUBLIC_DIR"
echo "    $(git log --oneline -1)"

if [ "$PUSH" = true ]; then
    echo "==> Pushing to GitHub..."
    git push origin main --force
    if [ -n "$TAG" ]; then
        git push origin "$TAG" --force
    fi
    echo "==> GitHub updated."
else
    echo ""
    echo "    To push to GitHub:"
    echo "      cd $PUBLIC_DIR"
    echo "      git push origin main --force"
    if [ -n "$TAG" ]; then
        echo "      git push origin $TAG"
    fi
fi
