#!/usr/bin/env bash
# Build reproducible DockChannel-console DTBs for the PMGR isolations in
# docs/NEXT_STEPS.md. This is host-side and only mutates the disposable kbuild
# container worktree plus artifacts under ~/code/linux-build-out.
set -euo pipefail

ROOT=/Users/damsleth/code/wallace
LINUX=/Users/damsleth/code/linux
M1N1=/Users/damsleth/code/m1n1
OUT=/Users/damsleth/code/linux-build-out
BUILD_DIR=${BUILD_DIR:-/build/linux-keyboard}
APPLE=arch/arm64/boot/dts/apple
BRANCH=feature/m4-m5-minimal-device-trees
ADT_REF="$BRANCH:j614s.adt"
SPECS=(
	"raw:raw:all:legacy:none"
	"no-always-on:raw:all:none:none"
	"preserve-active:raw:all:legacy:preserve"
	"preserve-pmgr1:raw:all:legacy:preserve-pmgr1"
	"preserve-dispext:raw:all:legacy:preserve-dispext"
	"preserve-dispext-ane:raw:all:legacy:preserve-dispext-ane"
	"preserve-dispext-disp:raw:all:legacy:preserve-dispext-disp"
	"minimal-dispext0:raw:all:legacy:preserve-disp-dispext0"
	"minimal-dispext1:raw:all:legacy:preserve-disp-dispext1"
	"minimal-no-sys:raw:all:legacy:preserve-disp-no-sys"
	"minimal-no-fe:raw:all:legacy:preserve-disp-no-fe"
	"minimal-no-cpu:raw:all:legacy:preserve-disp-no-cpu"
	"minimal-cpu-only:raw:all:legacy:preserve-disp-cpu-only"
	"restricted-domains:raw:all:legacy:restricted"
	"functional-policy:raw:all:legacy:functional"
	"core-infra-pruned:core-infra-pruned:all:legacy:none"
	"pmgr01:raw:pmgr01:legacy:none"
	"pmgr012:raw:pmgr012:legacy:none"
	"pmgr013:raw:pmgr013:legacy:none"
	"pmgr012-preserve:raw:pmgr012:legacy:preserve"
	"pmgr012-functional:raw:pmgr012:legacy:functional"
	"pmgr013-preserve:raw:pmgr013:legacy:preserve"
	"pmgr013-functional:raw:pmgr013:legacy:functional"
	"pmgr1-reparent-only:pmgr1-reparent-only:pmgr01:legacy:none"
	"pmgr1-prune-only:pmgr1-prune-only:pmgr01:legacy:none"
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
	> "$tmp/pmgr-generated-legacy.dtsi"
"$PY" "$M1N1/proxyclient/tools/pmgr_adt2dt.py" "$tmp/j614s.adt" \
	> "$tmp/pmgr-generated-none.dtsi"
sed -n '/^&pmgr0 {$/,$p' "$tmp/pmgr-generated-legacy.dtsi" \
	> "$tmp/t6040-pmgr-legacy.dtsi"
sed -n '/^&pmgr0 {$/,$p' "$tmp/pmgr-generated-none.dtsi" \
	> "$tmp/t6040-pmgr-none.dtsi"

if grep -qE 'apple,(preserve-active|skip-auto-enable)|status = "disabled"' \
	"$tmp/t6040-pmgr-legacy.dtsi"; then
	echo "raw ADT regeneration unexpectedly contains functional policy" >&2
	exit 1
fi

for spec in "${SPECS[@]}"; do
	IFS=: read -r name_suffix mode controllers always_on policy <<< "$spec"
	name="t6040-j614s-dcuart-pmgr-${name_suffix}"
	variant="$tmp/t6040-pmgr-${name_suffix}.dtsi"
	board="$tmp/$name.dts"

	python3 "$ROOT/scripts/t6040-pmgr-variant.py" \
		"$mode" "$tmp/t6040-pmgr-${always_on}.dtsi" "$variant"
	cp "$ROOT/dts/t6040-j614s-dcuart.dts" "$board"
	if [ "$controllers" != all ]; then
		{
			echo
			echo "/* Controller isolation: $controllers. */"
			case "$controllers" in
			pmgr01)
				echo '&pmgr2 { status = "disabled"; };'
				echo '&pmgr3 { status = "disabled"; };'
				;;
			pmgr012)
				echo '&pmgr3 { status = "disabled"; };'
				;;
			pmgr013)
				echo '&pmgr2 { status = "disabled"; };'
				;;
			esac
		} >> "$board"
	fi
	if [[ "$policy" = preserve* ]] || [ "$policy" = functional ]; then
		{
			echo
			echo '/* Preserve firmware-active domains on raw-boot machines. */'
			for controller in 0 1 2 3; do
				echo "&pmgr$controller { apple,preserve-active; };"
			done
		} >> "$board"
	fi
	if [ "$policy" = restricted ] || [ "$policy" = functional ] || \
	   [ "$policy" = preserve-pmgr1 ] || \
	   [ "$policy" = preserve-dispext-ane ]; then
		cat >> "$board" <<'EOF'

