# T6040 Linux bring-up — next steps

Current as of 2026-10-30. The M4 runs standalone on the 5019 debug kernel
(enrolled via 1TR) with its desktop root on the internal SSD, at `maxcpus=1`.
ANS2 rejects Flush, so the SSD runs write-through. BLE HID (MX Ergo S),
ftrace/kprobes and ramoops work. kexec is refused under `maxcpus=1` (5021/5024
fix that with `nr_cpus=1`). Agents work on the machine itself (COORDINATION.md
on-device mode). This file states priorities and stop conditions.
Exact work items, hashes, dependencies, and approval state live in
`tickets/*.json`.

## Manual commands for CJ (run these first)

Agents cannot run these. Keep this list current: add a command when a ticket
blocks on CJ, and remove it once it has been done.

1. **Finish 5020: the warm-reboot pstore check** (on the M4, with no agent
   mid-task, since the reboot ends every session on the machine):

   ```sh
   /mnt/sd/code/wallace/scripts/t6040-onboard-pstore-reboot.sh         # marker, then clean reboot
   /mnt/sd/code/wallace/scripts/t6040-onboard-pstore-reboot.sh check   # after the reboot
   ```

   A missing marker is a finding, not a failure. A warm reboot scrubbed DRAM
   on 2026-07-30, and pstore may then only carry records across kexec (5021).

2. **Push the reconstructed kernel base** (on the Mac). 5019 was built from
   `wallace/reconstructed-4f24291` (`6d2e54a0d`), which exists only in
   `/Volumes/CaseSensitive/linux`. Without it nobody else can rebuild the
   running kernel:

   ```sh
   cd /Volumes/CaseSensitive/linux && git push origin wallace/reconstructed-4f24291
   ```

2b. **Push the enrolled m1n1 source** (on the Mac). The m1n1 inside 5014/5019
   (`bf4b2462…`, version `v1.6.0-wallace-80badc91`) was built from
   `80badc91e62c8b4228a857730f160ffb62a29335`, which is not on GitHub
   (`damsleth/m1n1` has only `main` at `16b1f61`). Until it is pushed, nobody
   can rebuild that m1n1 or put the 5015 CTRR_C series on it, on the M4 or
   anywhere else:

   ```sh
   cd ~/code/m1n1 && git push origin 80badc91e62c8b4228a857730f160ffb62a29335:refs/heads/wallace/enrolled-80badc91
   ```

   If the window-free build used local flags or uncommitted files, note them in
   the 5015 ticket.

3. **Decide on the live sshd.** The running root listens on port 22 with
   `PermitRootLogin yes`, a root password, and no `authorized_keys`, so it
   accepts password logins as root from the network. The rebuilt root (5022)
   is key-only. To match it now, put your Mac's public key in
   `/root/.ssh/authorized_keys` on the M4, then:

   ```sh
   printf 'PermitRootLogin prohibit-password\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n' \
       > /etc/ssh/sshd_config.d/10-wallace.conf && rc-service sshd restart
   ```

4. **Approve rig tickets** when you want them run. Tell an agent, or run:

   ```sh
   scripts/rig-lease.sh queue approve 5021 --by cj   # kexec feasibility (needs 5024 enrolled)
   scripts/rig-lease.sh queue approve 5025 --by cj   # kexec kernel trial (after 5021)
   scripts/rig-lease.sh queue approve 5015 --by cj   # CTRR_C reads + SMP test (two variants)
   scripts/rig-lease.sh queue approve 5023 --by cj   # ANS2 Flush with dma_flags 0
   scripts/rig-lease.sh queue approve 5029 --by cj   # boot 5028 (pms_fpwm disabled; object c0e5d515)
   ```

5. **Enroll the 5024 object** (for 5021; built and verified, `/mnt/sd/wallace-5024/`). Same procedure as
   5019, documented in `docs/LINUX_PARTITION_README.txt` section 1, with the
   5024 file name and hash:

   ```sh
   shasum -a 256 /Volumes/linux/wallace-5024/wallace-5024.build1.bin
   # must equal 02da5165117d0c3a5b18e62a890ffc8ee7120ecb181ea3e2df5a32cfa0eb16a3
   kmutil configure-boot -c /Volumes/linux/wallace-5024/wallace-5024.build1.bin --raw \
       --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1
   ```

   `m1n1` is the only boot volume (CJ, 2026-10-30; RUNBOOK §10).
   `/Volumes/wallace` was the old name of the `linux` partition. Enrolling
   replaces what is there; `TARGET=/Volumes/m1n1 scripts/t6040-enroll-guard.sh`
   checks the hash once 5024's is on its allowlist.

   The SSD ignores Flush. Shut down cleanly (`poweroff`/`reboot`, never a
   hard reset), or the newest writes, the object included, can be lost.

