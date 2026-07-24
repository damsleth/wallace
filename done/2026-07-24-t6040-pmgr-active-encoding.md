# T6040 PMGR active/inactive encoding reconciliation

Date: 2026-07-24  
Ticket: 085  
Scope: offline parse of the exact live J614s ADT; no rig or MMIO

## Result

The suspected T6040 over-count does **not** reproduce on this machine. The
current m1n1 48-byte PMGR-device parser reads the active/inactive distinction
correctly from the existing first-byte `no_ps` bit (`0x10`), and the generated
214-domain DT excludes the T6041/Max-only memory and display domains.

This means there is no evidence for a new parser bit or a topology patch in
Wallace. The proven preserve-active/skip-auto-enable quirk is not superseded:
it controls Linux behavior for the real J614s domains and solves a different
raw-boot ownership problem.

## Ground truth

Input:

```text
/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt
size: 606208 bytes
SHA-256: 7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
```

This is the ADT captured directly from the live Mac16,8/J614s via the approved
read-only ticket 057 procedure. It reports 485 PMGR device records, each 48
bytes. m1n1 parses 214 records with `no_ps = 0` and 271 with `no_ps = 1`.

The raw first-byte distribution is:

```text
00:92 01:23 02:13 03:1 06:1 08:3 09:78 10:209
11:10 12:20 19:32 80:1 82:2
```

## Chop evidence

The relevant groups have an exact paired pattern:

| Family | J614s records with a power state | Inactive records | Flag transition |
|---|---|---|---|
| AMCC | `AMCC0..15` | `AMCC16..31` | `0x09` → `0x19` |
| DCS | `DCS_00..15` | `DCS_16..31` | `0x09` → `0x19` |
| display extension | `DISPEXT0/1_{SYS,FE,CPU}` | every `DISPEXT2/3_*` record | `0x00/0x02` → `0x10/0x12` |

`0x19 - 0x09 = 0x10` and `0x12 - 0x02 = 0x10`: the only changed flag is
the already-named `no_ps` bit. The inactive display groups each include SYS,
FE, CPU, DBE, GP0, GP1, GPL, PPP, and DSC. Their offsets remain in the ADT as
descriptive/virtual topology, but they are not power-state registers.

The generated
`arch/arm64/boot/dts/apple/t6040-pmgr.dtsi` contains exactly 214
`power-controller@...` nodes. It contains AMCC/DCS 0–15 and
`dispext0/1_{sys,fe,cpu}`; it contains none of AMCC/DCS 16–31 or any
`dispext2/3` node. Regeneration with the current `pmgr_adt2dt.py` gives the
same exclusion.

## Relationship to the live PMGR quirk

The real J614s `dispext0_cpu` and `dispext1_cpu` records are `no_ps = 0`.
The 2026-07-12 matrix established independently that:

- legacy full-PMGR policy fails 3/3;
- preserve firmware-active domains;
- disable `disp_cpu`; and
- skip auto-enable only for those two real dispext CPU domains

boots 3/3. Removing either CPU exception fails. Since the inactive
`dispext2/3` and upper AMCC/DCS records never enter the DT, that result cannot
be an accidental workaround for their presence. Preserve-active remains a
raw-boot handoff/ownership policy, not an inactive-record decoder.

## Reconciliation with the IRC report

The 2026-07-22/24 report said a tested “t6040 ADT” appeared to keep the larger
memory/dispext set active under the current interpretation, including a
nonexistent `ps_dispext3_cpu`. Our exact J614s/25F84 capture shows the opposite:
`DISPEXT3_CPU` is flag `0x10`, and therefore absent from the generated DT.

The most likely remaining explanations are a different board/firmware ADT, a
different generator/parser revision, or SoC-name shorthand referring to a
different chop. We cannot choose among them without yuka's exact ADT hash and
device-record bytes.

Draft for CJ to send, if useful:

> On our live Mac16,8/J614s 25F84 ADT (606208 bytes, SHA-256
> 7a92e6e4...), the existing PMGR flags do encode the chop: AMCC/DCS 0–15 are
> 0x09 while 16–31 are 0x19 (`no_ps`); dispext0/1 SYS/FE/CPU are 0x00/0x02,
> while all dispext2/3 entries are 0x10/0x12. Current adt2dt emits 214 domains
> and no dispext2/3. Which model/firmware and PMGR record layout showed them
> active for you? I can share a redacted per-record table.

Project policy forbids agents from posting this externally; CJ decides whether
to send it.

## Decision

1. Keep the current `no_ps` parser and 214-domain generated topology.
2. Keep the proven T6041-compatible preserve-active/dispext0/1 CPU quirk.
3. Do not add another “inactive” flag or prune domains by name.
4. Reopen only if a second exact ADT demonstrates a different record encoding;
   require its board, firmware build, ADT hash, struct size, and raw flag bytes.
