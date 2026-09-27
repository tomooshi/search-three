#!/bin/bash
# install.sh — install the four skills into an agent's skills directory.
#
# Only needed if you are NOT using a plugin/package manager:
#   Claude Code:  /plugin marketplace add tomooshi/search-three
#                 /plugin install search-three@search-three
#   pi:           pi install git:github.com/tomooshi/search-three
#
# Usage:
#   ./install.sh [--copy] [--force] TARGET
#
# TARGET is a preset or any directory:
#   claude   → ~/.claude/skills
#   pi       → ~/.pi/agent/skills
#   agents   → ~/.agents/skills   (shared dir read by pi, Codex, and others)
#   codex    → ~/.codex/skills
#   /any/dir → that directory
#
# Default is to SYMLINK each skill (so `git pull` in this repo updates them).
# --copy   copy instead of symlinking
# --force  replace existing skills with the same names
#
# The four skills must stay side by side in the same directory — web-research
# calls the engine skills' scripts through ../<skill>/scripts.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=(web-research kagi-search exa-search marginalia-search)
MODE=link
FORCE=""

while [ $# -gt 0 ]; do
	case "$1" in
	--copy) MODE=copy ;;
	--force) FORCE=1 ;;
	-h | --help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	-*) echo "Unknown option: $1" >&2; exit 2 ;;
	*) TARGET="$1" ;;
	esac
	shift
done

case "${TARGET:-}" in
"") echo "Usage: ./install.sh [--copy] [--force] claude|pi|agents|codex|/path/to/skills" >&2; exit 2 ;;
claude) DEST="$HOME/.claude/skills" ;;
pi) DEST="$HOME/.pi/agent/skills" ;;
agents) DEST="$HOME/.agents/skills" ;;
codex) DEST="$HOME/.codex/skills" ;;
*) DEST="$TARGET" ;;
esac

mkdir -p "$DEST"
chmod +x "$REPO"/skills/*/scripts/*.sh "$REPO"/skills/*/scripts/*.py 2>/dev/null || true

for s in "${SKILLS[@]}"; do
	dst="$DEST/$s"
	if [ -e "$dst" ] || [ -L "$dst" ]; then
		if [ -L "$dst" ] && [ "$(cd "$dst" && pwd -P)" = "$(cd "$REPO/skills/$s" && pwd -P)" ] && [ "$MODE" = link ]; then
			echo "  = $s (already linked)"
			continue
		fi
		if [ -z "$FORCE" ]; then
			echo "  ✗ $dst already exists — rerun with --force to replace it" >&2
			exit 1
		fi
		rm -rf "$dst"
	fi
	if [ "$MODE" = link ]; then
		ln -s "$REPO/skills/$s" "$dst"
		echo "  → linked $s"
	else
		cp -R "$REPO/skills/$s" "$dst"
		echo "  → copied $s"
	fi
done

echo
echo "Installed to $DEST. Next:"
echo "  1. Add API keys (see README → API keys)"
echo "  2. Check setup: $DEST/web-research/scripts/doctor.sh"
