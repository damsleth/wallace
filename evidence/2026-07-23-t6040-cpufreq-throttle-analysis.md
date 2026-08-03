# T6040 cpufreq throttle static analysis

Ticket 021 (offline, P2), 2026-07-23. This was a source, ADT, and paired
Apple-driver audit only. The rig was not leased or touched, and no new MMIO
access was attempted.

## Outcome

There is no evidence-backed replacement for T6030's direct
`ppt/llc/amx-thrtl` offsets on T6040. More importantly, the paired macOS 26.5
PMGR stack does not support the assumption that those old per-cluster writes
should simply move to another nearby offset:

- the J614s ADT advertises `ppt-thrtl`, `llc-thrtl`, and `amx-thrtl` as boolean
  capabilities, but supplies no register offsets for them;
- the target-specific `AppleT6041PMGR` overrides the generic
  `ApplePMGR::enableThrottler()` entry points and deliberately returns without
  calling the generic implementation for enum slots 1, 11, and 12
  (`(1 << slot) & 0x1802`);
- none of T6030's direct feature offsets occurs as a 32-bit literal in the
  paired `ApplePMGR`, `AppleT6041PMGR`, or `AppleT6041CLPC` executables.

The enum slots are not proven to map one-to-one to m1n1's three feature names,
and absence of a literal does not prove absence of a constructed address. The
evidence nevertheless rules out inventing a replacement table from the old
layout.

The correct current implementation remains m1n1's conservative
`t6040_features[]`: only the validated `CLUSTER_PSTATE` (`+0x20020`) features,
with no `+0x440f8`, `+0x40xxx`, or `+0x48xxx` access. Full throttle parity is
not required for Linux DVFS or the bootable-image milestone.

## Paired inputs

Restore identity:

```text
UniversalMac_26.5.2_25F84_Restore.ipsw
j614sap / macOS Customer / Erase
BuildManifest SHA-256:
a6e764ca158e10ea2ace9b74701f445eefbf012c9cdb5aaa616aa10a0b5197ef
```

The selected `kernelcache.release.mac16j` is Darwin 25.5.0
RELEASE_ARM64_T6041. Temporary extracted executables are proprietary and were
not committed:

| executable | size | SHA-256 |
|---|---:|---|
| `ApplePMGR` | 826,760 | `83b9b20e43a01510905dd05375b5df411390a239b1d1eea30ad243533db7cec4` |
| `AppleT6041PMGR` | 178,328 | `75890af83a64f8d9701c8026d38afa8069a2c9bcb0ec40813e445a950e90eb72` |
| `AppleT6041CLPC` | 733,080 | `5edf524cb6d260b2a158db5106b6b84af806d7ed78fac7c9e9800f29c5677f81` |

Captured ADT:

```text
/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt
SHA-256:
7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
```

## ADT result

`/arm-io/pmgr` contains:

```text
compatible = pmgr1,t6041
ppt-thrtl = 1
llc-thrtl = 1
amx-thrtl = 1
cluster-ctl-offset = 0x20000
misc-cores-offset = 0x88000
misc-acg-offset = 0x98000
```

The three named throttle properties are flags only. There is no accompanying
per-cluster throttle-offset property. The explicit offsets describe other
PMGR blocks and do not authorize a throttle access.

## Target PMGR decode

Both `AppleT6041PMGR::enableThrottler(Throttler, bool)` overloads implement the
same front end:

```text
if (slot <= 12 && ((1 << slot) & 0x1802))
        return;
return ApplePMGR::enableThrottler(...);
```

Thus slots 1, 11, and 12 are target-specific no-ops. The generic implementation
uses a 16-way dispatch and resolved PMGR register-map metadata; it is not a
simple T6030-style `cluster_base + constant` table. This is an architectural
warning, not a recovered register contract.

A byte-exact scan of all three executables found no little-endian 32-bit
occurrence of `0x40250`, `0x40270`, `0x48400`, `0x48408`, or `0x440f8`.
`AppleT6041CLPC` has one `0x20020` occurrence, consistent with the already
validated PSTATE path. These negative searches are supporting evidence only.

## Safety and follow-up

- Do not probe neighboring P-cluster addresses. The two prior reads produced
  asynchronous SErrors and defeated m1n1's guarded-read recovery.
- Do not restore any T6030 feature or misc write merely because the ADT flag is
  true.
- Submit the PSTATE/APSC-only patch independently; throttle parity can be a
  later target-PMGR reverse-engineering project.
- If upstream requires it, the existing draft question in
  `2026-07-10-t6040-cpufreq-writeup.md` now points specifically at the
  T6041 PMGR override and resolved RegMap metadata. Nothing was posted.

Ticket 021 is closed as a bounded static result: no safe offsets were recovered,
and no offset is needed for current Linux bring-up.
