#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$tmp_dir"
git init -q
git config user.name "TimeClockBar Test"
git config user.email "timeclockbar@example.test"
mkdir -p TimeClockBar.xcodeproj
printf '\t\t\t\tMARKETING_VERSION = 1.0;\n' > TimeClockBar.xcodeproj/project.pbxproj

git add .
git commit -q -m "Initial commit"

actual="$("$repo_root/scripts/next-version.sh")"
test "$actual" = "1.0" || { echo "expected 1.0, got $actual"; exit 1; }

printf 'docs\n' > docs.txt
git add .
git commit -q -m "docs: Update README"
actual="$("$repo_root/scripts/next-version.sh")"
test "$actual" = "1.0" || { echo "expected 1.0, got $actual"; exit 1; }

printf 'fix\n' > fix.txt
git add .
git commit -q -m "fix: Repair timer display"
actual="$("$repo_root/scripts/next-version.sh")"
test "$actual" = "1.0.1" || { echo "expected 1.0.1, got $actual"; exit 1; }

git tag v1.0.1
printf 'feat\n' > feature.txt
git add .
git commit -q -m "feat(settings): Add option"
actual="$("$repo_root/scripts/next-version.sh")"
test "$actual" = "1.1.0" || { echo "expected 1.1.0, got $actual"; exit 1; }

git tag v1.1.0
printf 'breaking\n' > breaking.txt
git add .
git commit -q -m "refactor: Change storage" -m "BREAKING CHANGE: preferences reset"
actual="$("$repo_root/scripts/next-version.sh")"
test "$actual" = "2.0.0" || { echo "expected 2.0.0, got $actual"; exit 1; }

echo "next-version checks passed"
