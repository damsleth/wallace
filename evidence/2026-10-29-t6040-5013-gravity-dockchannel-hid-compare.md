# 5013: Gravity DockChannel HID comparison (2026-10-29)

**Result:** No available Gravity FIFO change establishes a fix for the 2/11 pre-enumeration stalls. The best discriminator is where bytes stop: MTP production, FIFO/IRQ delivery, frame parsing, or STM/interface creation. `IPD HIDSPI attached` is an RTKit firmware message, not proof Linux received an INIT frame. C2/C10 consoles are on the Mac host and were not available here.

**Scope and limits:** Compared the locally available `origin/replacement/090-spi-hid:drivers/hid/dockchannel-hid/dockchannel-hid.c` with Wallace's named patches and `scripts/t6040-kbuild.sh`. Gravity's `d4e7c10c30` and `187be74189` commit metadata is local, but their diffs require missing blobs; `git show` attempted lazy fetching and was stopped. The 187 README and test are under `drivers/hid/dockchannel-hid/`, not repository root, and their contents are unavailable. Thus exact commit attribution, the README's M4 Max bring-up description, and full base-driver equivalence are **unverified**. No network was intentionally used. The branch-tip file is later than the named commit and also includes T8140 ring support; T6040 is FIFO. Wallace imports a different mailbox/HID series at build time; its base source is unavailable here, so absence from local patches alone does not prove absence from the built image.

| Gravity branch-tip behavior | Wallace equivalent / relevance |
|---|---|
| `dchid_frame_size`: header length 8 and 4-byte aligned body; called in **ring drain**, not FIFO. FIFO checks header length separately, then reads `hdr.length + 4`; no call to this helper. | No equivalent added in named patches; check imported source. Ring validation cannot be claimed as a T6040 FIFO fix. Invalid FIFO length could desynchronize/block the stream; no observed evidence yet. |
| Checksum sums header, body including opaque padding, and checksum; accepts only `U32_MAX`, logs mismatch. TX pads with zeroes and includes padding in checksum. | No comparable change in named patches; inspect imported source. Compare checksum errors in consoles; don't infer padding was rejected without packet evidence. |
| `MAX_INTERFACES` 32 (working-tree snapshot was 16); index bounds checked. | Named patches do not raise limit; verify imported source and actual INIT indices. Only relevant if a required index is 16–31; does not explain a missing first frame by itself. |
| `MAX_PKT_SIZE = 8 + 0xfffc + 4`, sized for largest aligned frame. | No equivalent in named patches; compare actual receive buffer and limits in imported source. Branch-tip FIFO does not use `dchid_frame_size` to enforce alignment before read. No evidence of oversized INIT. |
| ACK matches flags, sequence and report; branch tip treats `hdr->pad >> 8` as `-EIO`, otherwise uses subheader retcode, and logs nonzero result; command timeout 1000 ms, start timeout 2000 ms. | Wallace state trace records ACK/match/retcode; reset-contract explicitly handles `-EIO` for power-request fallback. Check base ACK semantics. A rejection or timeout matters only after a command is issued; inspect actual logs. |
| STM ready fetches ID/serial then releases deferred interfaces; helper must be bound before transport setup; no general FIFO bring-up retry visible. | Wallace trace records INIT/READY, STM results and queued/deferred/create state. Compare base probe ordering; no evidence Gravity has a FIFO retry for this stall. |
| FIFO uses v1 `0x40` post-firmware power request; T8132 ring uses v2 pair. | Wallace `hid-reset-contract` uses v2 pair with v1 fallback for T6040, after firmware upload on open. This is later than the missing initial interface configuration; not a demonstrated cause of 5013. `trackpad-fw` concerns upload, not initial keyboard enumeration. |
| FIFO transport vs ring `0x91` registration and notify. | Ring is not a T6040 mitigation. Wallace `poll` supplies per-instance masks and optional polling; `rx-rearm` addresses a proposed RX acknowledge/drain race but is opt-in (`HID_RX_REARM=1`); `irq-guard-debug` is diagnostic, not proof of recovery. Verify actual build and DT mode. |
| HID types keyboard/mouse and `.stop` exist in Gravity. | Wallace `hid-type` and `fixes` supply equivalents; these act during/after HID creation, not a missing first INIT. |

Gravity 187's commit message describes M4 Max hardware testing, Neo compile coverage only, and incomplete board/thermal qualification. Its README details and input-watch behavior cannot be verified without its missing blobs; this is not evidence of repeated T6040 cold-boot reliability.

## Ranked hypotheses and checks

