# October upstream convergence audit — ticket 6002

Astra, 2026-10-24. Offline Apple Silicon Linux hardware enablement audit.

**Decision:** use corrected Asahi `2bb9d16f967f11e533a851b13b148a708d59b4f3`
as the base of a **separate source-integration candidate**, keeping Wallace's
captured J614s DT, mailbox-based input/console, raw-boot policy and split NVMe
mapping. Do not import Yuka's component branch tips wholesale. The first
candidate replaces the base kernel, not the loader, firmware, PHY, display or
MM architecture. It is a plan, not a compiled or runnable artifact.

6001 remains the next hardware action, under its existing CJ-ready gate. Its
payload, ticket, hashes and approval state were not changed. There was no rig
access, enrollment, target storage access or external posting in this audit.
The daily baseline, `maxcpus=1`, and enrolled rollback remain in place.

## Evidence and reproducibility

- [Source lock](2026-10-24-upstream-convergence/source-lock.json): immutable
  revisions, retrieved-source SHA-256s and URLs, mail message IDs/body hashes,
  all local patch/DT/harness hashes, retrieval failures and scope limitations.
- [Captured ADT extraction](2026-10-24-upstream-convergence/sources/adt-summary.json),
  [config comparison](2026-10-24-upstream-convergence/config-comparison.json),
  [source-context checks](2026-10-24-upstream-convergence/sources/apply-checks.json),
  [candidate specification](2026-10-24-upstream-convergence/candidate-plan.json),
  and [patch disposition inventory](2026-10-24-upstream-convergence/patch-map.tsv).
- Saved primary code, tag responses and compressed complete mail threads are
  under `2026-10-24-upstream-convergence/sources/`. These avoid reliance on a
  mutable branch name or transient IRC HTML. The earlier
  [IRC review](2026-10-24-asahi-dev-review.md) supplies external run context.

At entry Wallace was **clean**, HEAD `fa99387` (full SHA in source lock): the
October refresh was already committed, despite the handoff's dirty-tree warning.
The Linux symlink's volume was unmounted. Its host sparsebundle was attached
**read-only**, exposing `/Volumes/linux/repo`; this is a host source-volume
operation, not rig access. Its HEAD is exactly
`4f2429104009e3964ddcc326d8490ac25bfb1a5c`. Existing dirty `t6040.dtsi`,
`t6040-pmgr.dtsi` and untracked board variants were read and preserved. The two
SoC DT source copies in Wallace and the Linux checkout are byte-identical;
PMGR and board snapshots are saved in `local-source/`. No source checkout,
reset, fetch, build or source-tree write was performed there.

Read AGENTS, COORDINATION, NEXT_STEPS, DEVLOG including corrections, ROADMAP,
the October review and 6002; also BUILD_RECIPE and RUNBOOK for candidate gates.
No compilation or schema pass is claimed. `git apply --check --verbose` was run
inside an isolated Git root on captured source files; it measures textual
compatibility only, not complete-series or API compatibility.

## 1. Immutable reference and merge-status ledger

