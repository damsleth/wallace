# T6040 / J614s upstream GPU mule checklist

Status 2026-08-03: parked. No maintainer-endorsed T6040/G16 kernel, firmware
ABI, m1n1, and Mesa combination is available, so no GPU artifact should be
built or run yet.

Use this only for a branch explicitly supplied or endorsed for T6040/G16
testing by the drm/asahi maintainers. It is not a recipe for adapting the
current G14 driver. Every live run still needs an exact-artifact rig ticket,
independent review, lease, and explicit maintainer approval.

## Candidate admission gate

Record immutable commit IDs for m1n1, Linux, Mesa, and any firmware tooling.
Reject the candidate before building unless all of these are true:

1. Linux has an explicit T6040 hardware configuration and compatible; it does
   not map `apple,agx-t6040` to a T602x/G14 configuration.
2. The kernel firmware structures explicitly support the supplied G16/macOS
   26.x ABI. A relaxed firmware-version comparison is not sufficient.
3. m1n1 explicitly supports T6040 in `dt_set_gpu()`, emits the three UAT
   reserved regions and the upstream branch's requested calibration/firmware
   properties, and does not reuse T602x calibration layouts by assumption.
4. Mesa has an explicit G16/AGX2 path selected from the kernel UAPI. It must
   not silently select `AGX_CHIP_G14G` or `AGX_CHIP_G14X` for generation 16.
5. The branch author provides the expected DT compatible, firmware ABI/build,
   first-test scope, and crash/recovery instructions.

The baseline evidence packet is
`done/2026-07-24-t6040-gpu-upstream-test-prep.md`.

## Offline build and inspection

- Build m1n1, kernel/modules/DTBs, and Mesa from clean pinned trees.
- Record compiler versions, configs, file sizes, and SHA-256 hashes.
- Decompile the final DTB and verify the GPU node, ASC, IOMMU, interrupts,
  power domains, OPP tables, reserved-memory phandles, and firmware properties
  against the branch author's contract and the captured ADT inventory.
- Verify the initramfs contains only the requested GPU module/firmware additions
  over the known RAM-root baseline. Keep internal NVMe, PCIe, external USB
  storage, networking, and unrelated experimental drivers disabled.
- Confirm the watchdog, `maxcpus=1 idle=nop`, DebugUSB console, simpledrm, and
  RAM-root remain present. Do not combine the first GPU probe with SMP,
  cpufreq, DCP, or enrollment.
- Independently review the exact archive and open a new rig ticket. Stop here
  until CJ approves its immutable hashes.

## Staged live sequence

Each stage is a separate approved boot unless the upstream maintainer's test
contract explicitly requires otherwise.

### G0 — probe only

Boot the storage-disabled RAM-root. Allow only module load/probe and capture:

```text
uname -a
cat /proc/cmdline
dmesg
ls -l /dev/dri /sys/class/drm
cat /sys/kernel/debug/dri/0/state
```

Do not open a render node or run Mesa. Pass requires RTKit/firmware startup,
the expected GPU identity, a stable render node, no DART/GPU fault, and a
responsive console for at least 60 seconds. Reboot; do not unload the module.

### G1 — userspace open, no render workload

After a clean G0, open the render node with the branch's smallest diagnostic
(`drm_info`, `eglinfo`, or maintainer-supplied equivalent). Capture kernel and
userspace logs. Do not run a compositor or benchmark. Pass requires the
expected G16 identity and clean context create/destroy.

### G2 — one bounded submission

After a clean G1, run only the maintainer-supplied one-triangle or one-dispatch
test with a hard timeout, then compare a small output buffer/image to the
provided reference. Capture `dmesg` before and after. No benchmark loop,
desktop compositor, suspend, or power-management stress.

### G3 — Mesa conformance smoke

Only after G2, run the exact short test list requested upstream. Pin the Mesa
commit and all environment flags. A desktop/glmark/dEQP sweep is a later
experiment, not a substitute for the bounded first submission.

## Stop conditions

Stop immediately on SError, DART fault, GPU/firmware panic, devcoredump,
watchdog/reset, console loss, unexpected storage/USB/PCIe probe, display loss,
or any write outside the reviewed driver path. Preserve the transcript and any
devcoredump, use the sanctioned reboot path once, and do not retry unchanged.

## Report template

```text
Title: T6040/J614s G16 mule result — <stage> — <pass/fail>

Machine:
  model: Mac16,8 / J614s / T6040
  macOS firmware source: <build>
  RAM: <size>

Pinned sources:
  m1n1: <remote> <commit>
  Linux: <remote> <commit>
  Mesa: <remote> <commit>
  firmware/tooling: <source> <commit/hash>

Artifacts:
  m1n1.bin: <size> <sha256>
  Image: <size> <sha256>
  DTB: <size> <sha256>
  initramfs: <size> <sha256>
  modules/firmware manifest: <sha256>

Test:
  stage: G0/G1/G2/G3
  command(s): <exact>
  timeout: <seconds>
  expected identity/output: <exact>
  result: <exact>

Kernel identity:
  compatible: <value>
  chip/generation/variant: <values>
  firmware ABI/build: <values>
  cores/clusters: <values>

Safety:
  storage-disabled: yes/no
  maxcpus=1 idle=nop: yes/no
  watchdog/DebugUSB healthy: yes/no
  DART/SError/GPU fault/reset: none/<details>

Attachments:
  console transcript: <sha256>
  dmesg before/after: <sha256>
  devcoredump: none/<sha256>
  output/reference comparison: <result/hash>

First divergence:
  <earliest unexpected line/state; do not summarize away>

Recovery:
  <sanctioned reboot result>
```
