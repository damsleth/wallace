# T6040 B0 v2 object — Norwegian keymap + unconditional proxy window (2026-07-25)

Two maintainer requests, both in one object:

1. **Norwegian keyboard by default** (standing preference — memory
   `norwegian-keyboard`). The ticket-100/v1 B0 root had **no** keymap, so the
   panel typed US. v2 loads the **Apple Norwegian** layout.
2. **Unconditional early-proxy window** — v1's upstream gate
   (`!display && sip0==127`) can never arm here (measured: `sip0 = 0`,
   `display: 0x1`), so v1 is pure auto-boot with no debug door.

```text
m1n1-b0-alpine-v2-nb-uncond.bin
SHA-256 f26a2156f1f44f659bd122f4ad9577d6c65adae9ca3162f290476e11322ea3cf
size 15,946,484 B (15.21 MiB) — fits the proven >=16 MiB iBoot budget
entry 0x800
```

| Member | SHA-256 | Change vs v1 (`4340ec37`) |
|---|---|---|
| m1n1 v2 | `5e9dcfd3…` | **new** — unconditional window |
| kernel (xz) | `cbb3e743…` | unchanged (expands to proven `df7657c1`) |
| DTB | `2782b922…` | unchanged |
| initramfs (xz) | `46e91340…` | **new** — +Norwegian keymap |
| bootargs | `3659a0da…` | unchanged |

## m1n1 v2 — `5e9dcfd3`

`patches/m1n1-early-proxy-unconditional.patch` on `a61fd099`, built with
`EXTRA_CFLAGS="-Wstack-usage=2048 -DEARLY_PROXY_TIMEOUT=5 -DEARLY_PROXY_UNCONDITIONAL=1"`
(nightly, `RUSTUP_TOOLCHAIN=nightly`). Byte-reproducible across two clean
builds; 1,097,728 B (same size as v1/base). Version tag is now
`v1.6.0-75-ga61fd099-dirty` — expected, since this is a real source patch
(v1 was a pure compile define).

The patch keeps upstream behavior when the new flag is absent:

```c
#ifdef EARLY_PROXY_UNCONDITIONAL
    if (true) {              /* always offer the window */
#else
    if (!cur_boot_args.video.display && lp_sip0 == 127) {
#endif
```

Behavior: **every** boot prints `Waiting for proxy connection...` and waits
5 s. Host connected (`macvdmtool reboot debugusb` + proxy) → hands control to
the host, chainload/debug as usual. Nobody connects → times out → auto-boots
the embedded Alpine. So the untethered cold boot still works, at the cost of a
**5 s delay on every cold boot**. That is the trade for a permanent debug door.

## Norwegian keymap — initramfs `46e91340`

Built from the proven B0 root (`ddd98171`, 699 entries) → 707 entries:

- `usr/share/bkeymaps/no/no-mac.bmap` + `no.bmap` — **pre-compiled binary**
  keymaps from Alpine `kbd-bkeymaps-2.8.0-r0`
  (`11420d1bf0aa7b364e4284d652c04d6c2acb1cead2c866d22c320f1b73720832`), so
  BusyBox `loadkeys` can load them with no compiler on target. **`no-mac`** is
  preferred: Apple Norwegian keyboards differ from PC Norwegian on several
  symbol positions.
- `etc/init.d/t6040-keymap` + sysinit runlevel symlink — OpenRC service,
  `need devfs`, `before t6040-health-report`; tries `no-mac` then falls back to
  `no`, and does not fail the boot if neither loads.
- `etc/profile.d/10-nb-no.sh` — `LANG=nb_NO.UTF-8` (`LC_COLLATE=C`; musl has no
  locale data, so this is just an env default for anything that reads it).
- `etc/wallace-keymap` records the active choice.

Cost: **+904 bytes compressed** (33 KB × 2 raw). Invariants preserved: 0 block
nodes, no network service, root locked, `/sbin/init` + `/sbin/openrc` intact.

Strict verifier: **PASS**.

## Status / next

- Not yet booted. Needs (a) a tethered chainload smoke like v1's — which also
  visually confirms the keymap service and the 5 s window — and (b) Sol
  cross-review before enrollment.
- v1 `4340ec37` remains the milestone candidate the maintainer is testing now;
  v2 is the follow-up "usable machine" object (Norwegian + debug door).
- If the 5 s universal delay proves annoying, the alternative is a gate on a
  chosen-var or held key instead of `if (true)`.
