# Upstream review 2026-07-28: NVMe is probably NOT SPTM-blocked, and D2 is confirmed by merged upstream

Offline research pass over yuka's `feature/t8132-nvme` branch and current upstream m1n1, prompted by
CJ. Everything load-bearing below was **re-verified locally** against our own captured ADT and our own
recorded fault logs — the provenance of each claim is marked.

## 1. NVMe: our "protected, needs SPTM" conclusion rests on writes aimed at the WRONG BASE

**This is the biggest finding of the session and it reopens internal storage.**

yuka's commit `8874ce87` ("nvme: use dedicated nvmmu base") states that on M4 and later the ANS
register layout splits: **`ans` reg[3] becomes the NVMMU window and the NVMe controller registers move
to reg[9]**. Her `fd883241` additionally skips two legacy writes on firmware ≥ 15.0:
`NVME_LINEAR_SQ_CTRL` (`+0x24908`) and `NVME_UNKNOWN_CTRL` (`+0x24008`).

### Verified locally (not taken on trust)

Our captured J614s ADT (`linux-build-out/j614s-usb-port-map-20260721.adt`) — `/arm-io/ans` has
**exactly 10 reg entries**:

| reg | bus | CPU-physical (+0x200000000) | size |
|---|---|---|---|
| 3 | `0x20dcc0000` | **`0x40dcc0000`** | `0x60010` |
| 9 | `0x24dcc0000` | **`0x44dcc0000`** | `0x10000` |

So the layout yuka describes **exists on our machine**. And `0x44dcc0000` is precisely the window our
own 2026-07-13 session called "the secure BAR … a separate 64 KiB window", read successfully
(AQA `0x000f000f`, ASQ `0x101005db000`, ACQ `0x101005dc000`, CC `0x00474000`, CSTS `0`) — and then
**never wrote to**, because we had classified it as iBoot's protected state rather than as *the NVMe
controller aperture*.

Our own m1n1 SError, arithmetic re-done from the recorded value in
`evidence/2026-07-25-t6040-nvme-probe-result.md` (`L2C_ERR_ADR: 0x28360040dce4908`):

```
low 36 bits      = 0x40dce4908
ans reg[3] (CPU) = 0x40dcc0000
offset           = 0x24908  == NVME_LINEAR_SQ_CTRL   -> MATCH
```

**Our fault was exactly the register yuka's firmware gate now skips.** Because the SError happened
there, everything before it — `asc_init`, `sart_init`, `rtkit_init`/`rtkit_boot`, and the
`BOOT_STATUS == 0xde71ce55` check — had already **succeeded** from raw m1n1 on T6040. Our probe
result's conclusion ("m1n1 cannot bring ANS up either … the protection is enforced below the OS") is
**not supported by that fault address**. Timeline note: our probe ran 2026-07-25, yuka's fix landed
2026-07-26, so our loader could not have contained it.

The same register explains the Linux-side failure too: `evidence/2026-07-13-t6040-nvme-map.md:513`
records "a same-value write to linear-SQ control faults" — same `0x24908`, different code path.

### What this does and does not overturn

- It does **not** invalidate the SPTM/service-6 decode (tickets 051/052/054/055). That remains a
  correct description of what *macOS* does.
- It **does** undercut the inference that no non-SPTM path exists for us. The two Linux faults we
  used to justify that (`MAX_PEND` at reg3+0x1210, AQA at `0x40dcc0000+0x24`) were both aimed at the
  **NVMMU** base; the NVMe controller aperture at reg[9] was never targeted.
- **Caveat, stated plainly:** reg[3] is not a clean "NVMMU-only" window — our reg[3]+`0x1300`
  boot-status poll *succeeded* while reg3+`0x1210` faulted. Do not adopt a strict two-window model.
- yuka's target is t8132 (plain M4, J773g Mac mini); ours is t6040 (M4 Pro, J614s). The reg-layout
  change looks generation-wide and our ADT matches, but "identical on t6040" is inference, not fact.
- I could not verify from the repo alone that yuka has a completed end-to-end `nvme_read` on M4. The
  supporting evidence is circumstantial but strong: her `cdw12` NLB fix (PR 637) and the
  `0x1200`/`0x1208` I/O-queue shadow-write fix (`11158bbb`) are both bugs only discoverable by
  actually running I/O on M4 silicon.

### Next step — attended, and it needs a fresh approval decision

The decisive experiment is cheap: rebuild m1n1 with the two changes (two-base split + FW gate) and
re-run the existing read-only `scripts/t6040-nvme-probe.py`. **But it is not read-only at the
controller level:** `nvme_ctrl_disable()`/`enable()` cycles `CC.EN` on the controller that holds
macOS, and `11158bbb` rewrites its I/O-queue base pointers, on the window currently holding iBoot's
authorized queues. There is no namespace-write opcode in the path, but this is a controller state
change on the boot SSD and must not be filed under "just NVMe init". Also note every error path calls
`pmgr_reset(nvme_die, "ANS")` — a PMGR reset write.

**Recommendation:** treat as a new ticket requiring explicit CJ approval of the `CC.EN` cycle
specifically. Do not run it on the assumption that the old NVMe plan approval covers it.

### Bug worth reporting upstream (draft for CJ; agents do not post)