| reference | exact pin | verified status / scope |
|---|---|---|
| Corrected Asahi `asahi-7.2.12-2` | tag object `6882df38eec9690e112d3e3f62ed6b5974ac07f4`; commit `2bb9d16f967f11e533a851b13b148a708d59b4f3`; tree `dc2d3044740e7c13308778d16c4b0669ffc44745` | Retrieved annotated tag and commit through GitHub API. Tagger 2026-10-22 20:27:08 UTC; API signature verification true, not independent local GPG verification. Makefile is 7.2.12. Downstream integration, not a mainline-support claim. |
| Corrected `asahi-7.2.12-1` | tag object `6d131de2f2d20f24c9a324208b27f3983e16bdc6`; commit `83b6d853f25cb95075aa16851418c4c4e7a37e2c` | Tag message explicitly says second try. This commit is the direct parent of `-2`; `-2` adds the AQC113 reset fix. Do not use the original transient mis-tag. The retrieved history includes Linux 7.2.12 `cc9de5d4b5ab6459f5774946aa3195ad51236fa8`. |
| Mainline inspection snapshot | `5b0764a53235d3c77e1ed674e836e1b3fe1a4b1f` | Target Makefile has no t6040/t6041 targets; nvme-apple has no t8132 match or split NVMMU; brcmfmac PCIe lacks BCM4388 support. Absence is asserted for those inspected interfaces, not every preparatory patch. |
| Yuka minimal DT submission branch | `b4/apple-m4-pro-max-initial-devicetrees` → `7edc05e30bf7a9da5e4e61bd94ca098445b15af9` | Ten t6041 binding/DT commits above its base; minimal CPU/AIC/UART/framebuffer foundation. Submission reported Oct 10; branch was rebased Oct 11. Pin is the retrieved b4 branch, **not verified byte-identical to the original mail submission**. No target in either inspected Asahi or mainline Makefile. |
| Yuka fuller DT reference | `parts/04-dt-more` → `0880225c96f587ce7645fd3ca8e51769bccbfccd` | Oct 19 component stack; includes NVMe, PCIe and endpoint nodes beyond the minimal submitted DT. Not evidence that those additions were merged upstream. |
| Yuka NVMe support | `parts/20-nvme` → `09116ec06ce4aba5e34f0266dad74c3678aa30c3`; M4 commit `6acd61216911155b04fd98ca5599c3e74450010b` | Actual driver diff retrieved. Tip adds SARTv4; **exclude that M5 change**. M4 diff supplies zero-based IOQ setup but uses one controller aperture, unlike Wallace. |
| Historical queue-size reference | `42839287f85c8c36b63579371af533fcd1b8c970` | Diff still retrievable; same zero-based IOQ contract used in 6000. Its hash and current rebased `6acd…` identify references, not a reason to alter 6001. |
| Yuka T604x NVMe DT delta | `2888926b6342cd4acc74015d59d5304e7dc329ed` in `parts/04-dt-more` | Sets ANS always-on; mailbox IRQs 1530–1533, SART and NVMe properties below. Published component code, distinct from local direct-boot validation. |
| Yuka old HID component | `parts/40-old-dchid` → `55e130fd72dbd21cf0896a73664eaa8029b9f792` | Actual legacy driver at `drivers/hid/dockchannel-hid/dockchannel-hid.c`; RTKit-helper + SoC FIFO API, not Wallace's mailbox API. v1 power request remains. |
| Yuka old HID DT component | `parts/41-dt-old-dchid` → `cb64e51073fc6837d25f3b83c0d965c2ab020626`; T604x device and board commits `501a16a59f79c8defe62e99dac055d220f982589`, `419adc71f0d8fedd8666fa60123b7262d4c82390` | Retrieved diffs. SID, SRAM, FIFO topology and helper contract differ materially; see §3. |
| HID v4 submission | Message ID `20260925-apple-mtp-keyboard-final-v4-0-304c267518f4@gmail.com`; patches 1–10 use same suffix | Full raw thread retrieved. Keyboard-only, tested on M3 J613. Trackpad firmware support expressly deferred. Binding discussion continued Oct 6. Neither the series date nor reviewed bindings proves a complete J614s input replacement. |
| BCM4388 v1 submission | Message ID `20260925-brcm4388-submit-v1-0-b5cbc2cde2fb@gmail.com`; patches 1–13 use same suffix; base `42a9fb3382fc2573e92f41d203b095d9a372cfc9` | Full raw thread and patches retrieved. Tested J613 scan/WPA2/DHCP/TCP; PCIe/DT and port-authorization fix are separate dependencies. Maintainer response says review underway. Chip support absent from inspected mainline PCIe source; Asahi already has downstream chip support but still BSS maximum 112. |