6. **Resync the Mac clone** if it pulled `4b1ef4f` before the 2026-10-30
   force-push that removed trailers. Check `git log origin/main..main` first:

   ```sh
   cd ~/code/wallace && git fetch && git reset --hard origin/main
   ```

## Device bring-up map (2026-10-30, CJ's new scope)

Panel brightness, HDMI, USB-C beyond VBUS, GPU, ANE and Touch ID are mapped on both sides:
[live and Wallace](../evidence/2026-10-30-t6040-device-map-live.md) and
[macOS abstract](../evidence/2026-10-30-t6040-device-map-macos-abstract.md). The keyboard
backlight works. Touch ID is not feasible (SEP-encrypted sensor link). Almost every next step
needs the J614s ADT: 5027 (`MTD_PHRAM`) or the Mac dump. Panel brightness (164) is the nearest
win; the ADT decides between its SPMI, PWM, DWI and I2C variants. 5028 tracks the `pms_fpwm`
domains that won't power on.

## 0. The current objective: a practical daily driver

**CJ's direction, 2026-08-03 (supersedes the previous upstream-first ordering).**
The goal is a machine that is actually usable, with six capabilities working
unambiguously:

| capability | state |
|---|---|
| SD read/write | reader and persistence proven; fixture needs `fsck.exfat` repair |
| USB read/write | device mode works; **USB2 host data path DONE 2026-08-19** (108) — dwc3 probes, right xHCI root hubs healthy. VBUS is the sole gap; the tps6598x SPMI PD driver is CJ-signed-off (231). 305 run 6: a1 SPMI binds, PD probe `-ENODEV` (WAKEUP never sent). Run 7 (2026-10-25): WAKEUP ACKed, register select mis-encoded; the run-8 `pddiag` image (`08de37b1`, 5002) is built, CJ-attended run pending |
| NVMe read/write | **Reads and writes work at `maxcpus=1`.** Reads: 6001 run 3 (2026-10-24), 16,384 direct reads through ~256 CQ wraps with the zero-based ANS2 IOQ size. Writes: 211 stage 1 r2/r3 (2026-10-25), 1 GiB at about 410 MB/s into the pinned exFAT `linux` partition (`nvme0n1p3`), read-back hash equal, writes elsewhere zero. **ANS2 rejects NVMe Flush** (5006), so the SSD must run `write through`, and recent writes are durable only after a clean controller shutdown; a crash or hard reset loses the last writes (see §3). **NVMe daily root (5005/5008) works:** desktop root on `linux`, WiFi auto-joins, three clean-reboot cycles clean ([5008 C](../evidence/2026-10-25-t6040-5008-C-nvme-daily-root.md)) |
| WiFi | works, including DHCP and routed traffic |
| Bluetooth | `hci0` present and working |
| Trackpad | **DONE 2026-08-19** (230): finger test PASSED — 37 950 events on `/dev/input/event0` and haptic click works. Daily-image integration remains (301) |

**Upstream reporting is explicitly deferred** — CJ: "we are not doing any
upstream reporting just now." Sections below that call an upstream report the
highest-value action are describing engineering value, not current priority.

Standing constraints for autonomous work:

- **NVMe writes are restricted to the exFAT `linux` partition**, verified by
  label *and* GPT type before any write, aborting on mismatch. No other
  partition on the internal SSD may be written (CJ, 2026-08-03).
- SD repair is a real `fsck.exfat`, not clearing the dirty flag (CJ, same).
- Chainload rather than enroll; the always-proxy rollback object stays enrolled.

## Permanent right-port USB-root goal (CJ, 2026-10-24)

The intended daily root is now a small USB-C stick left in the right port,
booted by the enrolled m1n1/kernel/initramfs through OpenRC. SD remains a
checksum-verified read/write fallback. This does not change any current
capability result above or bypass the 6001/305 execution gates.
As of 2026-10-25 the active daily-root track is the internal-SSD root on the
exFAT `linux` partition (5005/5008, §3). This USB-root section is retained
as written; CJ decides whether it still stands.