`8874ce87` gates the reg[9] read on `if (reg_len >= 10)`, but `adt_getprop` returns a **byte** length
and an `/arm-io` reg entry is 16 bytes — our node reports 10 entries = 160 bytes. Any pre-M4 machine
with ≥1 entry also passes `>= 10`, then `adt_get_reg(index 9)` fails and `nvme_init` returns false.
It works on M4 by accident and would regress M1/M2/M3. The fix is a one-liner
(`reg_len / 16 >= 10`, or compare against `10 * 16`).

## 2. PCIe: delta D2 is independently confirmed — and it is already MERGED upstream

Verified directly in `upstream/main:src/pcie.c` (fetched this session):

```c
#define APCIE_PHY_CTRL_RESET_T8103 BIT(7)
#define APCIE_PHY_CTRL_RESET_T8132 BIT(4)
...
} else if (adt_is_compatible(adt, adt_offset, "apcie,t6040")) {
    state->pcie_regs = &regs_t8132;          /* .phy_ctrl_reset = ..._T8132 */
```

So today's delta **D2** (clear BIT(4), not t602x's BIT(7)) — which I derived from the macOS
kernelcache — was independently derived by yuka and merged upstream (PR 633), with an explicit
`apcie,t6040` match. Two independent derivations agreeing is much stronger than my single
disassembly pass, and D2 should now be considered established.

**Uncomfortable corollary:** `docs/NEXT_STEPS.md`'s ticket-046 audit already said upstream
"already added initial T6041 identity and **T6040's moved PCIe reset bit**". That knowledge was in
our own docs and neither I nor the earlier PCIe sessions applied it to our fork, which kept clearing
BIT(7) for t6040 through every op-115 run. The decode work was not wasted (it produced D1, and the
op-115/tunable-semantics corrections) but D2 cost a full kernelcache decode to rediscover something
we had already written down.

### What upstream has that we lack, and vice versa

Our fork is **13 commits behind / 94 ahead** of `upstream/main`. Relevant deltas:

| | upstream/main | our fork |
|---|---|---|
| `apcie,t6040` match → `regs_t8132` | yes | no (local `regs_t6040`) |
| PHY reset bit | **BIT(4)** (correct) | BIT(7) until today's `19edc72b` |
| `fuse_idx` | 5 (unused, `fuse_bits = NULL`) | unset → defaults to 0 (ECAM); harmless only because `fuse_bits` is NULL |
| clkgen/CIO3 PLL enable+lock (ticket 058, PLL proven to lock) | **absent** | present |
| D1 `clkgen[0] \|= BIT(5)` | absent | present (today) |
| Diagnostic early-`return -1` scaffolding | absent | present (blocks link-up by design) |
| GXF guarded-stack fix (`2ea75b66`) | yes | no |
| ATC `LN?_RX_TOP_USB_EQA` offsets (`639e0506`) | yes | no |

**Strategic recommendation for the next PCIe candidate:** base it on **upstream's** t8132/t6040 path
rather than our diverged fork — upstream's is the shape that reportedly works on M4 hardware and has
no early returns — then add our clkgen PLL sequence and D1 on top, and drop the diagnostic
scaffolding. Caveat: upstream's t8132 path was presumably validated on plain M4 (t8132), **not** on
M4 Pro (t6040), which has more CIO3/PCIe blocks; and because upstream has no early return, booting
it performs the full PHY + port sequence, so it is an **attended** run either way.

Note also that upstream reaching PCIe link-up on M4 *without* any clkgen PLL work is evidence that
our ticket-058 clkgen sequence may not be a precondition at all — which would make the op-115 hang
attributable to the reset-bit error alone. That is a hypothesis the upstream-based candidate tests
directly.

## 3. Other upstream movement relevant to our frontiers

- **GXF (`2ea75b66`, merged):** `_gxf_init()` was given each GL stack's base instead of
  base + `GL_STACK_SIZE`, so the first push landed below the allocation and silently corrupted the
  heap. Any of our GXF/GENTER experiments predate this fix. It does not by itself explain our GENTER
  hang (we measured `GXF_CONFIG_EL1 = 0`), but pick it up before any retry.
- **USB / Type-C (our VBUS frontier):** PR **594** open — `tps6598x: add spmi transport`; PR **636**
  open — `tps6598x,usb: factor out hpm iteration`; PR **639** open — `atc-phy,t8132` tunables
  (reuses the t8122 table, aliases `tunable_ATC0AXI2AF` → `tunable_ATCAXI2AF`). These are the
  maintainable long-term route for role/VBUS that ticket 170 anticipated; our SWDF path remains the
  fast test. Worth an audit before the next HPM candidate — note our standing rule not to run
  yuka's HPM branch wholesale still applies.
- **ATC EQA offsets (`639e0506`, merged):** fills previously-`TODO` `LN0/LN1_RX_TOP_USB_EQA`
  (`0x9000`/`0x10000`), relevant to ticket 170's data path.

## 4. Provenance

- Verified by me this session: the ADT reg-entry table and reg[9] address; the SError offset
  arithmetic; upstream's `BIT(4)`/`apcie,t6040`/`regs_t8132` source; upstream's absence of any
  clkgen/CIO3 handling; our fork's 13-behind/94-ahead divergence.
- From the research pass (not independently re-derived here): the per-commit contents of yuka's four
  NVMe commits, the PR numbers/states, and the `reg_len >= 10` byte-vs-count analysis (though the
  16-byte entry size and our 160-byte length are consistent with it).
