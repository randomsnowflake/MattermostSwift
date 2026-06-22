#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

secret_patterns='(token|secret|password|passwd|authorization|bearer|api[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret|credential|cookie)'
artifact_patterns='(\.env|\.log|\.png|\.jpe?g|\.gif|\.heic|\.mov|\.mp4|\.zip|\.tar|\.gz|\.sqlite|\.db|\.xcresult|\.build|\.mattermostswift)'

echo "== Current tree: sensitive words, URLs, emails =="
rg -n --hidden -i \
  -g '!/.git/**' \
  -g '!/.build/**' \
  -g '!/.swiftpm/**' \
  -g '!/.mattermostswift/**' \
  "$secret_patterns|https?://|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}" . || true

echo
echo "== Current tree: generated/private artifact filenames =="
find . \
  -path ./.git -prune -o \
  -path ./.build -prune -o \
  -path ./.swiftpm -prune -o \
  -path ./.mattermostswift -prune -o \
  -type f -print | rg -i "$artifact_patterns" || true

echo
echo "== Git history: generated/private artifact filenames =="
git log --all --full-history --name-only --pretty=format: | sort -u | rg -i "$artifact_patterns" || true

echo
echo "== Git history: non-placeholder URLs =="
git grep -n -I -E 'https?://[^ )"<>]+' $(git rev-list --all) -- . ':!.git' \
  | rg -v 'mattermost\.example\.com|example\.com|api\.mattermost\.com|developers\.mattermost\.com|github\.com/randomsnowflake/MattermostSwift\.git|localhost|127\.0\.0\.1' || true

echo
echo "== Git history: non-example emails =="
git grep -n -I -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' $(git rev-list --all) -- . ':!.git' \
  | rg -v 'example\.com' || true

echo
echo "== Git history: common token/key signatures =="
git grep -n -I -E 'xox[baprs]-[A-Za-z0-9-]+' $(git rev-list --all) -- . ':!.git' || true
git grep -n -I -E 'gh[pousr]_[A-Za-z0-9_]{20,}' $(git rev-list --all) -- . ':!.git' || true
git grep -n -I -E 'github_pat_[A-Za-z0-9_]{20,}' $(git rev-list --all) -- . ':!.git' || true
git grep -n -I -E 'AKIA[0-9A-Z]{16}' $(git rev-list --all) -- . ':!.git' || true
git grep -n -I -F 'BEGIN PRIVATE KEY' $(git rev-list --all) -- . ':!.git' || true
git grep -n -I -F 'BEGIN RSA PRIVATE KEY' $(git rev-list --all) -- . ':!.git' || true
git grep -n -I -F 'BEGIN OPENSSH PRIVATE KEY' $(git rev-list --all) -- . ':!.git' || true
