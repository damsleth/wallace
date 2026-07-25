#!/usr/bin/env bash
# Build an XOR-masked B0 raw object (ticket 133).
#
# iBoot declines to execute an enrolled raw object whose appended region looks like
# a payload (ticket 129: probe-fdt-only, 1.10 MiB, never enters m1n1). The payload is
# therefore stored masked so nothing recognisable appears, and m1n1 un-masks it in
# place before parsing (-DPAYLOAD_MASK_KEY / -DPAYLOAD_MASK_LEN).
set -euo pipefail

OUT=${OUT:-/Users/damsleth/Code/linux-build-out}
WT=${WT:-/private/tmp/m1n1-earlyproxy}
BOOTARGS='maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/sbin/init'
KERNEL=$OUT/Image-b0-diet.xz
DTB=$OUT/t6040-j614s-dcuart-hid-state-trace.dtb
INITRAMFS=$OUT/initramfs-alpine-b0-nb2.cpio.xz

# 1. assemble the plaintext payload stream and choose a mask key that leaves no
#    recognisable magic anywhere in the masked bytes.
read -r KEY LEN < <(python3 - "$BOOTARGS" "$KERNEL" "$DTB" "$INITRAMFS" <<'PY'
import sys
ba, kern, dtb, init = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
payload = (f"chosen.bootargs={ba}\n".encode() + open(kern,'rb').read()
           + open(dtb,'rb').read() + open(init,'rb').read() + b"\0"*4)
# Structural magics (>=4 bytes) and ASCII markers must be absent. A 2-byte gzip
# magic (1f 8b) cannot be avoided in ~8 MB of high-entropy data for ANY key, and by
# the same token cannot be what iBoot keys on (every real kernelcache would contain
# it incidentally), so it is reported but not required to be absent.
MAGICS = [b"\xfd7zXZ\x00", b"\xd0\x0d\xfe\xed", b"070701", b"070702",
          b"chosen.", b"m1n1_sig", b"\x16\x04IMG4"]
import re

def textual(b):
    """fraction of printable ASCII (informational only)"""
    return sum(1 for c in b if 32 <= c < 127) / max(1, len(b))

# NB: compressed/high-entropy data is ~37% printable by nature (95 of 256 byte
# values), so a low printable *ratio* is unachievable and is the wrong test. What
# matters is that no LEGIBLE STRING survives. A key >= 0x80 maps every ASCII byte
# to >= 0x80 (non-printable), which guarantees the bootargs text is unreadable, and
# we additionally reject any long printable run.
LONG_RUN = re.compile(rb"[ -~]{24,}")

# Prefer high-bit keys: they push ASCII out of the printable range, so the masked
# bootargs cannot read as near-text (key 0x01 merely flips the low bit and leaves
# "chosen.bootargs=" legible as "bhpsdo/...").
chosen = None
# high-bit keys only: guarantees ASCII -> non-printable, so no text stays legible
for key in range(0x80, 0x100):
    m = bytes(b ^ key for b in payload)
    if any(g in m for g in MAGICS):
        continue
    if LONG_RUN.search(m):
        continue
    chosen = (key, m)
    break

if chosen is None:
    sys.exit("no single-byte key satisfies the criteria")

key, m = chosen
open('/private/tmp/b0-payload-masked.bin','wb').write(m)
open('/private/tmp/b0-payload-plain.bin','wb').write(payload)
sys.stderr.write(f"[key 0x{key:02x}] gzip-pairs={m.count(b'\x1f\x8b')} "
                 f"printable(4KiB)={textual(m[:4096]):.3f}\n")
print(key, len(payload))
PY
)
echo "== mask key 0x$(printf '%02x' "$KEY"), payload length $LEN bytes =="

# 2. build m1n1 with that exact key/length (plus fb console always on)
( cd "$WT"
  export PATH="$HOME/.cargo/bin:$PATH" RUSTUP_TOOLCHAIN=nightly
  make clean >/dev/null 2>&1
  EXTRA_CFLAGS="-Wstack-usage=2048 -DPAYLOAD_MASK_KEY=$KEY -DPAYLOAD_MASK_LEN=${LEN}UL -DFB_CONSOLE_ALWAYS=1" \
      make -j8 >/dev/null 2>&1 )
cp "$WT/build/m1n1.bin" "$OUT/m1n1-t6040-unmask-v5.bin"
echo "m1n1 v5: $(shasum -a 256 "$OUT/m1n1-t6040-unmask-v5.bin" | awk '{print $1}')"

# 3. object = m1n1 + masked payload
cat "$OUT/m1n1-t6040-unmask-v5.bin" /private/tmp/b0-payload-masked.bin > "$OUT/m1n1-b0-masked.bin"

# 4. verify: no magic in the masked region, and un-masking reproduces the plaintext
python3 - "$OUT/m1n1-b0-masked.bin" "$KEY" "$LEN" <<'PY'
import sys, hashlib
obj = open(sys.argv[1],'rb').read(); key=int(sys.argv[2]); ln=int(sys.argv[3])
PFX = 0x10C000
masked = obj[PFX:]
assert len(masked) == ln, (len(masked), ln)
MAGICS = {"xz":b"\xfd7zXZ\x00","fdt":b"\xd0\x0d\xfe\xed",
          "cpio":b"070701","bootargs-ascii":b"chosen."}
for n,g in MAGICS.items():
    print(f"  masked region contains {n:16s}: {'YES (BAD)' if g in masked else 'no'}")
un = bytes(b ^ key for b in masked)
plain = open('/private/tmp/b0-payload-plain.bin','rb').read()
print(f"  incidental 2-byte gzip pairs (unavoidable, informational): {masked.count(b'\x1f\x8b')}")
print("  first 16 masked bytes:", masked[:16].hex())
print("  un-mask reproduces plaintext:", un == plain)
print("  object size:", len(obj), f"({len(obj)/1048576:.2f} MiB)")
print("  object sha256:", hashlib.sha256(obj).hexdigest())
PY
