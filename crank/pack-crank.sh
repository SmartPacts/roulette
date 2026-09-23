#!/usr/bin/env bash
# pack-crank.sh — build, on the dev machine, the tarball that provision-roulette-crank.sh installs.
#
#     bash crank/pack-crank.sh <output-directory>
#
# A machine running a crank gets a tarball rather than a clone, so that what it runs is a named,
# checksummed artifact instead of whatever a working tree happened to hold. This is the only way
# one should be made. It packs COMMITTED BYTES ONLY — `git archive` of HEAD's
# crank tree, never the working tree — and refuses to run while anything under crank/ is
# modified or untracked, so a tarball can never carry an edit that is not in git. A COMMIT file
# holding HEAD's full 40-character id rides at the root of the archive, and the provisioner reads
# it back and prints it, so a machine can always say which commit it runs. The tracked node_modules
# symlink (a dev-machine convenience into devnet-harness) is left out: the host builds its own from
# package-lock.json.
#
# The archive is reproducible: every entry is stamped with HEAD's commit time, so packing the same
# commit twice gives the same bytes and the same sha256. Pass that sha256 to the provisioner.
set -euo pipefail

OUT_DIR="${1:?usage: pack-crank.sh <output-directory>}"
die() { printf '!! %s\n' "$*" >&2; exit 1; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this inside a checkout of this repository"
cd "$ROOT"
[ -f crank/roulette-crank.mjs ] || die "$ROOT does not look like this repository (no crank/roulette-crank.mjs)"

# Modified, staged, or untracked — any of them means the tarball would not match the commit.
dirty=$(git status --porcelain -- crank)
[ -z "$dirty" ] || die "crank/ is not clean; commit (or stash) first, the tarball carries committed bytes only:
$dirty"

HEAD_ID=$(git rev-parse HEAD)
SHORT=$(git rev-parse --short=12 HEAD)
STAMP="@$(git log -1 --format=%ct HEAD)"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/roulette-crank-$SHORT.tar.gz"
[ ! -e "$OUT" ] || die "$OUT already exists — remove it yourself if you mean to rebuild it"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$HEAD_ID" > "$tmp/COMMIT"
git archive --format=tar.gz --mtime="$STAMP" --add-file="$tmp/COMMIT" -o "$OUT" HEAD:crank -- . ':!node_modules'

echo "packed   $OUT"
echo "commit   $HEAD_ID"
echo "contents"; tar -tzf "$OUT" | sed 's/^/           /'
echo
echo "sha256   $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "Copy the tarball to the machine, then on the machine — CHECK THE CHECKSUM FIRST, before anything"
echo "is extracted from it (the script inside a tampered tarball would otherwise run as root before"
echo "it could check anything):"
echo "    echo \"<that sha256>  $(basename "$OUT")\" | sha256sum -c"
echo "    tar -xzf $(basename "$OUT") provision-roulette-crank.sh"
echo "    bash provision-roulette-crank.sh $(basename "$OUT") <that sha256>"
