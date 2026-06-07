#!/usr/bin/env bash
# Generate a Conventional-Commits-style changelog between two git refs.
# Usage: changelog.sh <PREV_TAG> <NEW_TAG>
# Output: markdown to stdout.
set -euo pipefail
IFS=$'\n\t'

prev="${1:?usage: changelog.sh PREV_TAG NEW_TAG}"
new="${2:?usage: changelog.sh PREV_TAG NEW_TAG}"

# Resolve repo slug for the compare URL. GITHUB_REPOSITORY is set in
# Actions; outside of CI we parse the origin remote.
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  repo="$GITHUB_REPOSITORY"
else
  origin="$(git config --get remote.origin.url || true)"
  repo="$(printf '%s' "$origin" | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#')"
fi

# Bucket helper. Pattern is a regex applied against `<sha> <subject>`.
print_bucket() {
  local title="$1"
  local pattern="$2"
  local lines
  lines="$(git log --no-merges --pretty=format:'%h %s' "$prev..$new" | grep -E "$pattern" || true)"
  if [ -n "$lines" ]; then
    printf '\n### %s\n\n' "$title"
    printf '%s\n' "$lines" | sed 's/^/- /'
  fi
}

printf "## What's changed in %s\n" "$new"

print_bucket "Features" '^[0-9a-f]+ feat(\([^)]*\))?!?:'
print_bucket "Fixes"    '^[0-9a-f]+ fix(\([^)]*\))?!?:'
print_bucket "Chores"   '^[0-9a-f]+ (chore|build|ci|docs|test|refactor|perf|style)(\([^)]*\))?!?:'

others="$(git log --no-merges --pretty=format:'%h %s' "$prev..$new" \
  | grep -Ev '^[0-9a-f]+ (feat|fix|chore|build|ci|docs|test|refactor|perf|style)(\([^)]*\))?!?:' || true)"
if [ -n "$others" ]; then
  printf '\n### Other\n\n'
  printf '%s\n' "$others" | sed 's/^/- /'
fi

if [ -n "$repo" ]; then
  printf '\n**Full diff:** https://github.com/%s/compare/%s...%s\n' "$repo" "$prev" "$new"
fi
