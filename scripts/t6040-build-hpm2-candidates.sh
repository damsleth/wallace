#!/bin/sh
# Build and audit the ticket-092 R0/R1/R2 and ticket-105 R3 (SWDF) / R4 (SWUF) m1n1 candidates twice.
set -eu

M1N1_TREE=${M1N1_TREE:-/Users/damsleth/Code/m1n1-hpm2}
BUILD_OUT_ROOT=${BUILD_OUT_ROOT:-/Users/damsleth/Code/linux-build-out}
CAPTURED_ADT=${CAPTURED_ADT:-/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt}
EXPECTED_ADT_SHA256=7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84

git -C "$M1N1_TREE" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "not an m1n1 worktree: $M1N1_TREE" >&2
    exit 1
}
test -f "$CAPTURED_ADT" || {
    echo "captured ADT missing: $CAPTURED_ADT" >&2
    exit 1
}

actual_adt_sha=$(shasum -a 256 "$CAPTURED_ADT" | awk '{print $1}')
test "$actual_adt_sha" = "$EXPECTED_ADT_SHA256" || {
    echo "captured ADT hash mismatch: $actual_adt_sha" >&2
    exit 1
}

test -z "$(git -C "$M1N1_TREE" status --porcelain)" || {
    echo "m1n1 worktree is dirty; refusing a non-reproducible build" >&2
    exit 1
}

commit=$(git -C "$M1N1_TREE" rev-parse HEAD)
short=$(git -C "$M1N1_TREE" rev-parse --short=12 HEAD)
source_file="$M1N1_TREE/src/t6040_hpm2.c"
test -f "$source_file" || {
    echo "ticket-092 source is missing" >&2
    exit 1
}

llvm_bin=$(/opt/homebrew/bin/brew --prefix llvm)/bin
test -x "$llvm_bin/llvm-nm" || {
    echo "llvm-nm not found under $llvm_bin" >&2
    exit 1
}
test -x /Users/damsleth/.cargo/bin/cargo || {
    echo "Rust toolchain shim is missing" >&2
    exit 1
}

output="$BUILD_OUT_ROOT/t6040-hpm2-$short"
test ! -e "$output" || {
    echo "output already exists: $output" >&2
    exit 1
}

temporary=$(mktemp -d "${TMPDIR:-/tmp}/t6040-hpm2-build.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
mkdir -p "$temporary/final"

build_one()
{
    class=$1
    pass=$2
    version="t6040-hpm2-r${class}-${short}"

    PATH="/Users/damsleth/.cargo/bin:$PATH" RUSTUP_TOOLCHAIN=nightly \
        make -C "$M1N1_TREE" clean
    PATH="/Users/damsleth/.cargo/bin:$PATH" RUSTUP_TOOLCHAIN=nightly \
        make -C "$M1N1_TREE" -j8 \
        M1N1_VERSION_TAG="$version" \
        EXTRA_CFLAGS="-DT6040_HPM2_EXPERIMENT_CLASS=$class"

    pass_dir="$temporary/r${class}-pass${pass}"
    mkdir -p "$pass_dir"
    for artifact in m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf; do
        cp "$M1N1_TREE/build/$artifact" "$pass_dir/$artifact"
    done
    "$llvm_bin/llvm-nm" -n "$pass_dir/m1n1-raw.elf" >"$pass_dir/symbols.txt"

    grep -q ' t6040_hpm2_experiment$' "$pass_dir/symbols.txt"
    grep -q ' spmi_init_strict$' "$pass_dir/symbols.txt"
    grep -q ' spmi_reg0_write$' "$pass_dir/symbols.txt"
    grep -q ' spmi_ext_read$' "$pass_dir/symbols.txt"
    if test "$class" -ge 1; then
        grep -q ' spmi_send_wakeup$' "$pass_dir/symbols.txt"
    else
        ! grep -q ' spmi_send_wakeup$' "$pass_dir/symbols.txt"
    fi
    if test "$class" -ge 2; then
        grep -q ' spmi_ext_write$' "$pass_dir/symbols.txt"
    else
        ! grep -q ' spmi_ext_write$' "$pass_dir/symbols.txt"
    fi

    if grep -Eq \
        ' spmi_send_(reset|sleep|shutdown)$| tps6598x| usb_init$| usb_phy_bringup$| spmi_ext_(read|write)_long$' \
        "$pass_dir/symbols.txt"; then
        echo "forbidden symbol linked into class R$class" >&2
        exit 1
    fi
}

for class in 0 1 2 3 4; do
    build_one "$class" 1
    build_one "$class" 2

    for artifact in m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf symbols.txt; do
        cmp "$temporary/r${class}-pass1/$artifact" \
            "$temporary/r${class}-pass2/$artifact"
    done

    class_dir="$temporary/final/r$class"
    mkdir -p "$class_dir"
    for artifact in m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf symbols.txt; do
        install -m 0644 "$temporary/r${class}-pass2/$artifact" "$class_dir/$artifact"
    done
    (
        cd "$class_dir"
        shasum -a 256 m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf >SHA256SUMS
    )
done

{
    echo "m1n1_commit=$commit"
    echo "captured_adt=$CAPTURED_ADT"
    echo "captured_adt_sha256=$actual_adt_sha"
    echo "builds=two byte-identical clean builds per class"
    echo "classes=R0 R1 R2 R3(SWDF) R4(SWUF)"
} >"$temporary/final/MANIFEST"

mv "$temporary/final" "$output"
echo "ticket-092/105 candidates: $output"
for class in 0 1 2 3 4; do
    sed "s|  |  r$class/|" "$output/r$class/SHA256SUMS"
done