Completion requires three consecutive cold boots with clean poweroff and
post-poweroff fsck, root-stick write/sync/reboot/checksum persistence,
6001's 16,384 direct 16 KiB NVMe reads plus separately gated checksum-verified
writes only to label-and-GPT-type-verified exFAT `linux`, DHCP/routed WiFi after
cold boot, M1↔M4 OBEX, daily trackpad touch/haptics and SD fallback R/W.
All must pass in **one preflight-clean image**, with Norwegian layout and no
SPMI/SMC/PMU access outside SPMI_SAFETY. None of this full-image acceptance has
run. Retain maxcpus=1. USB U-Boot3018 and stable SMP205 are stretch objectives.
The existing SD-first U-Boot work below can continue as fallback/stage2 work;
U-Boot is not a prerequisite for the direct-m1n1 USB-root objective.

**6005 (offline, in progress)** prepares a separate verified USB-root init and
identity/GPT/ext4 gates ([implementation and test evidence](../evidence/2026-10-24-usb-root-verified-init.md)).
48 metadata/selection cases pass natively on Linux/aarch64 and under macOS
sanitizers; 41 intercepted PID1 startup cases and six real OpenRC/ext4 shutdown
cases pass in the contained host harness. Two separate root-profile staging
archives match. These are host results; actual USB handoff/poweroff/cold boots,
physical identity and final initramfs qualification remain untested.
The legacy USB init accepts an arbitrary resolved root without USB identity
and lacks the keymap load. Keep its old payloads historical; do not use it for
a refreshed RW-root candidate. The new separate staging profile supplies the
Norwegian root config, shutdown gate and daily services; the historical098
image remains unchanged and does not satisfy the goal.
305→109→110/111→112/113 remain the hardware/flash/root progression, with exact
new artifacts and separate erase/enrollment review. 5008 (NVMe daily root) is done on hardware (§3).

## Immediate experiment: ANS2 queue-size contract

**Resolved for reads (6001 run 3, 2026-10-24).** The local Linux driver wrote
64 into the zero-based ANS2 IOQ-size fields at 0x1210 for 64-entry rings;
upstream and m1n1 write 63. With the 6000 fix, 16,384 direct 16 KiB reads ran
through about 256 CQ wraps at `maxcpus=1`: data byte-identical over four
passes, +16,384 reads and zero writes on n1, auxiliary n2/n3 unchanged, clean
full dmesg ([run 3](../evidence/2026-10-24-t6001-run3-16384-reads-no-cq-wrap-assert.md)).
Runs 1 and 2 stopped on payload defects, not hardware: the gate rejected the
SSD's three namespaces, then the log watchdog matched `BUG:` in `debug:`
([run 1](../evidence/2026-10-24-t6001-run1-gate-parked-three-namespaces.md),
[run 2](../evidence/2026-10-24-t6001-run2-tester-false-stop.md)).

Run 3's formal transcript checker was not green because `/dev/kmsg`
ratelimiting dropped the tester's PASS line. 5008 step A (2026-10-25) closed
that: the same 6001 tester initramfs (`524d94c3`) with `printk.devkmsg=on`, on
the new daily+NVMe kernel `2234baad`, and its checker passed. Not established:
sustained reads, multi-CPU, the 227 teardown UAF. Writes are covered in §3.

## October upstream findings and offline follow-ons

[Full review and source record](../evidence/2026-10-24-asahi-dev-review.md)
cover September 21–October 24, through 16:00 UTC. External J614s NVMe success,
submitted M4 Pro/Max DTs, and a working older HID branch justify convergence
work. They do not change the local capability table or authorize writes.

- **6001 is done for reads** (run 3, and its tester passed again as 5008 step
  A). The linux-next controller-state regression is distinct from our CQ-wrap
  assert. 5008 then delivered the NVMe daily root (§3).
- **6002 complete (offline audit):** [pinned map and candidate plan](../evidence/2026-10-24-upstream-convergence-audit.md). Corrected Asahi
  `asahi-7.2.12-2` is `2bb9d16f967f11e533a851b13b148a708d59b4f3`.
  **6004 (offline, P1)** assembles the separate LC1 source candidate, retaining
  local J614s DT, split NVMe and v2 input. Resolve PMGR and duplicate FIFO
  provider conflicts before a separate build ticket. No baseline replacement
  or live readiness is implied.
- **6003 (offline, P2):** plan a separate M4 Pro tracing environment with paired
  host/target revisions and recovery. Login-screen tracing is useful; post-login
  hangs and unexplained AMCC interrupt suppression remain.
- **Official Asahi M4 page (docs `c15c4937`, 2026-10-03):** T604x has no
  installer and no `linux-asahi` entry; DT, AICv3 and NVMe are WIP and every
  MacBook Pro peripheral is TBA. The `linux-asahi (7.4)` DT/AICv3/watchdog/I2C/
  GPIO entries are base M4 (T8132) only. Nothing to adopt, and the local
  capability table stands on Wallace evidence
  ([reading](../evidence/2026-10-24-asahi-m4-feature-support-page.md)).