| Rank | Hypothesis | Concrete offline / existing-log check |
|---|---|---|
| 1 | First INIT is not delivered or serviced: MTP startup timing, FIFO/IRQ or polling, including a lost wakeup. Both devices fail together. | On Mac host compare timestamped C2/C10 with C1/C3/C9/C11 from `linux-build-out/nvmeroot-20261025/runs/*/dcuart-console.log`: helper/probe, poll/IRQ mode and masks, RTKit messages, first INIT, errors and subsequent output. Confirm exact Image/DTB and build flags; check DT for `apple,poll-mode`. Absence of logged INIT alone cannot distinguish firmware silence from lost RX. If existing trace-enabled runs exist, compare `dc_trace` RX counts/bytes and `hid_trace` callbacks. |
| 2 | Bytes arrive but a malformed, incomplete or checksum-failing FIFO frame prevents dispatch or leaves parser waiting. | Search the same logs for bad header, checksum, read failure, timeout and warnings; inspect imported build source for frame bounds, partial buffering, padding and checksum. Compare trace `rx_bytes`, `rx_buffered`, `packets`, `events` if present. A clean console without trace is inconclusive. |
| 3 | INIT arrives but STM readiness, ACK matching or interface creation fails and leaves dependent interfaces deferred. | Compare INIT/configuration, STM ready/ID/serial, enable-command timeout/error and creation messages. Existing `HIDTRACE` fields `init_seen`, `ready_seen`, `ack_matches`, `deferred`, `create_ok` distinguish stages if that diagnostic was actually built; normal logs may not expose them. |
| 4 | An index >=16 or large frame exceeds Wallace limits. | Inspect successful INIT indices and sizes in any existing trace or packet capture, and the exact built base source. Gravity's larger limits are a hardening candidate only if a required value exceeds Wallace's actual limits. |
| 5 | Post-upload v2 power contract / missing firmware. | Confirm the stalled boots never reach interface creation/open or `sending firmware`; compare C11. This is a separate, later trackpad-only failure and cannot alone explain missing keyboard and all interfaces. |

## Minimal candidate, not applied

First add a bounded, observation-only delayed diagnostic after transport initialization: once, if no INIT has been dispatched, log transport mode, RX callback/byte and parser-buffer counts, packet/event counts, and INIT/READY/ACK/STM state using the existing state-trace mechanisms. Avoid reads of new MMIO, resets, firmware writes, or automatic command replay. Host-test parser size/checksum cases against captured or synthetic frames and check the exact built source first. If the evidence specifically shows pending FIFO bytes with no RX service, separately review the existing RX-rearm change for that mode; if a command times out, design a bounded retry only for that identified, demonstrably safe command, with sequence/late-ACK handling. Neither is established as a fix by this comparison.

## Reviewer addendum (claude, same day)

The body above was drafted by Codex (gpt-6.1-terra). It could not read
`187be74189` or the T6041 MTP DT, but both resolve offline (blobs cached).
They change the picture:

- **M4 Max (T6041, J616c) uses the M4-family shared-ring transport, not the
  FIFO ABI.** `t6041-mtp.dtsi` (`origin/replacement/000-devicetree`) gives
  `mtp_hid` the compatibles `apple,t6041-dockchannel-hid`,
  `apple,t8132-dockchannel-hid` with the comment "M4-family shared-ring
  transport, rather than the older FIFO ABI". The driver sets
  `use_ring` from `apple,t8132-`/`apple,t8140-dockchannel-hid`
  (`dockchannel-hid.c:1271` at `origin/replacement/090-spi-hid`).
  `README.m4max-bringup.md` says "No separate Max HID protocol implementation
  was needed". On the M4 Max, the keyboard (77/77 presses) and trackpad (314
  touch reports) work with **all 16 CPUs**.
- **Same MTP block as ours.** The Max MTP ASC is at `0x514600000`, DART
  `0x514800000`, DockChannel IRQ `0x514b14000` and mailbox `0x514608000`
  with IRQs 792–795 empty/not-empty, all identical to `dts/t6040.dtsi`. The
  child window is `ranges = <0 0x5 0x14b28000 0x10000>` with
  `rmt-config`/`rmt-data` at `+0x0`/`+0x4000` and `config`/`data` at
  `+0x8000`/`+0xc000`. Our `config`/`data` (`0x514b30000`/`0x514b34000`)
  are the same two pages. We do not describe the `rmt-*` pages that the ring
  transport uses.
- **DART SID remap.** The Max DT has `apple,sid-remap = <1 0>, <2 0>, <3 0>`
  on `mtp_dart` (binding from `replacement/020-dart` `27c2f74099`). Ours has
  none.
- **Consistency with 230.** Ticket 230 found that J614s accepts only the 9-byte
  v2 interface power request. In Gravity's driver that v2 pair belongs to the
  **ring** path, and the FIFO path sends v1 `0x40`. That points to T6040 MTP
  firmware speaking the M4-family ABI, with our FIFO transport as the older
  path patched to send v2.
- The ring path registers a 2 MiB DMA ring (`CMD_REGISTER_RING 0x91`,
  preceded by `{0xc1, 0x02}`). It also sends the reset-interface pair state 0
  then 2, each with byte 4 = 0 then 1, and skips the host GPIO reset.

**New top hypothesis for 5013:** the intermittent stall is a race in using the
legacy FIFO ABI against M4-family MTP firmware. The candidate is to move
J614s to the ring transport, which needs these steps:
(a) port Gravity's `dockchannel-hid.c` ring path, `d4e7c10c30` on
`replacement/090-spi-hid`;
(b) restructure the J614s DT to the Max layout, with the `rmt-*` pages and the
`t8132` compatible;
(c) take the DART `sid-remap` support from `replacement/020-dart`;
(d) re-run the 230 trackpad and haptics checks.
The `rmt-*` pages and the SID remap must first be confirmed in our own J614s
ADT (`/arm-io/mtp` and `dockchannel-mtp` nodes). This needs a rig run with CJ
approval, and stays a hypothesis until a ring-mode boot series beats 9/11.
