#!/usr/bin/env bash
set -euo pipefail

project_file="TimeClockBar.xcodeproj/project.pbxproj"
project_version="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$project_file" | head -n 1)"
latest_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || true)"

if [[ -n "$latest_tag" ]]; then
  base_version="${latest_tag#v}"
  commit_range="$latest_tag..HEAD"
else
  base_version="$project_version"
  commit_range="HEAD"
fi

IFS=. read -r major minor patch <<< "$base_version"
minor="${minor:-0}"
patch="${patch:-0}"
commit_messages="$(git log --format=%B "$commit_range" 2>/dev/null || true)"
subjects="$(git log --format=%s "$commit_range" 2>/dev/null || true)"
bump="none"

if grep -Eq '(^BREAKING CHANGE:|^[[:alpha:]]+(\([^)]+\))?!:)' <<< "$commit_messages"; then
  bump="major"
elif grep -Eq '^feat(\([^)]+\))?: ' <<< "$subjects"; then
  bump="minor"
elif grep -Eq '^(fix|perf)(\([^)]+\))?: ' <<< "$subjects"; then
  bump="patch"
fi

case "$bump" in
  major)
    echo "$((major + 1)).0.0"
    ;;
  minor)
    echo "$major.$((minor + 1)).0"
    ;;
  patch)
    echo "$major.$minor.$((patch + 1))"
    ;;
  *)
    echo "$base_version"
    ;;
esac
