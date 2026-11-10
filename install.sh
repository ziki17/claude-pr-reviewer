#!/usr/bin/env bash
# Install the scripts to $PREFIX (default ~/.local/bin) and seed
# ~/.config/auto-pr-review/ without overwriting any existing file. On macOS,
# also render the launchd plists into ~/Library/LaunchAgents/ and print the
# commands that load them (it never runs launchctl itself).
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX="${PREFIX:-$HOME/.local/bin}"
CONF="$HOME/.config/auto-pr-review"
STATE="$HOME/.local/state/auto-pr-review"

mkdir -p "$PREFIX" "$CONF" "$STATE"
for f in "$SRC"/bin/*.sh; do
  install -m 755 "$f" "$PREFIX/"
done
echo "scripts -> $PREFIX"

seed() {  # seed <source> <dest>: copy only when dest does not exist
  if [[ -e "$2" ]]; then echo "keep     $2"; return; fi
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
  echo "created  $2"
}
seed "$SRC/config/config.example.sh" "$CONF/config.sh"
seed "$SRC/config/rubric.md" "$CONF/rubric.md"
seed "$SRC/config/schema.sql" "$CONF/schema.sql"
seed "$SRC/config/eval/labels.example.tsv" "$CONF/eval/labels.tsv"
for f in "$SRC"/config/rules/*; do seed "$f" "$CONF/rules/${f##*/}"; done
while IFS= read -r f; do seed "$f" "$CONF/repos/${f#"$SRC"/config/repos/}"; done \
  < <(find "$SRC/config/repos" -type f -name '*.md')

[[ "$(uname -s)" == Darwin ]] || exit 0

AGENTS="$HOME/Library/LaunchAgents"
mkdir -p "$AGENTS"
for t in "$SRC"/launchd/*.plist; do
  out="$AGENTS/${t##*/}"
  if [[ -e "$out" ]]; then
    out="$out.new"
    echo "exists   $AGENTS/${t##*/} (left alone; compare with ${out##*/})"
  fi
  sed -e "s#__PREFIX__#${PREFIX}#g" -e "s#__HOME__#${HOME}#g" "$t" > "$out"
  echo "rendered $out"
done
cat <<EOF

Next steps:
  1. Edit $CONF/config.sh (at least ORG).
  2. Try it: DRY_RUN=1 $PREFIX/auto-review-prs.sh; then NO_POST=1 (see README).
  3. Load the agents:
     launchctl bootstrap gui/$(id -u) $AGENTS/com.example.auto-pr-review.plist
     launchctl bootstrap gui/$(id -u) $AGENTS/com.example.auto-pr-review-digest.plist
EOF
