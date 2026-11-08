#!/bin/sh
# Build the image from this branch.
# Usage: custom/build.sh wg2600hp [make options, e.g. -j8]
#
# 1. feeds: feeds.conf.default of this tree, which pins every feed to a
#    fixed commit; check that the checked-out feeds match
# 2. files overlay (custom/files/<device>) and config (custom/configs/<device>.config)
# 3. make download && make
set -e
DEV=${1:?usage: custom/build.sh wg2600hp [make options]}
shift
TOP=$(cd "$(dirname "$0")/.." && pwd)
C=$TOP/custom
[ -f "$C/configs/$DEV.config" ] || { echo "unknown device: $DEV" >&2; exit 1; }
cd "$TOP"

# The prerequisite checks parse English tool output.
export LC_ALL=C LANG=C

while read -r kind name url; do
	case "$kind $url" in
	"src-git "*^[0-9a-f]*) ;;
	*) echo "feed not pinned to a commit: $kind $name $url" >&2; exit 1 ;;
	esac
done < feeds.conf.default
cp feeds.conf.default feeds.conf
./scripts/feeds update -a
while read -r kind name url; do
	[ "$(git -C "feeds/$name" rev-parse HEAD)" = "${url##*^}" ] || {
		echo "feed $name is not at ${url##*^}" >&2; exit 1; }
done < feeds.conf
./scripts/feeds install -a

rm -rf files
[ ! -d "$C/files/$DEV" ] || cp -a "$C/files/$DEV" files

cp "$C/configs/$DEV.config" .config
make defconfig
cmp -s .config "$C/configs/$DEV.config" || echo "WARNING: make defconfig changed .config" >&2

make download "$@"
make "$@"
ls -l bin/targets/ipq806x/generic/*"$DEV"*
