# The DockChannel TTY driver was never in version control (ticket 159), and why 153 failed

Two findings from chasing why a "registered" `ttydc0` console produced nothing on the host.

## 1. `console=ttydc0` matches nothing — 153's premise was wrong

The shipping driver, `drivers/tty/apple_dockchannel_tty.c`, contains **no `register_console`, no
`struct console`, no `CON_*` flags**. It is a **TTY only**. Therefore:

- `/dev/ttydc0` exists, so a **userspace getty** works — that is how the ticket-147 B0 health report
  reached the host, via `scripts/t6040-b0-ttydc0-console` waiting for the device and running a getty;
- `console=ttydc0` on the kernel command line matches **no registered console**, is silently ignored,
  and **no kernel dmesg ever reaches the host**. Exactly the observed silence.

`patches/t6040-dockchannel-nbcon.patch` *does* add a real console (`register_console`,
`CON_PRINTBUFFER | CON_NBCON`, `name = "ttydc"`, `index = id`) — but it, and
`t6040-dockchannel-atomic-tx.patch`, are **never referenced by `scripts/t6040-kbuild.sh`**, so they
have never been applied to any build.

**My error, and its shape is today's recurring one.** I verified the DTB node existed, and I verified
the console name inside a patch — but not that the *shipping* driver registers a console. I checked
things adjacent to what mattered.

### Correction to an earlier explanation

I attributed the duplicated dmesg and ghosted glyphs on the panel to *two* `CON_PRINTBUFFER`
registrations (tty0 + ttydc0). That cannot be right, because ttydc0 never registers. The duplication
is the **single** normal replay when fbcon takes over from the boot console
(`Console: switching to colour frame buffer device 189x59`), and the glyph corruption is fbcon being
written from the replay and live-printk contexts. So it is **not** caused by adding `console=ttydc0`
and would appear on the plain object too.

## 2. The driver existed only inside the container (ticket 159)

`git status` in `/build/linux-keyboard`:

```
 M drivers/tty/Kconfig
 M drivers/tty/Makefile
?? drivers/tty/apple_dockchannel_tty.c
```

A 464-line driver plus 10 lines of Kconfig/Makefile, present in **all three** build trees
(`linux-keyboard`, `linux-b0-diet`, `linux-b0-dietcap`) and in **no version control** — not
`~/Code/linux`, not `patches/`.

Consequences:

- **a rebuild from a clean checkout silently produced a kernel with no `/dev/ttydc0`**, losing the
  DockChannel shell and the transport every B0 acceptance run reports through;
- it is why every built kernel reported a **`-dirty`** version;
- the two patches that *modify* this driver (`earlycon-debug`, `nbcon`) could never have applied to a
  fresh clone, because their target file was untracked;
- the DIET assertion "verified" `CONFIG_APPLE_DOCKCHANNEL_TTY=y` by grepping `.config` text, which
  passed because kbuild's `scripts/config -e` had written it — while the capability existed only by
  virtue of untracked files. **Another guard validating a string rather than a capability.**

### Recovered

`patches/t6040-dockchannel-tty-driver.patch` now carries it, and `t6040-kbuild.sh` applies it
**before `olddefconfig`** so the Kconfig symbol is real rather than dead text. The build now fails
loudly if neither the patch nor the driver is present, instead of quietly producing a kernel that
cannot talk to the host.

Verified: the patch applies cleanly to the pristine tree; applied to a throwaway clean tree it
reconstructs the driver **byte-identically** (sha256 `2880e145…`, 464 lines, matching the container)
and wires both Kconfig and Makefile.

## Consequence for ticket 153

The diagnostic object `d14df9f3` cannot work as designed, and its `console=ttydc0` is inert. Two
routes to actually capturing kernel dmesg on the host, in increasing cost:

1. **Apply `t6040-dockchannel-nbcon.patch`** (currently orphaned) to get a real console, then rebuild
   and re-cut the diagnostic object. This is the direct fix.
2. **`earlycon`** via `t6040-dockchannel-earlycon-debug.patch`, also orphaned; note it needs an
   explicit `earlycon=` argument, which the diagnostic bootargs did not carry either.

Until one lands, **the panel is the only source of kernel dmesg**, and a screenshot remains necessary
evidence for any graphical smoke.

## Sweep: is anything else only in the container? (2026-07-26)

Because one driver had gone untracked, all three build trees were swept. Each carries an identical
set of 14 modified/untracked paths, so they come from one shared application flow. Mapping every path
against `patches/` (plus `flokli-code.patch`):

| Path | Covered by |
|---|---|
| `Documentation/.../apple,pmgr.yaml` | `t6040-pmgr-t6041-bindings.patch` |
| `Documentation/.../apple,sart.yaml` | `t8140-ans-bindings`, `t8140-sart-power-bindings` |
| `Documentation/.../apple,mailbox.yaml` | `t8140-ans-bindings.patch` |
| `Documentation/.../apple,nvme-ans.yaml` | `t8140-ans-bindings.patch` |
| `Documentation/.../apple,pmgr-pwrstate.yaml` | `t6040-pmgr-t6041-bindings.patch` |
| `drivers/hid/.../apple_dockchannel_hid.c` | `hid-type`, `hid-state-trace`, `fixes`, `trackpad-fw` |
| `drivers/mailbox/apple-dockchannel.c` | `poll`, `rx-rearm`, `atomic-tx`, telemetry/debug patches |
| `drivers/pmdomain/apple/pmgr-pwrstate.c` | `pmgr-functional`, `pmgr-t6041-quirks`, others |
| `drivers/soc/apple/sart.c` | five `t8140-sart-*` patches |
| **`Documentation/.../apple,dockchannel-serial.yaml`** | **nothing — recovered here** |
| **`MAINTAINERS`** | **nothing — recovered here** |

So **9 of 11 were already reproducible**; the two that were not are both part of the same
dockchannel-serial feature as the driver, and are now folded into
`patches/t6040-dockchannel-tty-driver.patch`. Neither is compiled, so they never affected the build —
but the binding documents the exact `apple,dockchannel-serial` compatible that
`t6040-j614s-dcuart.dts` uses, so losing it would have made the DT unexplainable to a newcomer.

Full reconstruction re-verified on a clean scratch tree: driver byte-identical (`2880e145…`), binding
present, both MAINTAINERS entries applied.

**Conclusion: the kernel is now reproducible from the repository.** The remaining `-dirty` version
string is expected, since the build legitimately applies patches on top of a tagged tree.
