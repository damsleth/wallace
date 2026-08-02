# T6040 SN201202x SPMI transport port and power-role review

Date: 2026-08-02

Scope: offline source port, build, and review only. No rig lease, SPMI
transaction, MMIO access, HPM command, or external post.

## Result

The upstream TPS6598x-over-SPMI transport is now ported onto a clean Wallace
m1n1 worktree as a bounded, uncalled transport:

```text
worktree: /Users/damsleth/Code/m1n1-hpm-spmi-offline
branch:   codex/t6040-spmi-transport
base:     19edc72b85fcda63092de3b643092cc51d508281
commit:   74d3ccc705e7f5b1bddc055403f77f921890d289
author:   CJ Damsleth <kim@damsleth.no>
signoff:  CJ Damsleth <kim@damsleth.no>
```

The port deliberately does **not** integrate the upstream generic HPM
iterator or call the transport from `usb_init()`. It therefore does not touch
HPM0/1/2/5, does not enter the right-port path during boot, and does not create
a live artifact.

Most importantly, the upstream transport does not itself expose a proven
VBUS-enable path. It makes generic TPS logical-register reads/writes and 4CC
commands mechanically possible over SPMI. Linux's generic TIPD driver could
use that primitive to send `SWSr`/`SWSk`, but support for those commands on the
J614s SN201202x remains unproved and Apple's complete paired 25F84 corpus does
not use either command. This is an implementation route, not evidence that the
right port will source VBUS.

## Upstream inputs

- [AsahiLinux/m1n1 PR 636](https://github.com/AsahiLinux/m1n1/pull/636),
  `tps6598x,usb: factor out hpm iteration`, exact head
  `0f6cf87bc65200b35c519d17ca9d799137ee2d18`. The PR reports testing on
  T6000, whose HPM path is I2C.
- [AsahiLinux/m1n1 PR 594](https://github.com/AsahiLinux/m1n1/pull/594),
  `tps6598x: add spmi transport`, exact head
  `dcc5f1bccbbe986099f218e9057f7fa99a0b1fe2`.

PR 594 recognizes `aapl,spmi`/Gen3 controllers with
`usbc,sn201202x,spmi` children. Its selector protocol is:

1. Register-0 write with the seven-bit logical register;
2. poll SPMI register `0x00` until it is either `reg|0x80` (pending) or `reg`
   (selected);
3. transfer the logical payload through SPMI data window `0x20`.

That matches the already live-proven Wallace HPM2 R0/R1 transport shape.

## Hardening relative to PR 594

The Wallace port keeps the transport split but removes the unsafe lifecycle
and discovery coupling:

- accepts only an ADT node compatible with `usbc,sn201202x,spmi`;
- checks the `reg`/SID property is exactly one byte and checks allocation
  before dereference;
- bounds selector polling to 100 attempts with 1 ms spacing;
- bounds command completion polling to 10,000 attempts with 100 us spacing;
- does not automatically send SPMI `WAKEUP` during object construction;
- does not automatically send SPMI `SHUTDOWN` while freeing an object;
- does not add generic HPM/SPMI enumeration;
- does not call `SSPS`, clear W1C events, change interrupt masks, issue a role
  command, or run PHY bring-up through the new path.

The existing I2C path is retained through common read/write helpers. The
bounded command poll also removes the pre-existing unbounded I2C command wait.

## Build evidence

The changed C object compiles cleanly. A full m1n1 link also passes. The clean
worktree had no rustup default configured, so the link reused
`/Users/damsleth/Code/m1n1/build/librust.a`, SHA-256
`10782c88eec61431c4713aa11499d95c8e6827067416578f699d8d3fca046174`.
The Rust source trees at the port base and the supplying worktree are
identical.

```text
build/tps6598x.o  389a0f585f1743152606e8ca049816978273bf62cad8f60dddff4f8285ef1daa
build/m1n1.bin    e48c5c737e116bf6edd9b112e7722fe590373601fbf0bb3d4c13faf21bac6506
build/m1n1.elf    438a700819fbd75b901b0ddb3df2d1b60c1cfc34e751b1d2d11b43120bef396f
```

`tps6598x_init_spmi` and the SPMI selector/read helpers are present in
`tps6598x.o`. Because there is intentionally no caller, link-time garbage
collection removes `tps6598x_init_spmi` from `m1n1.elf`. The linked binary is
therefore build evidence only and cannot enter the new SPMI transport.

## Power-role / VBUS review

Linux `drivers/usb/typec/tipd/core.c` contains two distinct role operations:

```text
data role:  TYPEC_HOST   -> "SWDF"; TYPEC_DEVICE -> "SWUF"
power role: TYPEC_SOURCE -> "SWSr"; TYPEC_SINK   -> "SWSk"
```

For a power-role request the generic driver:

1. writes the four-byte command to logical CMD1 (`0x08`);
2. waits up to 1 s for CMD1 to clear;
3. reads DATA1 and maps timeout/rejected results;
4. reads four-byte Status (`0x1a`);
5. succeeds only if Status bit 5 matches the requested role.

The transport port can carry those exact logical accesses. That establishes
mechanical reachability, not SN201202x support:

- ticket 176 found zero ASCII and zero UTF-16LE `SWSr`/`SWSk` in the paired
  25F84 kernelcache and AppleHPM executable;
- PR 594 adds no `SWSr`/`SWSk` caller and reports no T6040 SPMI test;
- the generic command is a power-role *swap request*, not an unconditional
  VBUS switch. It can be rejected by firmware or policy and depends on the
  controller's advertised port capability and current connection state;
- a successful power-role status bit would still not configure the J614s
  eUSB2 repeater, ATC PHY, ACIO/DWC3 host path, or interrupt ownership.

Therefore the answer is:

> The generic stack supplies a plausible `SWSr` command route over the ported
> transport, but neither upstream nor paired Apple evidence proves the J614s
> SN201202x accepts it or that it turns on right-port VBUS. It is not ready for
> a write ticket.

## Next discriminator

Ticket 178 already owns the safe first measurement: an exact right-HPM2 R0
read of four-byte Status `0x1a`, including power role, PP5V switch, power
source, and VBUS state. No duplicate rig ticket is needed. A useful follow-up
R0 capture would add four-byte System Configuration `0x28` and two-byte Power
Status `0x3f`; the generic driver uses those to decide whether it may register
a source/DRP port. Even if those advertise DRP/source capability, an
`SWSr`/`SWSk` experiment remains a separately reviewed R3 write with explicit
rollback and a passive sink fixture.

## Refutations preserved

- “PR 594 enables VBUS” is false: it adds a transport, not a role policy or
  VBUS operation.
- “Linux contains `SWSr`, therefore SN201202x supports it” is unsupported.
- “Apple does not use `SWSr`, therefore the HPM rejects it” is also not proved;
  the negative corpus result constrains confidence but is not a device-command
  capability table.
- Porting the upstream generic iterator wholesale remains unsafe on Wallace:
  it couples WAKEUP, SSPS, W1C interrupt clear/masking, SHUTDOWN, and PHY
  bring-up across multiple HPMs.
