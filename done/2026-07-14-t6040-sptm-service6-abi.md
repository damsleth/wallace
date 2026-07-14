# T6040 SPTM service-6 ABI + GENTER entry-state decode (2026-07-14)

Ticket 007 (offline, P0, storage critical path). Static decode of the Apple
GENTER/SPTM guarded-call ABI that `AppleANS2CGv2Controller` uses for protected
NVMe queue ownership, and of the guarded-execution entry state macOS holds
versus what raw m1n1 boot provides. Pure static analysis; no rig, no MMIO, no
storage access.

## Result

The service-6 ABI is fully decoded from the paired **M4 target** kernelcache: the
selector encoding, the complete guarded-service map, and the exact
service-6 op set (0..8) are read directly from the kernel's GENTER veneer table.
The blocker is confirmed architectural, not ABI knowledge: the GENTER guarded
gate requires an initialized GXF/SPTM environment that iBoot+SPTM establish
during macOS secure boot and that raw m1n1 never sets up
(`SPRR_CONFIG_EL1=0`, `GXF_CONFIG_EL1=0`, guarded entry/abort sysreg reads trap).
Reproducing the exact call byte-for-byte does not let raw boot issue a single
service-6 op. This is the evidence base for the ticket 008 go/no-go.

## Provenance (no Apple binary stored in this repo)

Correct paired-target image (M4 / Mac16,x / T6040·T6041), staged on the host by
prior IPSW work, disassembled only in the session scratchpad:

- Source: `/private/tmp/t6040-ipsw/kernelcache.release.mac16j` (IMG4 `krnl`, LZFSE),
  SHA-256 `4cc018b4ab925d879a0f039bf1f83cdbd11dc0bd906910afd1f9d15befabad1b`
- Decompressed arm64e Mach-O fileset (`kernelcache.mac16j.raw`), SHA-256
  `ed556fe62efc2c229f3d4c7ebbbcd21fd5c8d099fbb4d9b5ae636dd78b61d3f6`
- Version: `Darwin Kernel Version 25.5.0: … xnu-12377.121.10~1/RELEASE_ARM64_T6041`
  (macOS 26.x, T6041 = the T6040/M4 PMGR variant this project targets). This
  matches the M4's running macOS 26.5 and the earlier SART/PCIe write-ups' paired
  kernelcache.
- Tools: `radare2`/`nm`, cross-checked against `~/Code/linux-build-out/nvme-sptm-stubs.dis`.

Correction note: the first pass of this ticket mistakenly analyzed *this host's
own* Preboot kernelcache (M1 Max, `RELEASE_ARM64_T6000`, Darwin 24.6.0) instead
of the M4 target's image — the host runs an older macOS than the target. The
`T6000` tag and version mismatch were the tell. Every claim below has been
re-derived from the correct T6041 / Darwin 25.5.0 target image. The NVMe SPTM
operation inventory was identical between the two images; the selector-table
structure differs (see below), so re-grounding mattered.

The decompressed binary and all disassembly stay in the scratchpad; only this
write-up is committed.

## The GENTER guarded-call selector ABI (confirmed on target)

Apple GENTER is the single instruction `.inst 0x00201420` (bytes `20 14 20 00`;
no assembler mnemonic). The target kernelcache has **151** GENTER sites. 99 of
them form a **per-(service,op) veneer table** in `__TEXT_EXEC` (a stripped local
region); the other ~52 are the guarded-call runtime helpers that take the
selector from a register rather than an immediate.

Selector register: **`x16 = op | (service << 32)`**, built as `movz x16, #op`
then `movk x16, #service, lsl #32`. Read directly off the veneer table; it also
matches the Linux-side reconstruction `nvme-sptm-stubs.dis`.

### Guarded-service map (from the target veneer table)