/* Firmware-owned ANE domains that reject raw-boot PMGR operations. */
&ps_ane_sys { apple,skip-auto-enable; status = "disabled"; };
&ps_ane_mpm { apple,skip-auto-enable; status = "disabled"; };
&ps_ane_cpu { apple,skip-auto-enable; status = "disabled"; };
&ps_ane_td { apple,skip-auto-enable; status = "disabled"; };
&ps_ane_base { apple,skip-auto-enable; status = "disabled"; };
EOF
	fi
	if [ "$policy" = restricted ] || [ "$policy" = functional ] || \
	   [ "$policy" = preserve-pmgr1 ] || \
	   [ "$policy" = preserve-dispext-disp ] || \
	   [ "$policy" = preserve-disp-dispext0 ] || \
	   [ "$policy" = preserve-disp-dispext1 ] || \
	   [ "$policy" = preserve-disp-no-sys ] || \
	   [ "$policy" = preserve-disp-no-fe ] || \
	   [ "$policy" = preserve-disp-no-cpu ] || \
	   [ "$policy" = preserve-disp-cpu-only ]; then
		cat >> "$board" <<'EOF'

/* Firmware-owned PMGR1 display CPU domain. */
&ps_disp_cpu { status = "disabled"; };
EOF
	fi
	if [ "$policy" = restricted ] || [ "$policy" = functional ] || \
	   [ "$policy" = preserve-dispext ] || \
	   [ "$policy" = preserve-dispext-ane ] || \
	   [ "$policy" = preserve-dispext-disp ] || \
	   [ "$policy" = preserve-disp-dispext0 ]; then
		cat >> "$board" <<'EOF'

/* PMGR2 display-ext0 domains whose auto-enable writes are unsupported. */
&ps_dispext0_sys { apple,skip-auto-enable; };
&ps_dispext0_fe { apple,skip-auto-enable; };
&ps_dispext0_cpu { apple,skip-auto-enable; };
EOF
	fi
	if [ "$policy" = restricted ] || [ "$policy" = functional ] || \
	   [ "$policy" = preserve-dispext ] || \
	   [ "$policy" = preserve-dispext-ane ] || \
	   [ "$policy" = preserve-dispext-disp ] || \
	   [ "$policy" = preserve-disp-dispext1 ]; then
		cat >> "$board" <<'EOF'

/* PMGR2 display-ext1 domains whose auto-enable writes are unsupported. */
&ps_dispext1_sys { apple,skip-auto-enable; };
&ps_dispext1_fe { apple,skip-auto-enable; };
&ps_dispext1_cpu { apple,skip-auto-enable; };
EOF
	fi
	if [ "$policy" = preserve-disp-no-sys ]; then
		cat >> "$board" <<'EOF'

/* Minimal-policy necessity test: no sys skips. */
&ps_dispext0_fe { apple,skip-auto-enable; };
&ps_dispext0_cpu { apple,skip-auto-enable; };
&ps_dispext1_fe { apple,skip-auto-enable; };
&ps_dispext1_cpu { apple,skip-auto-enable; };
EOF
	fi
	if [ "$policy" = preserve-disp-no-fe ]; then
		cat >> "$board" <<'EOF'

/* Minimal-policy necessity test: no fe skips. */
&ps_dispext0_sys { apple,skip-auto-enable; };
&ps_dispext0_cpu { apple,skip-auto-enable; };
&ps_dispext1_sys { apple,skip-auto-enable; };
&ps_dispext1_cpu { apple,skip-auto-enable; };
EOF
	fi
	if [ "$policy" = preserve-disp-no-cpu ]; then
		cat >> "$board" <<'EOF'

/* Minimal-policy necessity test: no cpu skips. */
&ps_dispext0_sys { apple,skip-auto-enable; };
&ps_dispext0_fe { apple,skip-auto-enable; };
&ps_dispext1_sys { apple,skip-auto-enable; };
&ps_dispext1_fe { apple,skip-auto-enable; };
EOF
	fi
	if [ "$policy" = preserve-disp-cpu-only ]; then
		cat >> "$board" <<'EOF'

/* Candidate minimum: only the two dispext CPU auto-enable skips. */
&ps_dispext0_cpu { apple,skip-auto-enable; };
&ps_dispext1_cpu { apple,skip-auto-enable; };
EOF
	fi

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
