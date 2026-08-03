# Ticket 106 exact-artifact cross-review — R3/R4 NO-GO

Reviewer: `sol`
Scope: exact shipped artifacts under
`~/Code/linux-build-out/t6040-hpm2-e41cf6e4ee8f/{r3,r4}/`, source commit
`e41cf6e4ee8f2a8b0edbc3fc917ef42aee22e894`, `~/Code/m1n1/AGENTS.md`, and
`docs/SPMI_SAFETY.md`.
Hardware touched: **none**.

## Verdict

**NO-GO for `queue ready 106`.** The endpoint gate, command byte order, bounded
polls, and shipped hashes check out, but the artifact does not implement the
approved source/VBUS experiment. `SWDF` is the **data-role** swap to DFP/host;
the separate source/power-role command is `SWSr`. R4's `SWUF` consequently
reverses only the data role, not a source/VBUS transition.

There are also three independent readiness failures:

1. Ticket 106 requires a role/orientation/power transcript and byte-exact
   rollback. The candidate reads only the 4CC task result and HPM system power
   state `0x20`; it does not read Type-C data role, power role, orientation, or
   VBUS state, and it does not execute rollback.
2. Ticket 105 requires passive-sink detection before sourcing and byte-exact
   rollback. Both were deliberately omitted without replacement plan approval.
3. The preflight says the shipped binaries link no DWC3 code and that the
   symbol audit proves it. Both binaries in fact contain many `usb_dwc3_*`
   symbols. The audit runs, but its deny-list does not test them.

Do not boot R3 or R4 as ticket 106. A replacement source/VBUS plan must derive
and review the exact `SWSr` transaction, source-state verification, and its
power-role inverse separately; it must not infer VBUS from a successful
`SWDF`.

## What passed

### Exact artifacts and provenance

- R3 SHA-256:
  `a106f8cd36a6068fc9586924028b9a64aca986a8e635e1bb0964422ec7345c4e`
- R4 SHA-256:
  `61d5f18ca19ca961162d3cae63a2352912a0683b44bca0ae4ef774c24e5a0716`
- Every R3/R4 member passes its shipped `SHA256SUMS`.
- `MANIFEST` pins commit
  `e41cf6e4ee8f2a8b0edbc3fc917ef42aee22e894` and captured ADT SHA-256
  `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`.
- The source commit has CJ's required author identity and sign-off.
- The build script performs two clean builds per class, compares all copied
  members byte-for-byte, audits each pass's `m1n1-raw.elf`, and ships pass 2.

### Endpoint identity and fail-closed ordering

The captured 606,208-byte ADT independently decodes as:

- root `target-type=J614s`, `model=Mac16,8`, compatible
  `J614sAP`, `Mac16,8`, `AppleARM`;
- `/chosen`: chip ID `0x6040`, board ID `4`;
- exact bus `/arm-io/nub-spmi-a1`, `aapl,spmi`, Gen3, with the sole child
  `hpm2`;
- raw bus reg tuples `0x309198000`, `0x309194000`, `0x309190000`, each
  `0x4000`; translated physical bases `0x509198000`, `0x509194000`,
  `0x509190000`;
- exact child compatible `usbc,sn201202x,spmi`, SID `0x0c`, RID `2`,
  port number `3`, class type `10`, location `right`, with no children.

`t6040_hpm2_experiment()` checks all of that before its first call to
`spmi_init_strict()`. Shipped-binary disassembly has all ADT lookup/property
calls before `spmi_init_strict` at `0xc400`; no SPMI call precedes it. An
identity mismatch therefore returns to the forced warm-reboot path with zero
SPMI transactions.

The strict initializer receives the literal direct bus path. There is no HPM
or SID iteration.

### SPMI surface and bounds

The experiment source reaches only:

- SPMI `WAKEUP`, SID `0x0c`;
- Register-0 selector writes for logical registers `0x08`, `0x09`, and
  `0x20`;
- bounded extended reads/writes through the SN201202x data window `0x20`.

No logical register `0x14`, interrupt mask, W1C clear, PMU, charger, NVRAM,
firmware, `RESET`, `SLEEP`, or `SHUTDOWN` operation is present. The shipped
symbols contain `spmi_send_wakeup`, `spmi_reg0_write`, `spmi_ext_read`, and
`spmi_ext_write`; they do not contain the reset/sleep/shutdown or long-form
SPMI entry points.

The sequence is:

1. exact ADT identity gate;
2. strict initialization of only `/arm-io/nub-spmi-a1`;
3. `WAKEUP`, 10 ms hold, power-state read;
4. if needed, the live-proven `DATA1 <- 00`, `CMD1 <- SSPS` reach-S0 path;
5. `DATA1 <- 00`, `CMD1 <- SWDF` (R3) or `SWUF` (R4);
6. bounded completion polling; stop on selector error, transport error,
   `!CMD`, timeout, nonzero task result, or nonzero HPM power state;
7. 10 s observation hold only after a zero task result and S0 recheck;
8. shutdown the local SPMI object and force a warm reboot.

FIFO waits are bounded in `raw_command`; selector waits are 100 ms; SSPS is
100 ms; the role command is 500 ms; the observation hold is 10 s. No failed
command is retried or escalated.