- Continue SD repair/shutdown, daily trackpad integration and scoped right-port
  VBUS work. Base-M4 USB does not solve M4 Pro's TB5 ATCPHY.
- Keep fault 205 open: secondary-start improvements and KVM SEIS fixes do not
  prove runtime MM/COW correctness. Defer experimental p3s/4K-process MM work.

## 1. Characterise and report the MM/SMP copy race

Tickets: **205** (umbrella), **217** (offline artifact), **209** (approved
rig run); **207** and **208** are done

**Lead (2026-10-29, ticket 5015):** 5012 found that the secondaries deny
writes to a physical range near the ADT end. M4 has a second CTRR instance,
`CTRR_C` (`s3_0_c11_c0_{0,1}`), which is enabled only on secondaries and was
not in the registers 5012 read. Asahi m1n1 `a735ea2`/`00b8814` and Gravity
`eb6cab7` reserve that range as an FDT mem-rsv. Asahi says this, together with
`idle=nop arm64.nowfxt`, makes M4/M4 Pro SMP boot reliable. We ship only
half of that: `flokli-code.patch` with `idle=nop` skips WFIT, but `__delay()`
still loops on WFET and our cmdline has no `arm64.nowfxt` (5015 adds it).
Gravity runs all 16 CPUs on the M4 Max. Not yet verified on J614s
([survey](../evidence/2026-10-29-gravitylinux-survey.md)).
The J614s ADT memory-map names the 384 KiB gap after the ADT
`TrustCache`; 5012's window lies inside it, beyond Asahi's 48 KiB. Local patch
`patches/m1n1-ctrr-c-v1/0004` reserves it by name, alongside 0001–0003
(2026-10-31, AI-written, fork only, syntax-checked, not built).

**2026-10-30:** the macOS kernel writes no CTRR register on any CPU, so the
secondary-only window is firmware-locked and a carve-out is the only remedy.
The live boot has no CTRR reservation, and the 384 KiB from the ADT end to
m1n1 `_base` is allocatable RAM that covers everything 5012 saw. 5015 now
tests the Asahi series and a fixed 384 KiB Wallace reservation side by side
([abstract and live layout](../evidence/2026-10-30-t6040-5015-ctrr-macos-abstract-and-live-layout.md)).

Established (mechanism detail and method in [DEVLOG.md](DEVLOG.md) "CPU" and
`evidence/2026-08-03-t6040-205-smp-cow-investigation.md`):

- the dependency-free BusyBox reproducer distinguishes one from two cores
  (`maxcpus=2` faulted twice in four runs, ticket 208);
- ticket 207's bisect **refuted the ordering hypothesis** — `smp_mb()` and a
  semantically irrelevant volatile read each suppress the fault, so the race is
  not in `copy_highpage`; the kernel-mode fault on a valid linear-map address
  points at page lifetime/refcount or TLB-invalidation completion;
- the bug is **fail-stop, not silent corruption** (round 18): with a fault
  firing and killing a concurrent process, twelve consecutive 64 KiB
  copy-and-compare checks were byte-identical. This establishes the observed
  fail-stop outcome for that test. Not proven: that a process *hit* by the fault writes nothing bad
  before dying, or that a fault during page-cache writeback cannot reach storage.

Do next:

1. Preserve an upstream-quality draft of the reproducer and 207/208 results
   (3002); external reporting remains deferred. Use 6002 to compare relevant
   upstream CPU changes without claiming they fix the runtime fault.
2. Ticket 217 (offline): build the byte-reproducible, storage-free diagnostic
   initramfs around the uninstrumented control Image and prove the stock
   arm64 oops already reports the logical CPU.