Primary immutable entry points:
[Asahi tag](https://api.github.com/repos/AsahiLinux/linux/git/tags/6882df38eec9690e112d3e3f62ed6b5974ac07f4),
[Asahi commit](https://github.com/AsahiLinux/linux/commit/2bb9d16f967f11e533a851b13b148a708d59b4f3),
[Yuka M4 NVMe](https://cyberchaos.dev/yuka/linux/-/commit/6acd61216911155b04fd98ca5599c3e74450010b),
[Yuka storage DT](https://cyberchaos.dev/yuka/linux/-/commit/2888926b6342cd4acc74015d59d5304e7dc329ed),
[HID v4](https://lore.kernel.org/asahi/20260925-apple-mtp-keyboard-final-v4-0-304c267518f4@gmail.com/),
[BCM4388 v1](https://lore.kernel.org/asahi/20260925-brcm4388-submit-v1-0-b5cbc2cde2fb@gmail.com/).

**Historical reference gap:** `parts/21-dt-nvme` and
`t604x-old-dchid-working` no longer appear in the published branch inventory;
ref-specific history endpoints return empty lists. Surviving components above
are pinned comparisons, not a reconstruction of the Oct 5/8 tested checkout.
The source lock preserves this distinction. Public raw file endpoints worked
where GitLab API file endpoints timed out; Lore raw/mbox worked despite web-tool
failures and a 403 for archive search. No credentials or external posts used.

## 2. NVMe/SART: three independent contracts

### Controller state: regression is resolved in the inspected code

Bad mainline commit
`c20bba234f3e1dcd81f7a2ec21ea7bf01a4cf35f` removed `NVME_CTRL_NEW` from
allowed prior states of `NVME_CTRL_RESETTING`. Apple probe still initializes
through `nvme_reset_ctrl()`, so that combination can leave a controller with
no namespaces. Full regression mail shows the proposed CONNECTING transition
was **retracted**, because it cannot then enter RESETTING. Maintainer Keith
Busch reported reverting the patch. Mainline path history contains revert
`5755f1bd0217ffe3c5cf85467bf6b0680f398265` and subsequent merge
`4375b45d7060a6a3f41e14a9181c5c913ea474a4`.

The pinned Asahi `core.c` directly allows NEW → RESETTING; its bounded core
history does not contain the offending 7.3 patch. The inspected mainline
snapshot also permits the transition. **No controller-state fix is needed on
this Asahi pin.** Future rebases must verify the transition and driver as a
pair, not blindly cherry-pick the revert or add CONNECTING to Apple probe.
This namespace-init regression cannot explain the existing Wallace assert:
our controller already enumerates and performs I/O before the first CQ wrap.
[Regression thread](https://lore.kernel.org/all/94912d46-381d-4988-800a-6ef3b595233f@cyberchaos.dev/T/).

### ANS2 IOQ sizing: preserve the separately prepared test

Local kernel base's `need_ioq_register=true`, depth 64 path writes
`64 | 64 << 16` to controller +0x1210. Both retrieved Yuka commits write
`63 | 63 << 16` **after** IOCQ and IOSQ base registration at +0x1208/+0x1200;
legacy hardware retains the pending-command-limit behavior. Wallace's
`t6040-nvme-ans2-ioq-size.patch` implements that distinction against its split
mapping. Firmware ignores the Create Queue qsize field for this contract;
software queue depth agreement alone did not validate the old register value.

Candidate 6001 already contains this fix plus the separately established
force-clean-ANS boot path, with unmodified code/config/DT/initramfs hashes.
The original source-only commit is not equivalent to its final patched Image.
6001 must supply local CQ-wrap evidence before selecting the subsequent storage
variant; upstream code is corroboration, not that evidence.

### Split mapping and power: retain proven local behavior

The July 21 and July 28 **live captures were reparsed offline**. Hashes:
`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`
and `2fe477c613c67e44550ded1bbb6cad9cf4fffc62393b47b39edc6c11281df4ba`.
ADT `get_reg()` translation, not raw `.reg`, gives:

| property | live ADT / Wallace | Yuka `2888926b…` | disposition |
|---|---|---|---|
| ANS coprocessor | raw reg0 `0x209600000/0x88000`; CPU `0x409600000`; driver control subwindow 0x4000 | same 0x4000 control aperture | retain; full ADT wrapper length is not the controller subresource length |
| mailbox | CPU `0x409608000/0x4000`; raw IRQ order 1531,1530,1533,1532; names require 1530,1531,1532,1533 | matches translated base and ordered IRQs | convergence available; use t6041 compatible only with matching binding |
| NVMe | raw reg9 `0x24dcc0000/0x10000` → CPU `0x44dcc0000/0x10000` | same base, **0x60000** size | conflict: do not widen in first candidate |
| NVMMU + linear SQ doorbells | raw reg3 `0x20dcc0000/0x60010` → CPU `0x40dcc0000`; local mapped size 0x60000 | no separate resource; all accesses use `mmio_nvme` | retain local `mmio_nvmmu` and all its TCB/linear-doorbell access sites |
| NVMe IRQ | 2583 from ADT interrupt index 4 | 2583 | matches |
| SART | version 3; raw `0x20dc50000/0xc000` → CPU `0x40dc50000/0xc000` | same base, **0x10000** size | retain live-capture size; no enlargement by analogy |
| SART power metadata | captured `sart-power-managed`, power offset 0x13e8 in reg2 (`0x40dcc0000`) | fallback `apple,t6000-sart`, no power resource | current local final node also uses t6040 + t6000, **not t8140 power-managed match**; don't infer handshake execution from patch presence |
| ANS power/reset | `ps_ans`, APCIE_SYS_ST0/ST1 parents, ANS reset; local PMGR snapshot | same named dependency graph plus ANS `apple,always-on` | compare generated offsets/parents, not phandle numbers; preserve current local graph in first candidate |

The current Yuka driver has no `mmio_nvmmu`, accesses linear/NVMMU registers
through the controller aperture, and re-enables legacy setup/queue-count calls
that the Wallace firmware path gates. Importing just its IOQ patch is possible
textually; importing the whole driver/DT would silently change four contracts.
Wallace's E7 controller-doorbell trial was reverted by
`1369af1f63c5080f07cccb7938c0bffa9186cd63`; do not resurrect it here.

The local SART power-management and deferred-scan patches remain compatibility
code for explicitly matching nodes; neither this audit nor an ADT marker
licenses switching J614s into that path. SARTv4 at `09116ec0…` is for another
hardware generation and supplies no T6040 requirement. Keep protected bootloader
entries and lazy-scan behavior where the current matching path uses them.

## 3. DT/input property map

| area/property | actual comparison | integration decision |
|---|---|---|
| board identity | submitted/current Yuka `apple,j614s`, `apple,t6040`, `apple,arm-platform`; shared hardware defined in t6041 | common vocabulary can replace local binding aliases in a later DT migration; retain current board include closure for first candidate |
| CPU topology | live J614s has fused-off positions in a 4E + 6P + 6P template; local DT has explicit disabled positional slot required by current m1n1 pruning, online result 4E+5P+5P | keep loader/DT positional contract and `maxcpus=1`; no wholesale SoC replacement |
| AIC | local CPU base `0x502400000`, event `0x502440000`; local lengths 0x1cc000/0x4000 vs Yuka 0x184000/4 and named resources; shared t8122-aic3 fallback | do not conflate schema cleanup with an IRQ-map migration. Retain existing lengths/config offsets; independently review changed resource semantics |
| PMGR display domains | live device nodes **disp0 + dispext0/1**, no dispext2/3; PMGR table still contains extra hardware/template labels | submitted J614s file correctly deletes dispext2 CPU/FE/SYS, shared T6040 deletes dispext3; keep internal disp hierarchy. PMGR metadata alone does not establish a populated engine |
| raw-boot display ownership | local `ps_disp_cpu` intentionally disabled; dispext0_cpu/1_cpu skip AUTO; active firmware-owned domains preserved | port exact local raw-boot policy on new PMGR code. Keep simpledrm, no DCP enable or framebuffer-domain ownership change |
| AP GPIO | live gpio0 CPU `0x51c000000/0x4000`, 200 pins, IRQs 478–484; Yuka maps 0x100000, same count/IRQs | keep captured window. Neither compared AP node has `gpio-reserved-ranges` |
| reserved pins | live `no-restore-gpio-pins` bytes decode LE u32 **191,192,190** | record board-specific evidence; not proof of an inaccessible pin or equivalent reservation semantics. If a later reviewed driver contract warrants reservation, contiguous candidate is `<190 3>`, not copied A18/M5 numbers. No pin probing here |
| PCIe endpoints | captured `apcie0/pci-bridge0` WiFi/BT, bridge1 SD; CLKREQ 0/1, PERST 4/5. Local port00/port01 and DART0/1; Yuka full DT selects **port02/DART2** for SD | keep proven local port01 topology and disabled ports02/03. Reconcile against ADT and m1n1 pruning before any DT migration; Linux bus number 02 is not physical root port02 |
| endpoint power | local `gpio-macsmc` keys gP13 (line 0x13) and gP19 (line 0x19); new Yuka board nodes alone don't reproduce this handoff | retain approved endpoint GPIOs and wait/probe behavior. No new SMC keys |
| SMC | live ASC CPU `0x50c600000`, mailbox `0x50c608000`, ordered IRQs 996–999; local SRAM base `0x50de70000` established by RTKit requests, not generic SoC arithmetic | preserve actual shared-memory contract and telemetry/endpoint power; size uncertainty remains as recorded in DEVLOG. Minimal submitted DT does not replace this functionality |
| HID ASC | local mailbox form `coproc-asc`/`coproc-sram` at `0x514600000/0x4000`, `0x514c00000/0xac000`, ASC IRQs 792–795 | keep current form; Yuka old-helper DT instead uses `asc`/`sram` at `0x514e00000/0x100000` and RTKit helper |
| HID DMA | local HID device owns MTP DART SID0; proven upload and touch/haptics | Yuka helper owns SID0 and HID FIFO child SID1. Those are different device/DMA ownership contracts; never merge only the DT or only the driver |
| HID FIFO | local mailbox resources IRQ/config/data `0x514b14000`, `0x514b30000`, `0x514b34000`, each 0x1000; parent IRQ776, RX BIT3 | Yuka interrupt-controller FIFO + child four-window topology, same parent IRQ776 but helper API. Retain mailbox stack for first candidate |
| HID power | local nine-byte 0x40/v2, phase0 then phase1, status0, for OFF then ON; Yuka/Asahi old driver sends four-byte v1 and ignores the two reset return values | retain `t6040-dockchannel-hid-reset-contract.patch` after firmware support. 0x40 is **power**, 0x42 is actual reset. Do not drop error handling/fallback or switch to v1 merely because keyboard works |
| HID v4 | mailbox-based rewritten keyboard transport, no external firmware path; Oct 8 wake failure on M4 Pro recorded in IRC | submitted keyboard-only work cannot replace proven 230 trackpad/haptics. Keep type assignment, bounded HIDF parsing, retry state cleanup and exact blob |
| keyboard/trackpad | local `HID_TYPE_SPI_KEYBOARD`/`SPI_MOUSE`, firmware-name child, magicmouse; blob SHA `a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2` | retain exact volatile-use exception. The current daily config has MAGICMOUSE disabled, while 230's config enables it: daily-image integration 301 remains necessary |
| DebugUSB console | live ADT UART IRQ says 360; **measured working Linux input is 816**; local mailbox + TTY + atomic TX + nbcon | measured 816 remains load-bearing. Preserve RX BIT1 separately from MTP BIT3, and no controlling-terminal regression. New FIFO driver is not a drop-in console replacement |
| WiFi firmware/board | local board `apple,mriya`, antenna X3, rev6 using c2 bytes under c0 names; Asahi supports 4388 but max BSS version112 | retain exact local firmware manifest and BSS116 patch; no firmware swap in first candidate. Keep BT and its firmware independently tested |
| USB | local right-port USB2 data path proven; VBUS separately gated 305; native T6040 PHY and exact translated hpm2 `0x509198000` | leave USB/SPMI disabled in first integration profile. Do not import base-M4 ATCPHY fallback, USB4/CIO or broad SN201202x nodes as T6040 support |

Yuka old-HID commits `01334b613f75dbb2ee1bbb8ff705d3af8bf923de`
(workqueue WQ_PERCPU) and `55e130fd…` (no-STM discovery) are concrete references,
not power-v2 fixes. The old-driver board DT includes commented AFE/STM GPIO
suggestions. Comments are not permissions; do not enable them. Local input
already passed touch and haptics, while its daily incorporation remains open.

## 4. Patch/dependency disposition

The companion TSV inventories **every top-level patch**, including diagnostic
and non-kernel exclusions, with its hash. The following is the load-bearing
integration map. `keep/port` means preserve behavior via the patches workflow,
not directly edit the live kernel checkout or blindly apply incompatible text.

| patch / committed delta | disposition on Asahi `2bb9d16f…` | dependencies / concrete work |
|---|---|---|
| `t6040-apple-cpufreq-freq-mult-overflow.patch` | **absorbed downstream** | Asahi uses `frequency * 1000UL + 999`; forward check fails, reverse check passes. Omit patch on this base; preserve DT OPPs and test P-core policy without SMP |
| idle portion of `flokli-code.patch` | **replace with downstream support** | Asahi `idle.c` already handles wfi/yield/nop; patch conflicts. Use `idle=nop`, do not test yield (known hang) |
| WFIT guard in `flokli-code.patch` | **replace with explicit override** | Asahi `delay.c` still calls WFIT/WFET when WFxT is enabled. `arch/arm64/kernel/pi/idreg-override.c` defines `arm64.nowfxt` → `id_aa64isar2.wfxt=0`. Candidate must include both `idle=nop arm64.nowfxt`; `idle=nop` alone is insufficient |
| AIC part of local commit `08c0e68f6e71b9666316cd1b57c480a1f67cf9ba` | **keep/port separately** | New base still writes VM_TMR_FIQ_ENA_EL2 and ICH_HCR_EL2 in aic_init_cpu. `flokli-code.patch` file contains only idle/delay hunks despite harness comment; exporting that file alone loses the AIC guards. No blanket KVM claims |
| `t6040-pmgr-functional.patch`, `t6040-pmgr-t6041-quirks.patch`, bindings | **keep/port**, textual conflict | New PMGR has force-disable/reset changes; functional patch fails context. Preserve current T6041 preserve-active + dispext0/1 AUTO exceptions + disabled internal display CPU node without removing new logic |
| `t6040-pmgr-ans-no-auto.patch` | **exclude** | historical diagnostic did not move the first-read boundary; not a general storage fix |
| local NVMe committed lineage `38645fe8da365a63d5f43dbacbe592376bc59e31`, `6b6d9b4bf73858758504e51cd85b0534f68c836b`, `8dc17800b4dbc182e6a0bc5181833f34e8f528cb` | **keep/port final behavior** | preserve firmware legacy-register and queue-count gates, split resource mapping, restored doorbells/depth from final HEAD. Do not cherry-pick the reverted E1–E10 history wholesale |
| `t6040-nvme-apple-force-clean-ans-boot.patch` | **keep** | applies to captured Asahi source, but test after split port; force clean boot when inherited CPU RUN does not belong to this RTKit instance |
| `t6040-nvme-ans2-ioq-size.patch` | **keep equivalent contract, don't double apply** | patch needs Wallace split port first (fails against bare Asahi). Alternatively port zero-based setup from `6acd…` (textual check passes against Asahi), then add split/gates. Use **one** implementation and compare order/value, not helper names |
| `t8140-sart-power-managed.patch`, `t8140-sart-defer-scan.patch`, SART/ANS binding patches | **retain compatibility where matched; port/check whole pair** | power patch alone applies; deferred scan depends on it. Current T6040+t6000 node doesn't select the power-managed t8140 ops. Don't activate a new power resource or SARTv4 during convergence |
| mailbox/HID base commits in Wallace HEAD (`a97a98ae…`, `79ddb8fc…`, `25a68c4e…`, `cf47872d…`) | **keep mailbox implementation; resolve duplicate symbol** | Asahi already has SoC `CONFIG_APPLE_DOCKCHANNEL` FIFO and `CONFIG_HID_DOCKCHANNEL`. Use exactly one APPLE_DOCKCHANNEL provider: omit its SoC Kconfig/Makefile selection when wiring the legacy mailbox provider; disable HID_DOCKCHANNEL and RTKit-helper path. Do not compile two providers or enable both compatible families |
| `t6040-dockchannel-tty-driver.patch` → `poll.patch` → `atomic-tx.patch` → `nbcon.patch` | **keep as a dependency chain** | preserve old mailbox header/API and measured UART DT. Later UART transport migration needs its own review and observation-channel test |
| `t6040-dockchannel-fixes.patch`, `hid-type.patch`, `trackpad-fw.patch` → `hid-reset-contract.patch` | **keep behavior** | apply to mailbox HID source; preserve bounds checks, type, timeout/error cleanup, nine-byte power messages and exact firmware. Existing patch paths intentionally differ from Asahi's old driver |
| `t6040-dockchannel-rx-rearm.patch` | **conditional, not auto-selected** | preserve selected baseline flag/state; don't add another interrupt experiment while changing base |
| `t6040-brcmfmac-bss-info-v116.patch` | **keep** | forward check passes; Asahi has 4388 chip/firmware selection but BSS maximum112 |
| BCM4388 v1 patches 1–13 | **separate convergence later** | patch9's newer-BSS handling could replace local bound change only as part of reviewed layout parsing; don't layer two BSS policies. Patch4/5/6 overlap downstream PCIe startup/mailbox/signed-firmware paths. Patch10/11 introduce versioned scan/join, patch12 PMK. Preserve port-authorization fix plus board/PCIe and firmware dependencies |
| native USB2 PHY/force-host/PD transport patches | **exclude from first profile; retain in their track** | reviewed 108/231/305 artifacts remain; later refreshed USB image audits RESET_APPLE_CIO, USB4, USB4_APPLE_SOC built-in dependency closure, without claiming TB5 |
| tracing/debug/isolation, modern RTKit crashlog, forced PMGR, threaded IRQ patches | **exclude** | they change experiment conditions or lack a closed review. Crashlog decoder outer-bounds issue remains separate |
| m1n1 / U-Boot / macvdmtool patch sets | **no change** | keep paired tested loader and host client. Refresh/tracing is ticket6003; no loader startup/AMCC workaround bundled with this kernel candidate |

## 5. Smallest source candidate: `LC1-7.2.12-2-local-j614s`

The [machine-readable plan](2026-10-24-upstream-convergence/candidate-plan.json)
pins all source selectors; it intentionally has no bootable artifact hashes
and `runnable:false`. A source pin is not an exact-artifact review.

**Base:** Asahi `2bb9d16f…`. **Local reference:** final Wallace kernel
`4f242910…`, plus the exact dirty-DT snapshots/local patch hashes in the lock.
**Loader/client:** leave the 6001 pairing unchanged: m1n1 source HEAD
`80badc91e62c8b4228a857730f160ffb62a29335` with exact built binary
`7de07c714ebe8b26a408ab0a4719d10d2d208eb120eaac7d3aea03f0e36daf2a`
and its existing reviewed client inventory. No m1n1 refresh is necessary for
the first comparison. Future build must recapture any uncommitted client bytes.

Ordered source assembly (new patch files only, no edits in the shared Linux
checkout; every new patch uses CJ's current author/sign-off):

1. Port **only AIC guards and raw-boot PMGR policy** first. Use upstream
   `idle=nop arm64.nowfxt`; omit duplicate local idle and cpufreq fix. Keep the
   local DT filenames, measured IRQs, display ownership and endpoint-power
   description. Do not import the broad Yuka SoC/board DT stack.
2. Retain the Wallace mailbox/HID/TTY implementation with exactly one
   APPLE_DOCKCHANNEL config/provider and the patch dependency chains in §4.
   Disable the Asahi SoC-FIFO/HID helper consumer chain. Verify the final
   Kconfig/Makefile diff explicitly; merely renaming a file is insufficient.
3. Retain WiFi BSS116 and firmware mapping. Keep modern Asahi WiFi/BT drivers
   otherwise. No BRCM4388 v1 rewrite, firmware update or new PCIe power graph.
4. Port final split-NVMe/gated behavior and zero-based IOQ setup once, plus
   force-clean boot and existing SART compatibility. Keep this code/config
   available for a second DT profile, but **disabled in the first DT**. If
   6001 fails, record that failure and reassess storage selection before an
   LC1 NVMe run; don't conceal it under the base refresh.
5. Produce **LC1-A**: RAM-only, one CPU, input/SMC/WiFi/BT/SD identity and
   read-only SD checks, ANS disabled, SPMI/USB disabled. **LC1-B** differs only
   in the reviewed ANS DT enablement and read-only storage test fixture, after
   6001 and LC1-A evidence pass. No SD-root RW boot in either profile.

No blanket DAPF/PCIe bypass, new display driver, GPU/AVD/audio/suspend, p3s,
4K-process MM, KVM series or secondary-CPU startup change belongs in LC1.
This keeps the cross-version kernel change observable without also changing
the boot firmware or hardware-description model. Hardware-risk reduction,
not minimum line count, defines this candidate's scope.

### Config and packaging gates before any live follow-on

Compare **final post-olddefconfig** values, not the distro Asahi fragment.
That fragment sets NVME_APPLE/SART/PCIe/WiFi/BT/HID and many helpers to modules;
it is not an adequate standalone RAM-root configuration. Current 6001 has
RTKit/NVME_APPLE/SART built in, but intentionally lacks SDHCI-PCI, WiFi PCIe,
BT and magicmouse; it cannot serve as the input/daily-regression image.

Required LC1 built-ins: ARCH_APPLE, ARM64_16K_PAGES, APPLE_AIC,
APPLE_PMGR_PWRSTATE, APPLE_MAILBOX, APPLE_RTKIT, APPLE_DART,
PCIE_APPLE, PINCTRL_APPLE_GPIO, MFD_MACSMC, GPIO_MACSMC, MACSMC_POWER,
SENSORS_MACSMC_HWMON, MMC/SDHCI/SDHCI_PCI, BRCMFMAC/PCIE/MSGBUF,
BT_HCIBCM4377, legacy APPLE_DOCKCHANNEL + APPLE_DOCKCHANNEL_TTY +
APPLE_DOCKCHANNEL_HID, HID_APPLE, HID_MAGICMOUSE, HID_MULTITOUCH,
FW_LOADER, DEVTMPFS, TMPFS, UNIX, simpledrm/fbcon. For LC1-B also
NVME_CORE/NVME_APPLE/APPLE_SART. Reconcile exact symbol names on the new base;
an unknown symbol is a failure, not an ignored config line. Match current
16 KiB page size and SME policy; no unrelated MM options.

Reject enabled nub_spmi0/PMU/RTC/reboot NVMEM dependencies, USB/PD/ATCPHY and
unreviewed peripheral nodes; GPIO_MACSMC remains for only the allowed keys.
Retain `pd_ignore_unused clk_ignore_unused` and existing console arguments,
append `arm64.nowfxt`, keep `maxcpus=1 idle=nop`, `rdinit=/init` and
`console=tty0` last. Check the actual boot Image's hash/markers and paired
firmware rather than assuming a named output updated `$OUT/Image`.

Before build, source preparation must close the textual/API conflicts. Then a
**separate build ticket** must perform two fresh builds, byte-compare
Image/System.map/config/DTBs/initramfs, schema-check/decompile each exact DTB,
review all warnings affecting resources/IRQs/DMA/power/resets, and run existing
image preflight with `--proxy-payload`. No modifications to the canonical
harness or `/out/Image` as a side effect of this audit; use isolated staging and
explicit names. A later live ticket needs hashes, maintainer approval,
independent exact-artifact review, readiness and a lease.

Every image must load the Norwegian binary map before a shell. If it carries
an OpenRC/X root, enforce keymap="no", XkbLayout "no", preferably nb_NO, plus
usable rescue/ttydc0 shells. Preserve fsck.exfat and the dirty-fixture gate in
any root-capable initramfs. Layout compliance applies even to RAM diagnostics.

## 6. Regression sequence and explicit pass/fail gates

| order | prerequisite and change | pass | fail / stop |
|---|---|---|---|
| 0: 6001 | existing payload, CJ-ready signal, its existing reviewed gate | original 16,384 direct 16 KiB reads, repeated-data and counter verdict, first transcript preserved | its current stop conditions; failure remains evidence. No refresh substituted into it |
| 1: offline LC1 source preparation | exact source lock; inspect all compiler-facing API and DT dependencies | ordered patch series applies to the pin; one FIFO provider; expected final source contracts; complete delta review | unresolved Kconfig symbol duplication, unknown mapping/power requirement, unexplained DT change or unpinned source blocks build handoff |
| 2: isolated build/review | separate scoped build ticket after source preparation | two fresh identical builds, config assertions, clean relevant schema/decompile review, preflight and independent exact-member review | any artifact mismatch, missing map/driver/firmware, unknown schema resource warning, wrong boot Image |
| 3: LC1-A RAM first light | approved exact ticket, fixture identity/boot-volume firmware reconfirmed; one CPU; ANS/SPMI/USB disabled | ttydc0 plus panel console; SMC telemetry; GL9755 and only expected endpoints; keyboard; touch **and haptics** with maintainer finger/click; second open no re-upload; Norwegian symbols | console loss, WFI-related hang, unexpected provider, DART/SError/panic/reset; stop and archive first transcript |
| 4: LC1-A read-only SD/network | same one-CPU candidate; exact SD identity; no fsck/RW mount | read-only data comparison/checksum on identified SD64, no new error counters; WiFi scan/association/DHCP/routed traffic, BT hci0 functional; no PMGR/lockdep regression | dirty/read failures don't authorize repair here: 215/216 own it. Missing subsystem first triggers artifact/config audit. Network success does not prove Bluetooth |
| 5: LC1-B NVMe | 6001 result accepted, LC1-A pass, exact new DT/test hashes separately approved | real controller **and namespaces**, state reaches LIVE; same 6001 read-only workload crosses many CQ wraps, data identical and no counter/error delta; repeat fresh boot | NEW stuck distinguishes state regression; CQ-wrap assert distinguishes local bug. No filesystem mounts, namespace writes, reset/controller experimentation beyond ticket; stop at first fault |
| 6: daily integration | 301 input and 215/216 SD gates, LC1 single-CPU evidence | repaired fixtures, hardened shutdown, read-only post-shutdown checks and complete daily services under existing tickets | no daily promotion or enrollment based on one RAM boot. Keep current rollback |
| 7: fault205 separately | LC1-A/B one-CPU gates complete; original uninstrumented reproducer and storage-free artifact (217), independent live ticket | matched one-vs-two-CPU matrix, fresh boot per variant, at least four repetitions each; archive CPU/topology and oops/result | any fault kills the SMP promotion; a clean matrix supports further testing, **does not establish root-cause fix**. Never run SMP with writable storage |

For step7 pin `scripts/t6040-cow-repro.sh` unchanged (hash in source lock),
use the original heap/fork workload, no validation printk/barrier/volatile
pre-copy instrumentation, and record whether the workload itself finished.
Use controlled topology DTs only after their exact review. Keep kernel, loader,
DT topology, drivers and workload fixed except the intended CPU-count variable;
then isolate kernel versus loader changes in separate fresh-boot matrices if
needed. Ticket209 owns victim-topology questions; don't silently broaden its
approval. The one-core storage/input gate precedes **all** SMP experiments.
Secondary startup and PMU/GIC SEIS guest fixes cannot close native fault205.

Global live stops remain SError, DART fault, firmware panic, unexpected reset,
console loss before the boundary, artifact/fixture mismatch, unauthorized
access or writes. Preserve the first transcript, then recover by the sanctioned
path under the lease. NVMe writes remain a later, separately reviewed ticket,
limited to the exFAT `linux` partition verified by **both label and GPT type**;
no write permission is created by LC1.

## 7. Remaining uncertainties and next executable action

1. Deleted historical working-branch heads cannot be pinned from the present
   public ref inventory. Components are real source comparisons but don't prove
   an exact externally tested J614s composition or its boot-volume firmware.
2. The b4 DT branch is a rebase, not an independently matched original mail
   series. Mainline/Asahi lack the T604x target at the inspected pins.
3. Single-aperture reg9, wider SART/AP-GPIO/AIC windows, SD port02 and helper
   HID DMA/SRAM semantics remain migration questions; current local behavior
   stays in LC1. No inference of universal MMIO exclusivity is made from the
   proven split.
4. PMGR and mailbox/Kconfig ports need source assembly, compilation and schema
   work. This audit supplies exact before/after contracts, not compile success.
5. Public J614s benchmark success used an HV/modified-loader environment;
   direct-boot durability and Wallace's CQ-wrap result remain local gates.
6. Neither startup work nor KVM SEIS establishes a runtime MM/COW fix. No
   accelerated G16, T6040 TB5 or display/audio/suspend completion is inferred.

**Next hardware action is still 6001**, once CJ signals readiness. **Next
offline action is source assembly of LC1 from this source lock** through the
Wallace queue, resolving the named PMGR and duplicate-FIFO conflicts and
reviewing the final deltas before opening a separate build/live gate. Ticket
6002's research/map/plan deliverable is complete; none of these follow-on gates
is implicitly approved or marked passed.