| service | ops present | veneers |
|---:|---|---:|
| 3 | 0..18 | 19 |
| 5 | 0..2 | 3 |
| **6 (NVMe)** | **0..8** | **9** |
| 7 | 0..12, 24 | 14 |
| 9 | 0..12 | 13 |
| 10 (0xa) | 0..5 | 6 |
| 11 | 0..18 | 19 |
| 13 | 0..15 | 16 |

Service 6 has exactly nine veneers, ops 0 through 8 — this is the ticket's target
set, confirmed by direct enumeration rather than inference.

### A service-6 veneer (op 0), verbatim from the target

```asm
    pacibsp
    stp  x29, x30, [sp, #-0x10]!
    mov  x29, sp
    bl   guard_enter            ; 0x…4736830
    mov  x16, #0                ; op 0
    movk x16, #6, lsl #32       ; service 6
    .inst 0x00201420            ; GENTER -> SPTM at guarded level
    bl   guard_exit             ; 0x…473689c
    mov  sp, x29
    ldp  x29, x30, [sp], #0x10
    retab
```

`x0..x4` carry the per-op payload; `x0` carries the return. op 1 follows at
+0x2c with `mov x16, #1`, and so on through op 8 — a contiguous stub table.

### The guard-enter helper = the entry-state gate

```asm
guard_enter:
    pacibsp
    ...save x29/x30, x20/x21, x0..x7 (the SPTM args)...
    mov  x20, x16              ; stash selector
    mrs  x9,  tpidr_el1
    cbz  x9,  1f
    ldr  w10, [x9, #0x1c0]     ; per-thread guarded-call reentrancy counter
    add  w10, w10, #1
    str  w10, [x9, #0x1c0]
1:  mrs  x14, s3_6_c15_c8_0    ; guarded-mode status/lock sysreg
    cmp  x14, #0
    b.ne 1b                    ; spin until the guarded gate is idle (==0)
    ...restore args...  ret
```

The load-bearing precondition is the `mrs s3_6_c15_c8_0` read: the CPU must be
*able to read* the guarded-mode sysreg and it must report the gate idle before
GENTER is issued.

## Service-6 operation set (NVMe queue ownership)

The op *implementations* live in the SPTM firmware (guarded level), not the
kernelcache; the kernelcache exposes the caller side. NVMe operation semantics
are read from `IONVMeFamily` `AppleANS2CGv2Controller` symbols, present and
identical in the target image:

| Symbol | Role |
|---|---|
| `GetNVMeSPTMProtocolVersion()` | negotiate the SPTM NVMe protocol version |
| `GetNVMeSPTMQueueEntries()` | query SPTM-owned queue-entry limits |
| `SetupAdminQueue()` | register admin SQ/CQ with SPTM |
| `EnableSubmissionQueue(u16)` / `PolledEnableSubmissionQueue` | register/activate an I/O submission queue |
| `EnableCompletionQueue(u16)` / `PolledEnableCompletionQueue` | register/activate an I/O completion queue |
| `EnableAutoQueueManage()` | hand queue management to SPTM/ANS |
| `SetupIOQARegister()` | program the protected I/O-queue-attributes register |
| `NVMeCoastGuardSetTCB(...)` / `NVMeCoastGuardSetTCBEntry(tcb_queue_entry*, AppleNVMeRequest*)` | per-command TCB (translation-control-block) authorization |

These methods are vtable/PAC-dispatched (`blraa` through the ANS2 provider) and
reach the veneers via `_pmap_iommu_ioctl`, so the numeric op assignment for the
enable/query paths is not byte-proven from the caller.

### service-6 op → operation map

Confidence marked explicitly. The op *slots* 0..8 are proven present (veneer
table); op 0/1/4 assignments are proven by the prior live test; the rest are
matched to the remaining named NVMe operations by elimination.

