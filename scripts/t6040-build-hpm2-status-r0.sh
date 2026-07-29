#!/bin/sh
# Build and audit the ticket-178 HPM2 connector-status candidate twice.
set -eu

M1N1_TREE=${M1N1_TREE:-/Users/damsleth/Code/m1n1-hpm2}
BUILD_OUT_ROOT=${BUILD_OUT_ROOT:-/Users/damsleth/Code/linux-build-out}
CAPTURED_ADT=${CAPTURED_ADT:-/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt}
EXPECTED_ADT_SHA256=7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
EXPERIMENT_CLASS=5

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
    echo "ticket-178 source is missing" >&2
    exit 1
}

llvm_bin=$(/opt/homebrew/bin/brew --prefix llvm)/bin
for tool in llvm-nm llvm-objdump; do
    test -x "$llvm_bin/$tool" || {
        echo "$tool not found under $llvm_bin" >&2
        exit 1
    }
done
test -x /Users/damsleth/.cargo/bin/cargo || {
    echo "Rust toolchain shim is missing" >&2
    exit 1
}

output="$BUILD_OUT_ROOT/t6040-hpm2-status-$short/r0-status"
test ! -e "$(dirname "$output")" || {
    echo "output already exists: $(dirname "$output")" >&2
    exit 1
}

temporary=$(mktemp -d "${TMPDIR:-/tmp}/t6040-hpm2-status-build.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

build_one()
{
    pass=$1
    version="t6040-hpm2-status-r0-$short"

    PATH="/Users/damsleth/.cargo/bin:$PATH" RUSTUP_TOOLCHAIN=nightly \
        make -C "$M1N1_TREE" clean
    PATH="/Users/damsleth/.cargo/bin:$PATH" RUSTUP_TOOLCHAIN=nightly \
        make -C "$M1N1_TREE" -j8 \
        M1N1_VERSION_TAG="$version" \
        EXTRA_CFLAGS="-DT6040_HPM2_EXPERIMENT_CLASS=$EXPERIMENT_CLASS"

    pass_dir="$temporary/pass$pass"
    mkdir -p "$pass_dir"
    for artifact in m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf; do
        cp "$M1N1_TREE/build/$artifact" "$pass_dir/$artifact"
    done
    cp "$M1N1_TREE/build/t6040_hpm2.o" "$pass_dir/t6040_hpm2.o"
    "$llvm_bin/llvm-nm" -n "$pass_dir/m1n1-raw.elf" >"$pass_dir/symbols.txt"
    (
        cd "$pass_dir"
        "$llvm_bin/llvm-objdump" -dr --no-show-raw-insn \
            t6040_hpm2.o >t6040_hpm2.dis
    )

    grep -q ' t6040_hpm2_experiment$' "$pass_dir/symbols.txt"
    grep -q ' spmi_init_strict$' "$pass_dir/symbols.txt"
    grep -q ' spmi_reg0_write$' "$pass_dir/symbols.txt"
    grep -q ' spmi_ext_read$' "$pass_dir/symbols.txt"
    grep -q ' spmi_shutdown$' "$pass_dir/symbols.txt"

    if grep -Eq \
        ' spmi_ext_write$| spmi_send_(wakeup|reset|sleep|shutdown)$| spmi_ext_(read|write)_long$' \
        "$pass_dir/symbols.txt"; then
        echo "forbidden SPMI symbol linked into ticket-178 artifact" >&2
        exit 1
    fi

    test "$(grep -c 'R_AARCH64_CALL26[[:space:]]*spmi_reg0_write$' \
        "$pass_dir/t6040_hpm2.dis")" -eq 1
    test "$(grep -c 'R_AARCH64_CALL26[[:space:]]*spmi_ext_read$' \
        "$pass_dir/t6040_hpm2.dis")" -eq 2
    ! grep -Eq \
        'R_AARCH64_CALL26[[:space:]]*spmi_(ext_write|send_wakeup|send_reset|send_sleep|send_shutdown)' \
        "$pass_dir/t6040_hpm2.dis"

    grep -q 'mov[[:space:]]w2, #0x1a' "$pass_dir/t6040_hpm2.dis"
    grep -q 'mov[[:space:]]w2, #0x20' "$pass_dir/t6040_hpm2.dis"
    grep -q 'mov[[:space:]]w4, #0x4' "$pass_dir/t6040_hpm2.dis"
    strings -a "$pass_dir/m1n1.bin" | grep -q \
        't6040-hpm2: ticket 178 class R0-status, direct endpoint only'
    strings -a "$pass_dir/m1n1.bin" | grep -q \
        't6040-hpm2: status raw=%08x bytes=%02x %02x %02x %02x'
}

build_one 1
build_one 2

for artifact in m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf t6040_hpm2.o \
    symbols.txt t6040_hpm2.dis; do
    cmp "$temporary/pass1/$artifact" "$temporary/pass2/$artifact"
done

mkdir -p "$output"
for artifact in m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf t6040_hpm2.o \
    symbols.txt t6040_hpm2.dis; do
    install -m 0644 "$temporary/pass2/$artifact" "$output/$artifact"
done
(
    cd "$output"
    shasum -a 256 m1n1.bin m1n1.macho m1n1.elf m1n1-raw.elf \
        t6040_hpm2.o t6040_hpm2.dis >SHA256SUMS
)

{
    echo "ticket=178"
    echo "m1n1_commit=$commit"
    echo "experiment_class=$EXPERIMENT_CLASS"
    echo "captured_adt=$CAPTURED_ADT"
    echo "captured_adt_sha256=$actual_adt_sha"
    echo "builds=two byte-identical clean builds"
    echo "traffic=selector write 0x1a; bounded selector reads; four-byte data read at 0x20"
    echo "forbidden=wakeup, reset, sleep, shutdown, extended write, long SPMI transfers"
} >"$output/MANIFEST"

echo "ticket-178 candidate: $output"
cat "$output/SHA256SUMS"
