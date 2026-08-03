# T6040 B0 dual-mode object cross-review (ticket 119)

Date: 2026-07-24  
Scope: offline rebuild, byte audit, and trigger review only. No rig, enrollment,
Boot Policy, or network action.

## Verdict

**Conditional PASS for a bounded ticket-101 hardware validation.** The exact
staged object is internally consistent and preserves the live-proven Linux
payload byte-for-byte. Its normal-display and DebugUSB classification remain
hardware assumptions, so the cold boot and proxy-window checks must be
separate, bounded observations with the known proxy object available for
rollback.

Do not describe the current m1n1 recipe as independently byte-reproducible
until both `M1N1_VERSION_TAG` and the exact Rust nightly are pinned. This is a
provenance limitation, not evidence of an unexplained payload delta.

## Independent build evidence

Fresh detached source at `a61fd099` with LLVM 22.1.8 exposed two inputs that
were not pinned by the original build:

- A natural fresh-tree `git describe` used seven characters (`a61fd09`) and
  produced base m1n1
  `db029f97f60ddadd5a4d965aad8862b9f1458897a41a52ef2aa2af16be15b2ba`.
- With `M1N1_VERSION_TAG=v1.6.0-75-ga61fd099`, current rustc
  `1.99.0-nightly 6f72b5dd5 (2026-07-22)` produced:
  - base:
    `94b71bfb3f885098d75bed40e4f526f1da94e5f9f4bf9b4750b97d7fd14c827a`
  - `EARLY_PROXY_TIMEOUT=5`:
    `638ef4a65425188a763d03f717280e3d1e0f2c1d543ab5c15143e45d59872c69`

The staged `librust.a` identifies rustc
`1.99.0-nightly af3d95584 (2026-07-09)`. Relinking the fresh C objects with
that exact archived Rust output reproduced both expected binaries:

- base:
  `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- `EARLY_PROXY_TIMEOUT=5`:
  `11f6fbf1d9bfd4b5d4ea6308444beffc8063446553d48791c3a34e20c1458b91`

This isolates the fresh-build mismatch to the version string and Rust nightly.
It does not constitute an independent rebuild of the archived Rust object;
future recipes must install/pin the exact nightly rather than reuse an output.

## Object audit

The independently packed object is 22,183,563 bytes and reproduced:

`46237ade7e314cd752e1482930e21b62319e1b0b707a0f23e86392701555f0c9`

Inputs:

| Component | SHA-256 |
|---|---|
| dual-mode m1n1 prefix | `11f6fbf1d9bfd4b5d4ea6308444beffc8063446553d48791c3a34e20c1458b91` |
| kernel | `d76463e51cf3fb61e0af93f9ea6f24562de32db78988eeaa98a031f0c336bcc5` |
| DTB | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| initramfs | `ddd981711e91c917b735d39df0e90dd50200c158e1ea54c7f2c171c8ad317024` |

The strict object verifier passed. Every byte after the 1,097,728-byte m1n1
prefix matches live-proven object
`2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b`.
A current-nightly prefix changes the whole-object hash
(`b9b63540a5dc242541cfede8d791c9dd91d8ec547158c2aaed2d2a99b5f821e7`)
but still preserves every post-prefix byte.

## Trigger semantics and bounded validation

The feature is confined to `config.h` and `main.c`. It opens the early proxy
window only when both conditions hold:

1. `video.display` is absent/false; and
2. `lp-sip0 == 127`.

Missing or unexpected `lp-sip0` defaults to zero and skips the window. The
loop is 500 iterations of nominal 10 ms polling, then `payload_run()`.
A connection enters `uartproxy_run()` indefinitely by design.

Consequences to validate on hardware:

- a display-present cold boot should skip the proxy and boot immediately;
- a no-host false positive delays payload by about five seconds, then boots;
- a false negative immediately boots and provides no proxy opportunity;
- an accidental proxy connection during a no-display cold boot holds in proxy
  rather than running the payload.

Ticket 101 must therefore first cold-boot with no host proxy handshake and
judge B0 on the panel/keyboard. Only afterward should it separately start the
host proxy before a DebugUSB reboot and test the five-second window. Stop on
any artifact mismatch, boot failure/reset loop, missing panel, or
misclassification. Do not tune the timeout during the session. Roll back by
re-enrolling exact known proxy m1n1 `1394c345...` from main macOS.

