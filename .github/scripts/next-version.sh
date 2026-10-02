#!/usr/bin/env bash
# Prints the next release version from conventional commits since the latest vX.Y.Z tag.
# Output is key=value lines, safe to append to $GITHUB_OUTPUT.
#   fix, perf = patch | feat = minor | "!" or a BREAKING CHANGE footer = major
#   chore, docs, ci, test, refactor, style, build = no release
# The floating major tag (v1) never matches, only full vX.Y.Z tags do.
set -euo pipefail

TARGET=${1:-HEAD}

previous=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)
if [ -z "$previous" ]; then
  previous=v0.0.0
  range=$TARGET
else
  range="$previous..$TARGET"
fi

subject_pattern='^([a-z]+)(\([^)]*\))?(!)?: '
level=0 # 0 none, 1 patch, 2 minor, 3 major

for sha in $(git rev-list "$range"); do
  subject=$(git log -1 --format=%s "$sha")
  body=$(git log -1 --format=%b "$sha")

  if [[ $subject =~ $subject_pattern ]]; then
    type=${BASH_REMATCH[1]}
    bang=${BASH_REMATCH[3]}
    case $type in
      feat) commit_level=2 ;;
      fix | perf) commit_level=1 ;;
      *) commit_level=0 ;;
    esac
    if [ -n "$bang" ]; then commit_level=3; fi
  else
    commit_level=0
  fi

  if printf '%s\n' "$body" | grep -Eq '^BREAKING[ -]CHANGE: '; then commit_level=3; fi
  if [ "$commit_level" -gt "$level" ]; then level=$commit_level; fi
done

if [ "$level" -eq 0 ]; then
  echo "release=false"
  echo "previous=$previous"
  exit 0
fi

IFS=. read -r major minor patch <<<"${previous#v}"
case $level in
  3) bump="major"; major=$((major + 1)); minor=0; patch=0 ;;
  2) bump="minor"; minor=$((minor + 1)); patch=0 ;;
  *) bump="patch"; patch=$((patch + 1)) ;;
esac

echo "release=true"
echo "bump=$bump"
echo "previous=$previous"
echo "version=$major.$minor.$patch"
echo "major=$major"
