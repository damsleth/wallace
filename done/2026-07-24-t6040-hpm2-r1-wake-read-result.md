# T6040 right-HPM2 R1: WAKEUP plus power-state read

Date: 2026-07-24
Ticket: 094
Result: **PASS — right HPM2 reported power state `0x07`**

## Exact artifact and transcript

```text
m1n1 commit:
  3e4ea5b880d13284de7383b1f8059f71ca08ad53
R1 m1n1.bin:
  bf3694348739558df91b10ffe5f097b6e1a4b4878e3b4724cd3a9cac6744cf0a
chainload transcript:
  /Users/damsleth/Code/linux-build-out/hpm2-r1-wake-read-20260724.log
  e68321259acd1a3dd942586a578ece6e5c8ded764f8d325370458f07068cd341
```

Independent source, final-disassembly, symbol, and two-clean-build review
passed before the live run. The R1 binary linked WAKEUP and extended read, but
not extended write, SSPS, SLEEP, SHUTDOWN, RESET, long transfers, TPS6598x,
USB, or PHY code.

## Exact result

```text
t6040-hpm2: ADT identity PASS, direct endpoint /arm-io/nub-spmi-a1/hpm2 sid=0x0c
t6040-hpm2: WAKEUP sid=0x0c; read-only after wake
spmi-strict: TX sid=0x0c opc=0x13 extra=0x0000 in=0 out=0
spmi-strict: RX header=0x00008c13
spmi-strict: RX validated data
t6040-hpm2: logical-select reg=0x20
spmi-strict: TX sid=0x0c opc=0xa0 extra=0x2000 in=0 out=0
spmi-strict: RX header=0x00008ca0
spmi-strict: RX validated data
spmi-strict: RX data-word=0x00000020
spmi-strict: RX validated data 20
t6040-hpm2: logical-read reg=0x20 len=1
spmi-strict: RX data-word=0x00000007
spmi-strict: RX validated data 07
t6040-hpm2: power-state=0x07
t6040-hpm2: class R1 PASS; intentional stop and warm reboot
```

This proves the public driver's missing prefix on J614s: WAKEUP plus the exact
10 ms delay activates the selector/data window. It also provides the first
read of the target's system-power-state byte: `0x07`, not S0.

The automatic warm reboot ran. A standard DebugUSB recovery then returned a
quiescent healthy proxy, and the lease was released healthy.

## Next boundary

Do not combine the first SSPS transition with interrupt-mask testing. Ticket
095 is narrowed to:

1. the proven identity, WAKEUP, 10 ms, and `0x07` state-read prefix;
2. one-byte DATA1 target S0 (`0x00`);
3. one four-byte `"SSPS"` command;
4. bounded command polling;
5. a final logical power-state read requiring `0x00`;
6. stop and warm reboot.

No IRQ/event register is accessed. The former mask roundtrip moves to a later
separately reviewed ticket after SSPS succeeds.