### 4CC re-derivation and polarity

From the paired kernelcache:

- `AppleHPMInterface::roleSwap(0)` loads UTF-16 `SWDF`;
- `roleSwap(1)` loads UTF-16 `SWUF`;
- `roleSwap(>=2)` does not issue a command;
- `roleSwap` invokes the `AppleHPM::atomic4CC` vtable slot at `0x9a8`, not
  `execute4Cc`;
- its `rev64` + `uzp1` transform is canceled by `atomic4CC`'s `rev` at the
  command-write site, giving forward wire bytes;
- selector argument `1` selects CMD1 (`0x08`);
- the call supplies one zero DATA1 input byte.

The exact shipped binary constants are:

- R3 contains forward ASCII `53 57 44 46` (`SWDF`) and no `SWUF`;
- R4 contains forward ASCII `53 57 55 46` (`SWUF`) and no `SWDF`;
- both retain `SSPS` and `!CMD`;
- no searched DFU/flash 4CC is present.

The R3 artifact, not R4, is the forward **data-role** candidate named by the
preflight.

## Blocking finding 1: `SWDF` is not the source/VBUS command

The local upstream TPS6598x Linux driver provides an independent semantic
cross-check in `drivers/usb/typec/tipd/core.c`:

- `tps6598x_dr_set()` maps `TYPEC_HOST` to `SWDF` and `TYPEC_DEVICE` to
  `SWUF`, then verifies the **data-role** status field.
- `tps6598x_pr_set()` separately maps `TYPEC_SOURCE` to `SWSr` and
  `TYPEC_SINK` to `SWSk`, then verifies the **power-role** status field.

The existing m1n1 TPS experiment likewise sends `SWDF` and then `SWSr` as two
separate commands. DFP/UFP and source/sink are distinct USB-PD roles.

Therefore the preflight's repeated equation
`SWDF = DFP = host/source = enables VBUS` is not established and is contradicted
by the driver semantics. A successful R3 can at most establish that the HPM
accepted a data-role swap request; it cannot be treated as evidence that the
right port sources VBUS.

## Blocking finding 2: no state verification or rollback

After command completion, R3/R4 read only:

- four DATA1 result bytes, accepting result byte zero; and
- logical system power state `0x20`, accepting S0.

They do not read the TPS status register or any decoded Type-C data-role,
power-role, orientation, attach, or VBUS field. Ticket 106's required
role/orientation/power transcript is therefore absent.

R4 `SWUF` is a reasonable candidate inverse for the **data-role** request, but
it cannot roll back a source transition because the source command would be
`SWSr`, not `SWDF`. A power cycle is recovery, not byte-exact rollback. This
makes the rollback deviation unacceptable for the stated source/VBUS test.

The fixed passive-stick fixture materially reduces the consequence of
accidentally sourcing into another host, but it does not satisfy the approved
pre-detection gate. CJ may explicitly replace that artifact gate with an
attended fixture-inspection gate in a revised plan; the existing approval
cannot be silently broadened.

## Blocking finding 3: the shipped-binary symbol claim is false

The script rejects:

```text
spmi_send_(reset|sleep|shutdown)
tps6598x*
usb_init
usb_phy_bringup
spmi_ext_(read|write)_long
```

It does **not** reject `usb_dwc3_*`, `xhci*`, `atc*`, `eusb*`, or general PHY
symbols. Both shipped symbol tables include, among others:

```text
usb_dwc3_handle_events
usb_dwc3_queue
usb_dwc3_write
usb_dwc3_read
usb_dwc3_can_read
usb_dwc3_can_write
usb_dwc3_flush
```

The absence of `usb_init` and `usb_phy_bringup`, plus the unconditional
experiment stop before later main initialization, is good evidence that this
linked gadget support is not invoked by the experiment. It is not evidence
that no DWC3 code is linked. Either the ticket/preflight must narrow the
requirement to “no USB/PHY bring-up entry point is linked or reachable” and
prove that call boundary, or the artifact must be rebuilt to meet the literal
no-DWC3-code condition.

## Policy and queue state

`docs/SPMI_SAFETY.md` still records an explicit R3 no-go pending a complete
host transition and rollback design. The new `SWDF` decode narrows the data-role
operation but does not supply the missing power-role/VBUS transition or its
inverse, so it does not close that policy gate.

Ticket 106 remains `approved`, `runnable=false`. It also currently has no
pinned `hashes` object and depends on ticket 105, which is not done; the queue
tool would reject `queue ready 106` even apart from this NO-GO.

## Required next artifact split

Do not add `SWSr` to R3 in place. First prepare and independently review:

1. a read-only status decode that distinguishes attach, data role, power role,
   orientation, and VBUS without consuming W1C state;
2. a separately approved DFP/data-role artifact if it is still a necessary
   prerequisite;
3. a separately approved source-role artifact using the exact `SWSr` command,
   with the known passive fixture, pre-source gate, bounded status
   verification, and a decoded sink/off inverse;
4. an exact rollback run in the same attended session, with power cycle only
   as recovery if rollback fails.

That preserves the one-operation-class discipline and makes the VBUS result
observable instead of inferred.
