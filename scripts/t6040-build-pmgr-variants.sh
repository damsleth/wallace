#!/usr/bin/env bash
# Build reproducible DockChannel-console DTBs for the PMGR isolations in
# NEXT_STEPS.md. This is host-side and only mutates the disposable kbuild
# container worktree plus artifacts under ~/Code/linux-build-out.
set -euo pipefail

ROOT=/Users/damsleth/Code/wallace
LINUX=/Users/damsleth/Code/linux
M1N1=/Users/damsleth/Code/m1n1
OUT=/Users/damsleth/Code/linux-build-out
BUILD_DIR=${BUILD_DIR:-/build/linux-keyboard}
APPLE=arch/arm64/boot/dts/apple
BRANCH=feature/m4-m5-minimal-device-trees
ADT_REF="$BRANCH:j614s.adt"
MODES=(
	raw
	core-infra-pruned
	pmgr1-reparent-only
	pmgr1-prune-only
)

tmp=$(mktemp -d "${TMPDIR:-/tmp}/t6040-pmgr-variants.XXXXXX")
cleanup() {
	# Leave the normal functional-policy source in the build cache.
	podman cp "$LINUX/$APPLE/t6040-pmgr.dtsi" \
		"kbuild:$BUILD_DIR/$APPLE/t6040-pmgr.dtsi" >/dev/null 2>&1 || true
	rm -rf "$tmp"
}
trap cleanup EXIT

# The committed t6040-pmgr.dtsi already carries the later functional policy,
# so it is not a raw baseline. Regenerate from the committed 606 KiB ADT and
# retain only the &pmgr sections; t6040.dtsi already defines the four syscons.
git -C "$LINUX" show "$ADT_REF" > "$tmp/j614s.adt"
PY="$M1N1/venv/bin/python"
[ -x "$PY" ] || PY=python3
"$PY" "$M1N1/proxyclient/tools/pmgr_adt2dt.py" --always-on critical \
	"$tmp/j614s.adt" \
	> "$tmp/pmgr-generated.dtsi"
sed -n '/^&pmgr0 {$/,$p' "$tmp/pmgr-generated.dtsi" \
	> "$tmp/t6040-pmgr-raw.dtsi"

if grep -qE 'apple,(preserve-active|skip-auto-enable)|status = "disabled"' \
	"$tmp/t6040-pmgr-raw.dtsi"; then
	echo "raw ADT regeneration unexpectedly contains functional policy" >&2
	exit 1
fi

for mode in "${MODES[@]}"; do
	name="t6040-j614s-dcuart-pmgr-${mode}"
	variant="$tmp/t6040-pmgr-${mode}.dtsi"
	board="$tmp/$name.dts"

	python3 "$ROOT/scripts/t6040-pmgr-variant.py" \
		"$mode" "$tmp/t6040-pmgr-raw.dtsi" "$variant"
	cp "$ROOT/dts/t6040-j614s-dcuart.dts" "$board"

	podman cp "$variant" "kbuild:$BUILD_DIR/$APPLE/t6040-pmgr.dtsi"
	podman cp "$board" "kbuild:$BUILD_DIR/$APPLE/$name.dts"
	podman exec kbuild bash -lc \
		"cd '$BUILD_DIR' && make ARCH=arm64 apple/$name.dtb && cp '$APPLE/$name.dtb' /out/"
	shasum -a 256 "$OUT/$name.dtb"
done

if cmp -s "$OUT/t6040-j614s-dcuart-pmgr-raw.dtb" \
	"$OUT/t6040-j614s-dcuart.dtb"; then
	echo "raw and functional-policy DTBs unexpectedly match" >&2
	exit 1
fi
