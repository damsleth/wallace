# brcmfmac fixes from Gravity `bits/084-bcm4388-wifi` (ticket 5016)

These are verbatim `git format-patch` exports with the original authors
(Niklas Sheth / Cody Ho) kept. Not applied, built or run.

| Patch | Gravity | Why we care |
|---|---|---|
| 0001 | `9c150e234d` don't drain an uninitialized bus_reset work | Removes a `WARN` on PCIe removal when firmware load fails. Hygiene only |
| 0002 | `406b59b0a0` Map msgbuf packet IDs bidirectionally | **Rebase guard.** Upstream `f0ba5fd51ff2` ("Set DMA direction for msgbuf packet IDs") makes BCM4388 firmware trap with "H2D DMA data transfer error" after the first LINK event; WiFi never associates (bisected on M4 Air, 7.3). Needed as soon as our kernel base contains `f0ba5fd51ff2`; check with `git merge-base --is-ancestor f0ba5fd51ff2 HEAD` |
| 0003 | `426ef46e3a` Report port authorization after the connect result | WPA2-PSK/SAE with firmware supplicant otherwise hits `WARN_ON(!wdev->connected)` in `__cfg80211_port_authorized()` on every join. Fixes `3afb9971c1275` (Janne, Asahi "Report port_authorized for offload auth"); only applies if our base has that commit. We have only proven association on an open network |

## Deliberately not taken

`fb50041b58` "EXPERIMENTAL: wifi: brcmfmac: add M4 Max BCM4388C2 support":

- Its `cfg80211.c` hunk re-adds a `cfg80211_port_authorized()` block after
  0003 already moved one there. At the Gravity branch tip,
  `brcmf_bss_connect_done()` calls `cfg80211_port_authorized()` **twice** per
  successful SAE/PSK connect (lines 6500 and 6512 of `cfg80211.c` at
  `origin/bits/084-bcm4388-wifi`). This is a Gravity bug.
- Its `pcie.c` hunk adds a `4388C2` firmware mapping (rev ID 6 via `BIT(6)`)
  and sets `bus->chiprev`. Our base already loads
  `brcmfmac4388c2-pcie.apple,mriya.*` (`scripts/t6040-kbuild.sh` firmware
  list, live 2026-08-04: "BCM4388/6"), so the mapping is already present.
  Re-check only if a rebase drops it.
- The `WLAN_AKM_SUITE_WFA_DPP` → local `WLAN_AKM_SUITE_DPP` rename is a
  build fix for their tree.

## Wiring

`scripts/t6040-kbuild.sh` applies patches by explicit name. To use these,
add a stanza per patch with the same `git apply --check` / "already applied"
pattern as `t6040-brcmfmac-bss-info-v116.patch`.
