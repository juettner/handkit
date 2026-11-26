#!/usr/bin/env bash
# Marks which commit a build of the Handkit app was made from. App/README.md
# has the whole routine; this is the part that is easy to get wrong by hand.
#
#   Tools/release.sh start [1.1]    before building: the next build number
#   Tools/release.sh finish         after uploading: tag it and push
#   Tools/release.sh last           what was released last, and what is waiting
#
# "start" checks that this repository is on a clean, up to date main, adds one
# to the build number (and sets the version, if one is given), and commits
# that here, on your machine only.
#
# "finish" tags that commit (app-1.1-b7: version, then build number) and
# pushes main and the tag.
#
# It never builds or uploads anything: that is Xcode's job.
#
# The tags P.S. puts on this repository (ios-1.1-b7, android-...) mark the
# HandKit commit a P.S. build was made against. These start with "app-", so
# the two never meet.
#
# For a Java person: "start" is `mvn versions:set` plus the commit, "finish"
# is the tag half of `mvn release:prepare`.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
pbxproj="$repo/App/Handkit.xcodeproj/project.pbxproj"

die() { echo "release: $*" >&2; exit 1; }

usage() { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

# The first value of a setting in the project file: the regex's first group.
one_value() {
  perl -ne 'if (/'"$1"'/) { print "$1\n"; exit }' "$pbxproj"
}

version() { one_value 'MARKETING_VERSION = ([^;]+);'; }
build()   { one_value 'CURRENT_PROJECT_VERSION = ([0-9]+);'; }

# The repository must be on main, with nothing uncommitted, and hold exactly
# what GitHub's main holds (plus, if a number is given, that many commits of
# its own: the one "start" made).
check_repo() {
  local ahead_allowed="${1:-0}"
  local branch
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  [ "$branch" = main ] || die "this is '$branch'. Releases are made from main."
  [ -z "$(git -C "$repo" status --porcelain)" ] \
    || die "there are changes that are not committed. Commit them or put them away first."
  git -C "$repo" fetch --quiet --tags origin main || die "could not reach GitHub"
  local behind ahead
  behind="$(git -C "$repo" rev-list --count HEAD..origin/main)"
  ahead="$(git -C "$repo" rev-list --count origin/main..HEAD)"
  [ "$behind" = 0 ] || die "this is $behind commit(s) behind GitHub's main. Pull first."
  [ "$ahead" -le "$ahead_allowed" ] \
    || die "there are $ahead commit(s) here that GitHub's main does not have. Push or merge them first."
}

start() {
  local new_version="${1:-}"
  if [ -n "$new_version" ]; then
    [[ "$new_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] \
      || die "'$new_version' is not a version. Give it as 1.1 or 1.1.2."
  fi
  check_repo

  local v b
  v="$(version)"
  b="$(build)"
  [ -n "$v" ] && [ -n "$b" ] || die "could not read the version and build number"
  v="${new_version:-$v}"
  b=$((b + 1))

  # Both of the project's configurations (Debug and Release) carry the numbers.
  V="$v" B="$b" perl -pi -e '
    s/(MARKETING_VERSION = )[^;]+;/$1$ENV{V};/;
    s/(CURRENT_PROJECT_VERSION = )[0-9]+;/$1$ENV{B};/' "$pbxproj"
  [ "$(version)" = "$v" ] && [ "$(build)" = "$b" ] \
    || die "the numbers did not take: look at 'git diff'"
  git -C "$repo" add "$pbxproj"
  git -C "$repo" commit --quiet -m "App: version $v, build $b"

  echo "Handkit is now version $v, build $b (committed here, not pushed)."
  echo
  echo "Next, in Xcode: Product > Archive, then Distribute App > TestFlight & App Store."
  echo "Once it is uploaded:   Tools/release.sh finish"
  echo "Changed your mind?     git reset --hard origin/main"
}

finish() {
  check_repo 1
  local tag
  tag="app-$(version)-b$(build)"
  if git -C "$repo" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    die "$tag is already a release. Run 'Tools/release.sh start' before building again."
  fi
  git -C "$repo" tag -a "$tag" -m "Handkit $(version), build $(build)"
  git -C "$repo" push --quiet origin main "$tag"
  echo "Tagged $tag ($(git -C "$repo" rev-parse --short HEAD)) and pushed."
}

last() {
  git -C "$repo" fetch --quiet --tags origin main || die "could not reach GitHub"
  local tag
  tag="$(git -C "$repo" tag --list 'app-*' --sort=-creatordate | head -n 1)"
  if [ -z "$tag" ]; then
    echo "Handkit: never released."
    return
  fi
  echo "Handkit: $tag, on $(git -C "$repo" log -1 --format=%ad --date=short "$tag")."
  echo "  On main since then, and not in that build:"
  # The app is App/ and the library it is built from.
  git -C "$repo" log --no-merges --format='    %h %s' "$tag..origin/main" -- App Sources Package.swift \
    | grep . || echo "    nothing"
}

case "${1:-}" in
  start)  shift; start "$@" ;;
  finish) finish ;;
  last)   last ;;
  *)      usage ;;
esac