| op | Operation | Confidence |
|---:|---|---|
| 0 | controller/queue-context initialization | **confirmed** (prior live test issued op 0 first) |
| 1 | TCB authorization | **confirmed** (`NVMeCoastGuardSetTCB`) |
| 2 | (queue/context op) | slot present; operation inferred |
| 3 | (queue/context op) | slot present; operation inferred |
| 4 | admin queue registration | **confirmed** (args below; prior live test) |
| 5 | I/O submission-queue registration | slot present → `EnableSubmissionQueue` (inferred) |
| 6 | I/O completion-queue registration | slot present → `EnableCompletionQueue` (inferred) |
| 7 | auto-queue-manage / IOQA program | slot present → `EnableAutoQueueManage`/`SetupIOQARegister` (inferred) |
| 8 | teardown / final activation | slot present; operation inferred |

Do not treat ops 2/3/5/6/7/8 as an exact contract.

### op 4 argument contract (confirmed)

From the reproduced sequence in `patches/t6040-nvme-sptm-debug.patch`, admin
setup is op 0 (no args) followed by op 4:

```
x16 = (6 << 32) | 4
x0  = admin SQ physical address (ASQ PA)
x1  = admin SQ depth - 1
x2  = admin CQ physical address (ACQ PA)
x3  = admin CQ depth - 1
x4  = 0
```

## GENTER entry state: macOS vs raw m1n1 boot (the crux)

macOS reaches the guard-enter helper with GXF fully live: iBoot loads and starts
the SPTM firmware at the guarded level, and the guarded-execution config
(`GXF_CONFIG_EL1`, the GENTER entry vector, `SPRR_CONFIG_EL1`) is programmed
before XNU runs. The `mrs s3_6_c15_c8_0` read then succeeds and GENTER traps
into the SPTM guarded vector, which services the request and `GEXIT`s back.

Raw m1n1 boot provides none of this. The read-only m1n1 snapshot before the
prior Linux attempt (`logs/t6040-console-20260714-nvme-sptm.log`):

```
SPRR_CONFIG_EL1 = 0x0
GXF_CONFIG_EL1  = 0x0
GXF_STATUS_EL1  = 0x0
GXF_ENTER_EL1   = SYNC exception   (reading the guarded entry sysreg traps)
GXF_ABORT_EL1   = SYNC exception
```

GXF is disabled and its entry vector unconfigured. With `GXF_CONFIG_EL1=0` there
is no guarded vector for GENTER to dispatch to; the prior live attempt confirmed
the failure mode — the CPU entered `.inst 0x00201420` and never returned (no
`GEXIT`, no exception delivered to Linux), and the watchdog recovered the
machine. A raw-boot GENTER neither dispatches to SPTM nor faults cleanly; it
wedges.

The gap is therefore not a register write Linux can add. It is the whole SPTM
guarded-execution bring-up: loading the SPTM monitor image, entering
GL2/guarded state, and programming `GXF_CONFIG_EL1` + the GENTER entry vector —
work owned by iBoot/SPTM during Apple secure boot, which m1n1's minimal raw boot
deliberately does not perform.

## Implications (feeds ticket 008 go/no-go)

- The service-6 ABI is understood well enough to *reproduce* macOS's admin-queue
  call; that was already tried and hung, so the ABI was never the missing piece.
- Direct main-BAR / secure-BAR queue programming remains faulting and is not a
  substitute (prior finding): the controller enforces the SPTM path.
- Storage under raw boot requires one of: (a) m1n1/Linux gaining a documented
  SPTM loader transition into guarded state (large; SPTM is signed/locked), or
  (b) upstream M4 SPTM support. Neither is a local register tweak.
- Everything here is static. No admin command, Identify, namespace read, mount,
  or storage write occurred, and none is justified by this decode.

## Reproduce

```sh
KC=/private/tmp/t6040-ipsw/kernelcache.mac16j.raw     # Darwin 25.5.0 T6041
nm "$KC" | grep AppleANS2CGv2Controller               # NVMe SPTM op inventory
# GENTER veneers: search kc for bytes 20 14 20 00; each stub is
#   movz x16,#op ; movk x16,#service,lsl32 ; .inst 0x00201420
# service 6 => 9 veneers, ops 0..8
```
