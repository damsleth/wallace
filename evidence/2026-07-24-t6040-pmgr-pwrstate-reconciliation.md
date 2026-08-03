# T6040 PMGR pwrstate active/inactive reconciliation — ticket 085 (2026-07-24)

Reconciles our 214-domain T6041 PMGR quirk with yuka's #asahi-dev concern
(07-22/07-24): that the t6040 (J614s) ADT carries t6041's extra memory-channel
and dispext domains "still present and active (!no_ps)", suggesting a missed
active/inactive encoding. Parsed the actual J614s `/arm-io/pmgr` `devices` blob
(485 entries) with m1n1 `adt.py` (`PMGRDeviceFlags`/`PMGRDevices`).

## Finding: the `no_ps` flag already encodes the t6040-vs-t6041 difference

adt2dt (`proxyclient/tools/pmgr_adt2dt.py`) emits a pwrstate node **only for
`!no_ps` devices**. On the J614s ADT the `no_ps` flag is set exactly on the
domains t6040 silicon lacks:

**Memory channels (DCS = DRAM channel):**
- `DCS_00..DCS_15` → `no_ps=0` (emitted) — **16 channels = M4 Pro's 256-bit bus.**
- `DCS_16..DCS_31` → `no_ps=1` (NOT emitted) — the M4 Max (t6041) 512-bit extras.
- (All DCS are `on=1, critical=1` — firmware always-on.)

**External displays:**
- `DISPEXT0_{SYS,FE,CPU}` and `DISPEXT1_{SYS,FE,CPU}` → `no_ps=0` (emitted) —
  **2 external display controllers = M4 Pro.**
- **`DISPEXT2_*` and `DISPEXT3_*` → all `no_ps=1` (NOT emitted).** So
  `ps_dispext3_cpu` is never produced — matching yuka's "the t6040 I tested does
  not really have that node."
- `DISP_{SYS,FE,CPU}` → `no_ps=0` (the internal panel), the rest of `DISP_*`
  `no_ps=1`.

So **there is no over-count on J614s**: the phantom t6041 domains (DCS_16-31,
DISPEXT2/3) are already `no_ps=1` and adt2dt drops them. The "new encoding that
marks devices active/inactive" is the existing **`no_ps` flag**, and on this ADT
it is set correctly. (Flag census across 485 devices: 271 are `no_ps=1`;
`b7/b6/b2` are essentially unused — 3× b7, 1× b2 — so there is no *additional*
hidden active/inactive bit beyond `no_ps` + `on`.)

## Our quirk is consistent with the flags

The three display-CPU domains that are **emitted** (`no_ps=0`) and **off at boot**
(`on=0`) are exactly `DISP_CPU`, `DISPEXT0_CPU`, `DISPEXT1_CPU`. Our quirk
disables `disp_cpu` and skips auto-enable on `dispext0_cpu`/`dispext1_cpu` —
i.e. it acts only on real, firmware-off display-CPU domains (force-enabling them
pre-console hangs, the empirical 3/3 result). `preserve-active` reads the real
power-state registers at Linux probe time; it never sees the phantom domains
because they are `no_ps=1` and unemitted. **No phantom domain is emitted or
preserved.**

## Conclusion + collaboration note

1. On **J614s** the `no_ps` encoding is correct and self-consistent; our PMGR
   quirk does not over-count and is aligned with the ADT. No change needed to
   the quirk on account of yuka's concern.
2. yuka is on **j773s** (t6040 Mac Mini). Either that board's ADT sets `no_ps`
   differently, or the concern conflates "present in the 485-device list" with
   "emitted (`!no_ps`)". **Draft-for-CJ to yuka:** on J614s, `no_ps` already gates
   DCS_16-31 and DISPEXT2/3 — ask them to check the same flags on the j773s ADT;
   if those differ, that's a board/firmware delta, not an adt2dt bug. (Agents
   don't post; CJ sends.)
3. The upstream-correct shape stays: **trust `no_ps`** (adt2dt already does) plus
   our empirically-necessary display-CPU auto-enable skip. `preserve-active` is a
   safe superset given every phantom domain is unemitted.

Parse method: `adt.py` `PMGRDevices` over `/arm-io/pmgr.devices`; exact live ADT
SHA-256 `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`.
The complete flag distribution and evidence table are in
`done/2026-07-24-t6040-pmgr-active-encoding.md`. No rig, no writes. Ticket 085
done.
