# T6040 RTKit 26.x compatibility-draft audit (2026-07-23)

Ticket 037 (offline, P1, RTKit). The requested patch set is intentionally
empty: no inspected 26.x delta is proven to be a version-gate-only change.
Adding whitelist entries would either do nothing or route an unverified ABI
through an older method table.

This is the safe completion of the ticket contract: emit patches only where the
ABI delta is proven version-only, and otherwise emit upstream test notes.

## Audited sources

- Wallace Linux source:
  `96ac043df12fd3b8648505c51933b1552d033c4c`
  (`wallace/t6040-bringup`).
- Chad Medley's DCP/ISP 14.8.3 branch:
  `f4df8984b39affb6d661ac67d097c131132b8f26`
  (`https://github.com/chadmed/linux`, branch `dcp/14.8.3`).
- Paired J614s/macOS 26.x static and live facts from ticket 028:
  RTKit OS build `RTKit-1558.40.16.release`, GPU G16, ISP H16, and a live ANS
  management-protocol negotiation accepted by the unchanged Linux RTKit core.

No source checkout was modified.

## Patch decision matrix

| Driver | Inspected gate | J614s evidence | Decision |
|---|---|---|---|
| `soc/apple/rtkit` | management protocol 11–12 | ANS reached `RTKit client initialized` under the existing core | no patch; a max-version bump is unsupported and unnecessary |
| DCP | exact firmware/compat parser plus ABI-specific 13.5 and 14.7 method dispatch | 26.x method/structure ABI and T6040 hardware deltas are not decoded | no whitelist patch; this is not version-only |
| ISP | parses through 14.7 but deliberately continues with `UNKNOWN` | H16 is a new generation and there is no `apple,t6040-isp` match/hardware descriptor | no version patch; it would change only the label, not add H16 support |
| SMC | no firmware-version whitelist | generic RTKit endpoint/key transport; 26.x core protocol already proven | no compatibility patch; ticket 061 owns DT wiring |
| SIO | reports the firmware's protocol value but does not gate it | exact J614s SIO/audio topology and protocol behavior are not tested | no compatibility patch; ticket 040 owns mapping/testing |
| GPU | generation-specific kernel and Mesa ABI | G16 is a new GPU generation | not a version-only patch; ticket 039 |

## Why DCP cannot receive a one-line 26.x entry

At `f4df8984`, `dcp_check_firmware_version()` accepts only the known 13.5 and
14.7 compatibility contracts. That enum is then used by `_dcp_poweroff()`,
`dcp_sleep()`, `dcp_poweron()`, and other paths to select concrete
`iomfb_*_v13_3` or `iomfb_*_v14_7_0` calls. Therefore a new enum or alias is an
ABI assertion, not a logging-only whitelist.

The J614s audit already found independent hardware/interface differences:

- a fifth display register window;
- eight ASC IRQ entries versus the older four-entry Linux shape;
- changed DART SID/register-bank layout;
- unresolved raw-boot display-domain ownership;
- no decoded macOS 26.x DCP method/signature table.

Routing 26.x to the 14.7 method table would conceal all of these unknowns. No
DCP patch is emitted.

### [UPSTREAM] DCP test note

Before proposing a 26.x compatibility entry:

1. extract the exact J614s `apple,firmware-version` and
   `apple,firmware-compat`;
2. diff the complete IOMFB/DCP service-method names and serialized
   request/reply sizes against the 14.7/14.8.3 implementation;
3. add a T6040 hardware descriptor for the five-window, eight-IRQ, DART layout;
4. prove the PMGR ownership transition without adding unreviewed writes;
5. boot with callback/service tracing and stop on the first unknown method or
   size mismatch.

Only if step 2 is byte-for-byte compatible is a version alias defensible.

## Why ISP cannot receive a one-line 26.x entry

At `f4df8984`, `isp_read_fw_version()` recognizes 12.3, 12.4, 13.5, and 14.7,
but `apple_isp_probe()` explicitly continues with
`ISP_FIRMWARE_V_UNKNOWN`. The match table ends at `apple,t6031-isp`. J614s uses
the H16 camera generation, so adding a 26.x enum cannot supply the missing
T6040 register, PMU, mailbox, DART, metadata, or command-layout description.

### [UPSTREAM] ISP test note

Treat H16 as a hardware/command-ABI port:

1. inventory the J614s ISP ADT node, reserved memory, DART streams, IRQs,
   power domains, sensor presets, platform ID, and temporal-filter property;
2. extract the paired H16 setfiles and exact firmware/compat tuples;
3. compare boot-stage magic, channel descriptors, command IDs, metadata size,
   mailbox enable bits, and DSID clearing against the closest existing
   generation;
4. add a dedicated T6040 hardware descriptor before interpreting a boot result.

Do not represent H16 readiness with only `ISP_FIRMWARE_V_26_*`.

## SMC, SIO, and shared RTKit

The Wallace `macsmc` transport has no OS-firmware whitelist. It initializes the
standard RTKit SMC endpoint and enumerates keys, so the remaining J614s work is
DT wiring and read-only key validation, not a 26.x compatibility patch.

`apple-sio` logs `SIO protocol v%u` on `MSG_STARTED` and does not select a
versioned implementation. The correct next evidence is the ticket-040
J614s audio/SIO map and a bounded protocol smoke, not a guessed version gate.

The shared RTKit core accepts management protocol versions 11–12. J614s ANS
already negotiated and booted through that code. No evidence supports raising
`APPLE_RTKIT_MAX_SUPPORTED_VERSION`.

## Outcome

No local fork, patch, rig test, MMIO access, or external post was produced.
The actionable outputs are the two upstream test notes above and an explicit
ban on four misleading changes:

- no RTKit max-version bump;
- no DCP 26.x-to-14.7 alias;
- no ISP 26.x enum without a T6040/H16 hardware port;
- no SMC/SIO “compat” patch where no version gate exists.

Ticket 030 still owns exact paired firmware extraction. Tickets 022, 039, 040,
and 061 own the evidence needed for the corresponding real driver work.