3. Ticket 209 (rig, consumes 217's artifact): characterise which CPU takes
   the fault and whether the victim differs in core type or cluster from the
   CPU that populated the page, using the controlled-online-set DTBs.
4. Keep the discipline: fresh boot per variant, at least four runs (the first
   is the most sensitive), constant storage/drivers/topology/workload, and an
   exact Image hash plus uniquely named transcript per result.

Pass: a locally reviewable report draft plus a victim-topology characterisation.
Do **not** ship any perturbation that merely suppresses the symptom; ticket
207 proved suppression is not evidence of a fix. A single clean run is not
evidence either.

## 2. Repair and harden the SD-root system

Tickets: **215**, then **216**; these close **204**

The SD reader and root image work at `maxcpus=1`: `switch_root`, ttydc0, OpenRC,
and persistence were observed. Later SMP panic tests left exFAT and ext4
unclean. Do not mount the root read/write again before ticket 215.

**Ticket 3006 (2026-10-24):** the staged shutdown pivot could never have
completed on the device. OpenRC hides `/run/initramfs`, the remount lacked
`/proc`, and OpenRC submounts pin the old root. The scripts are fixed and the
host harness `scripts/t6040-test-sdroot-shutdown.sh` (baseline 0/23, fixed
23/23) is now the gate for this path
([evidence](../evidence/2026-10-24-t6040-3006-sdroot-shutdown-regression.md)).
**216's object `bdd8cc86…` is invalid until rebuilt** from the fixed scripts
(ticket 5000). Any daily SD-root object (301/4003 trackpad
integration included) must carry them.

Do next:

1. Exact-review ticket 215's pinned repair image and automatic-only repair script.
2. Repair and repeat read-only checks for SD64 and the ext4 image.
3. Exact-review ticket 216's identity gates, early console, and shutdown pivot.
4. Apply the root configuration and boot it at `maxcpus=1`.
5. Power off through the PID-1 restart path; verify ext4 and exFAT are clean.
6. Preserve a uniquely named, hash-pinned transcript.

Use `maxcpus=1`. Ticket 205 proves that two or more CPUs can fault in kernel
page-copy paths; that is separate from SD storage.

Pass: the repaired root boots through ttydc0 and OpenRC, cleanly powers off,
and both filesystems pass post-shutdown read-only checks without repair.

Approved follow-ons **213** (i3 desktop on the SD root) and **214**
(WiFi/sshd/ntpd autostart, removing the serial tether) continue this track
once 215/216 restore a clean root.

## 2a. Stable enrolled SD stage 2 (active, offline-first)

Tickets: **3010** (architecture, done), **3011** (PCIe/SD ownership, done), **3012**
(one-shot proxy cookie), **3013** (SD U-Boot), **3014** (bundle tooling),
**3015/3016** (compose + independent review), **3017** (read-only tethered
first light), **3019** (physical-media preflight). Ticket **3018** adds USB
only after the VBUS track has a bounded result; **3020** packages and validates
the exact Linux handoff on a synthetic FAT image.

The target is:

```text
iBoot -> enrolled aligned m1n1 -> short DTR proxy window -> U-Boot
                                                        |-> SD -> Linux
                                                        |-> USB -> Linux later
                                                        `-> no media -> warm reboot -> Running proxy
```

The architectural contract is
[recorded here](../evidence/2026-08-19-t6040-removable-stage2-architecture.md).
The enrolled object changes rarely; Image, J614s DTB, initramfs and their
manifest are the daily files. SD comes first. The current card's outer exFAT
filesystem is not a U-Boot boot filesystem, and nothing here authorizes
repartitioning it. Ticket 3019 must prefer a separately identified development
card or stop for an exact maintainer choice.

Do next, entirely offline:

1. Implement and host-test the clear-before-use, one-shot warm-RAM proxy reason
   (3012). Do not use NVRAM or invent a direct return from U-Boot.
2. Apply ticket 3011's resolved boundary while building the SD target (3013):
   m1n1 performs exact `gP19` power and the one common-PHY/link initialization;
   U-Boot attaches only if the link is already up and owns DART1/PCI/MMC above
   it. Link-down must not trigger a second port setup.
3. Build the SD-only U-Boot target twice, then build and independently review
   the aligned composed object (3013, 3015, 3016).
4. Build the board-bound FAT32/FIT-or-manifest tooling on synthetic images
   (3014). The daily profile stays `maxcpus=1`, ANS/NVMe disabled, trackpad
   enabled, and Norwegian-layout compliant. Ticket 3020 then validates the
   exact `booti` handoff and daily bundle without touching a card.
5. Only then propose 3017 for cross-review and approval. It chainloads while the
   rollback remains enrolled, reads only PCI/MMC/GPT identity from SD64, and is
   expected to warm-reboot once back to the enrolled proxy because no valid FAT
   bundle exists.

Pass for this phase: one reviewed tethered run proves the GL9755/MMC path and a
clean return to the enrolled rollback proxy, with no media write or enrollment.
Physical bundle installation and untethered enrollment get separate tickets
only after an exact removable target and hashes exist.

## 3. NVMe: writes proven; write-through durability; the NVMe daily root

The Linux CQ-wrap assert was the non-zero-based IOQ size (see Immediate
experiment). Linux reads and writes now pass at `maxcpus=1`. The daily SD-root
DTB (`c5c3b4c3`) still keeps ANS/NVMe disabled; the separate nvmeroot DTB
`t6040-j614s-dcuart-wifi-cpufreq-nvmeroot` (`6d2d3da6`) is the sdroot DTB with
only the model string and the three ANS nodes (mailbox, SART, `nvme@44dcc0000`)
set `okay`.

**Writes (211 stage 1, 5003 payloads, 2026-10-25).** Run 1 stopped on the
first Flush (`BAD_CMD`, `fast decode err 0x7`, `sc 0x2`); its data was later
lost on a hard reset
([write1](../evidence/2026-10-25-t6040-211-write1-flush-badcmd.md)). With
`write_cache` set to `write through`, r2 wrote 1 GiB in about 2.6 s (about 410 MB/s) and r3
another 1 GiB, each into the label-, GPT-type- and extent-pinned exFAT
`linux` partition; read-back after `drop_caches` matched; whole-disk writes
equalled p3 writes and nothing else was written; no BAD_CMD or I/O errors
([r2](../evidence/2026-10-25-t6040-5006-flush-unsupported-211-write-r2-pass.md),
[r3](../evidence/2026-10-25-t6040-211-r3-clean-shutdown-durable.md)).

**Flush is not supported (5006).** An m1n1 proxy probe sent Flush with m1n1's
own minimal encoding (zeroed TCB, `dma_flags=3`) to nsid 1 and to broadcast
`0xFFFFFFFF`; both returned status 2, and the link stayed alive. The
`t6040-nvme-apple-flush-tcb.patch` is therefore not the fix; it stays opt-in
(`NVME_FLUSH_TCB`) and unused. How macOS makes ANS2 durable is an open RE item.

**Durability model.** Without Flush, ANS2 holds the most recent writes in a
volatile cache and does not commit them on its own, even after minutes idle.
r2's 1 GiB survived a hard reset, but its trailing `pattern.sha256` and the
exFAT dirty-bit clear were lost. r3 ended with `reboot -f`, so
`device_shutdown` reached `apple_nvme_shutdown` (CC.SHN); the firmware logged
`saveCtx 1 took 599 ms`, and after a hard reset the verify found every file,
including the last one written. Rules for any system that mounts the internal
SSD read/write:

- set `/sys/block/nvme0n1/queue/write_cache` to `write through` before the
  mount (no Flush/FUA requests reach the firmware);
- shut down cleanly through the `reboot`/`poweroff` syscall so that
  `device_shutdown` runs the controller shutdown;
- accepted caveat (CJ): a crash or hard reset still loses the last writes.
  ext4's journal on the loop root bounds that to recent data.

**KVM shutdown oops (5007), fixed for the daily image.** r3's `reboot -f`
then hit `kvm_shutdown` → `kvm_timer_cpu_down` → `aic_fiq_set_mask`, an
IMP-DEF sysreg write (`d51df160`) that traps because the kernel is not at EL2:
Oops (Undefined instruction), and the machine hung after the storage
shutdown. The daily+NVMe kernel is built with kbuild `NO_KVM=1`; 5008 step B
showed `saveCtx 1 took 678 ms` and then `reboot: Restarting system` with no
Oops ([5008 A/B](../evidence/2026-10-25-t6040-5008-A-B.md)).

**NVMe daily root (5005 offline, 5008 rig).** SD64 was unavailable, so the
root is a host-built 16 GiB ext4 image (`wallace-root.img`, UUID `988d97b4`,
raw sha256 `e3fa66b5…`) from the pinned dwm/i3 desktop RAM root
(`initramfs-alpine-dwm-i3-v5`) plus a persistent OpenRC profile and the
Norwegian layout at all three layers; the RAM-root `t6040-data-mount` and
`t6040-data-sync` are removed. Kernel `2234baad` = daily301 config minus KVM
(flags `DOCKCHANNEL DOCKCHANNEL_NBCON MACSMC HID_TYPE_FIX T6040_PPP WIFI PCIE
CPUFREQ TRACKPAD_FW TRACKPAD_RESET_CONTRACT NVME NVME_IOQ_SIZE NVME_EXFAT
NO_KVM`), DTB `6d2d3da6`, m1n1 `7de07c71`
([payloads](../evidence/2026-10-25-t6040-5005-payloads.md)).

**5008 step C done (2026-10-25).** Four NVMe-root boots (C1–C4), the last
three each after a clean `reboot` through the PID-1 shutdown. Every
post-shutdown boot's fail-closed gates found exFAT and ext4 clean. OpenRC,
Xorg + i3, the Norwegian layout at all three layers and BT service are up;
WiFi auto-joins `Casa-D` (initramfs `dfcd7d5c`, which differs from `9adabb1b`
only in `wpa_supplicant.conf`). Untested: the final power-off of `poweroff`
(smc_reboot is disabled), BT pairing/OBEX on this root, USB, and multi-core.
Evidence: [5008 C](../evidence/2026-10-25-t6040-5008-C-nvme-daily-root.md).

- **A: PASS.** The 6001 read-only tester (`524d94c3`) on the new kernel and
  DTB: 16,384 direct reads, no writes; the same boot brought up both PCIe
  links, WiFi, BT, the GL9755 SD reader, keyboard, trackpad firmware and
  `nvme0n1: p1 p2 p3 p4`.
- **B: done.** Installer `d2c564f0` repaired the dirty p3 (from r2), set
  write-through, wrote the image (sha256 equal to the pin, re-read equal,
  loop `e2fsck -fn` clean). It then STOPped on a false positive: `others()`
  counted the read I/Os from `findfs`; the parked shell showed zero writes
  outside p3. The clean reboot was run by hand. `others()` now compares
  writes, discards and flushes only (`4389c3d`).
- **C: pending.** First NVMe-root boot (`9adabb1b`), then three cold boots
  with clean poweroff and a post-poweroff fsck. Nothing about the NVMe root
  booting is established yet.

Still open: stage 2 of 211 (raw `dd` to p3) needs CJ's re-authorization
against the new partition; sustained reads, multi-CPU NVMe, the 227 teardown
UAF, and Apple's real durability mechanism.

Parked: 201 (RTKit crashlog decoder), 203/210 (threaded-IRQ discriminator) and
195 (live admin traffic in m1n1) were follow-ons for the assert. Revive them
only if an assert reappears with the zero-based size. Do not revive the
refuted “wrong MMIO window,” non-zero tag, batching, or simple queue-depth
explanations without new evidence.

## 4. Keep the strict SD fixture sequence honest

Tickets: **199** then **200**

Ticket 193 already proved SD read/write persistence. Tickets 199/200 are a
stricter, hash-pinned fixture procedure and must not be treated as if they have
run.

- Ticket 199 is read-only: identify GL9755 and `SD64`, mount `ro`, list,
  hash one existing file, and unmount.
- Ticket 200 may run only after 199 is done and separately approved: mount
  read/write, create the one named test file, fsync, unmount, remount read-only,
  and verify content and SHA-256.

Neither ticket permits repartitioning, formatting, fsck, or unrelated card
changes. Ticket 200 must also respect the dirty-filesystem gate owned by
tickets 215/216.

## 5. Trackpad: DONE — daily-image integration remains

**Complete as of 2026-08-19** (ticket 230, touch + haptic click; finger-test
numbers and the `0x40`/v2 decode are in
`evidence/2026-08-19-t6040-trackpad-finger-test-PASS.md` and
[DEVLOG.md](DEVLOG.md) "Trackpad").

Do next — **ticket 301:** fold the patch
(`t6040-dockchannel-hid-reset-contract.patch`) and the `a1f4131d` firmware blob
into the daily sdroot image, two-build reproduce, preflight, new enrollable
object, so the daily driver carries a working trackpad without a special image.
Any live attempt stays limited to the approved volatile HIDF blob `a1f4131d…`;
nothing else changed in the safety scope.

## 6. USB host/VBUS (active)

Tickets: **108** (USB2 data path — DONE, VBUS the sole gap), **303** (v2 rebuild,
built + binary-reviewed), **231** (PD driver — reviewed and **CJ-signed-off**),
**3000/3008** (a1 address correction — audited and byte-reproduced offline),
**3009** (independent corrected-DTB review, PASS and done), **305** (attended PD/VBUS run,
corrected artifact reviewed; attendance and fixture gates remain), **229** (R0 connector read, attended-only), **109+** (block
read-only and beyond, blocked)

Both 2026-08-04 blockers are solved offline (mechanism and live-run detail in
[DEVLOG.md](DEVLOG.md) "USB and Type-C"):

1. **dwc3 `-EINVAL` — fixed and VERIFIED LIVE (2026-08-19).** The v2 PHY slice
   (303, `buildB` `80248306…`, binary-reviewed PASS) probes clean, both right
   xHCI root hubs up and persistent, zero DART faults. **The USB2 data path is
   done.** No child appeared — VBUS is the sole gap (or the S128 stick left the
   port; CJ settles that by looking).
2. **VBUS — tps6598x SPMI transport written and reviewed** (231, `77fd00b`;
   review `evidence/2026-08-18-t6040-tps6598x-spmi-review.md`). A draft
   hpm2-only DT connector node exists
   (`dts/t6040-j614s-dcuart-usb2-native-right-pd.dts`). Ticket 305 runs 1--4
   accidentally put the ADT's raw `/arm-io` address `0x309198000` under
   identity-mapped Linux `/soc`; they therefore never accessed the real a1
   controller and do not prove an a1 hardware stall. Ticket 3000 proved the
   translated CPU physical address is `0x509198000`. Ticket 3008 built the
   corrected DTB twice from clean trees, byte-identical (`eaf8cceb...`), with
   hpm2 as the sole PD endpoint and NVMe disabled.

CJ **signed off the SPMI envelope 2026-08-19** — the exact permitted operations
are in `docs/SPMI_SAFETY.md` (Entry 1, hpm2/right-port only via the DT gate).
Independent exact-artifact review (3009) of the corrected `eaf8cceb...` DTB
passed; see its completed ticket and review evidence. Remaining: the attended
PD/VBUS live run (305), including an R0
connector-state read (229) to learn whether the right port already sources
VBUS; then the PD-enabled image through the normal build/review cycle. SPMI
stays deny-by-default; the only described PD endpoint is right-port `hpm2`.

**305 run 6 (2026-10-24,
[evidence](../evidence/2026-10-24-t6040-305-run6-a1-physfix-probes-hpm2-enodev.md)):**
at `0x509198000` both SPMI controllers bound, with no hang, SError or DART
fault; runs 1–4 hung only on the raw address. hpm2 appeared as `1-0c`, but
`tps6598x-spmi` probe returned a silent `-ENODEV`; no typec class, no VBUS, no
child. **305 PASS not met.** Confirmed from source: `spmi-apple` has no
`.cmd`, so `spmi_command_wakeup()` returns `-EINVAL` without touching the bus,
and the probe ignored that result. That an un-woken part then reads VID 0 and
causes the `-ENODEV` is consistent with 093 but not yet hardware-proven.

Fix: `patches/t6040-spmi-wakeup-and-tipd-probe-diag.patch` (f430d1f) adds a
WAKEUP-only `.cmd` (every other opcode `-EOPNOTSUPP`), fails the probe closed on
WAKEUP error, waits 10 ms and logs the power state and VID. Within SPMI_SAFETY
Entry 1; independent review PASS-with-notes
([review](../evidence/2026-10-24-t6040-pdwake-patch-independent-review.md)).
Next: two byte-identical `pdwake` builds and artifact review, then an attended
run. Expect `after WAKEUP: power-state … state=0x07`; `state=0x00` with VID 0
points at the select/window protocol instead. The host must first free the
Debug USB device from `deviceinterfaced` ([RUNBOOK](RUNBOOK.md) §2).

**305 run 7 (2026-10-25,
[evidence](../evidence/2026-10-25-t6040-305-run7-wakeup-ok-zero-write-encoding.md)):**
WAKEUP reached the bus and was ACKed, but the power-state read returned
`state=0x00` and VID 0: spmi-apple encoded the register-select zero-write as a
command word plus a data word, so every select hit register 0. The fix
(`t6040-spmi-apple-zero-write-encoding.patch`, `64dcbaf`) and a read-only
connector-state diagnostic form the `pddiag` image (5002), built twice
byte-identical (Image `08de37b1`) with preflight OK
([build](../evidence/2026-10-25-t6040-5002-pddiag-build-and-review.md)).
This track belongs to the Mythos session. Run 8 is CJ-attended. Multi-core
fault 205 remains fail-stop, so it also runs at `maxcpus=1`.

## 7. Parked tracks

- **GPU:** wait for a maintainer-endorsed T6040/G16 kernel, firmware ABI, m1n1,
  and Mesa stack. Do not relabel G14 support.
- **Internal-NVMe stage 2:** ticket 191 remains a separate parked design. It is
  not the active removable SD-first path. The NVMe I/O fault it waited on is
  resolved; the active internal-SSD root work is 5005/5008 (§3).
- **Audio, camera, suspend, cpuidle, panel backlight:** retain as roadmap work;
  none blocks the current SD-root milestone.

## Global stop conditions

Stop on an async SError, DART fault, firmware panic, unexpected reset, console
loss before the planned boundary, artifact mismatch, access outside the ticket,
or any write not explicitly authorized. Preserve the first transcript and
return the rig in the state required by [COORDINATION.md](COORDINATION.md).
