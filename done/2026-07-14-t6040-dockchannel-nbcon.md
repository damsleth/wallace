# DockChannel-UART nbcon draft and validation matrix

Ticket 033 is complete offline. The console draft is
`patches/t6040-dockchannel-nbcon.patch`, SHA-256
`b245c837793e16ed3241c893393f7c0e1b9a9fefd1391c4ba04842da0b969d6d`.
It depends on ticket 011's
`patches/t6040-dockchannel-atomic-tx.patch`, SHA-256
`a217182c4abb85d7c77c10083c617cb36677b16c454cd2d9fe7ab69339cef51a`.

This is an opt-in draft, not a rig artifact. It does not change the standard
build or boot arguments and has not been run on hardware.

## Patch order

Apply the console series to the current T6040 DockChannel state in this order:

1. `patches/t6040-dockchannel-poll.patch`;
2. `patches/t6040-dockchannel-atomic-tx.patch`;
3. `patches/t6040-dockchannel-nbcon.patch`.

The first patch retains the proven 5 ms TTY fallback. The second adds the
bounded direct FIFO primitive and serializes it with normal mailbox TX. The
third changes only `drivers/tty/apple_dockchannel_tty.c`.

## Console shape

Each probed `apple,dockchannel-serial` TTY embeds and registers one dynamic
nbcon console named `ttydcN`. Standard `console=ttydc0` selection can therefore
enable it when the device probes; without that selection this draft does not
force the console enabled.

Both `.write_atomic` and `.write_thread` call the mailbox primitive directly.
They never call `apple_dctty_write()`, inspect or modify the TTY kfifo, schedule
the TTY work item, wait for mailbox completion, or issue printk on failure.
The threaded callback receives the nbcon-required device serialization through
the existing TTY TX spinlock. The atomic callback takes no TTY or controller
lock.

The callback accepts one printk record of at most `0x800` bytes, matching both
the hardware FIFO and the current kernel's `PRINTK_MESSAGE_MAX` (2048). It
enters one nbcon unsafe section, submits the record with a 10,000 microsecond
drain bound, exits the unsafe section, and returns. Any `-EBUSY`,
`-ETIMEDOUT`, invalid length, lost nbcon ownership, or disconnected-device
case is silently dropped. A timed-out record is never blindly retried because
it may already have reached the host.

Removal calls `unregister_console()` before setting the TTY disconnected or
freeing its mailbox and port, so console SRCU teardown protects the embedded
console and private pointer.

## Atomic/panic validation matrix

These are the required behaviors before any live proposal. “Validated” below
means code-path/static validation plus the successful arm64 build, not a claim
about unmeasured hardware drain latency.

| Context / injected state | Required behavior | Static result |
|---|---|---|
| Console not selected | Existing `/dev/ttydc0` kfifo/workqueue shell path remains the only user-visible TX owner | PASS: registration is dynamic; no forced `CON_ENABLED` |
| Normal nbcon printer thread, idle FIFO | Device lock serializes against TTY queue bookkeeping; record bypasses queue and drains within 10 ms | PASS |
| Hard IRQ/NMI-style atomic flush, idle FIFO | No allocation, sleep, workqueue, regular spinlock, IRQ completion, or printk | PASS |
| Panic flush, idle FIFO | Atomic owner claim, at most 2048 FIFO writes, one timekeeping-independent bounded drain poll | PASS |
| Panic while normal TTY/mailbox TX owns FIFO | Fail `-EBUSY`, drop record, never wait on a lock held by a stopped CPU | PASS |
| FIFO non-empty with no current owner (for example after an old timeout) | Fail `-EBUSY`; do not interleave byte streams | PASS |
| FIFO accepts data but does not drain | Return `-ETIMEDOUT` after at most 10 ms requested delay; drop without recursive report or retry | PASS |
| Higher-priority nbcon takeover before unsafe entry | `nbcon_enter_unsafe()` fails; perform no FIFO access | PASS |
| Higher-priority takeover while FIFO transaction is unsafe | nbcon core observes the unsafe section; a forced panic takeover may sacrifice later console usability per the nbcon contract, but the mailbox owner prevents interleaved writers | PASS, documented residual |
| Record length 0 or greater than 2048 | Drop before entering unsafe state or touching MMIO | PASS |
| Console callback returns a mailbox error | No `dev_err`, `dev_warn`, `pr_*`, TTY write, or callback into mailbox completion | PASS |
| Device removal during normal operation | Unregister and synchronize the console before disconnect/free | PASS |

## MMIO and recursion audit

The console patch itself contains no MMIO. Its only hardware call is ticket
011's primitive, whose audited access set is the existing ADT-described TX
data FIFO (`DATA_TX8`, `DATA_TX32`, and read-only `DATA_TX_FREE`). It never
touches the unresolved IRQ mask/flag or threshold registers.

There is no recursive printk edge:

- normal TTY send errors may still log from normal workqueue context;
- nbcon never invokes that normal send path;
- the atomic primitive returns errno without logging;
- the nbcon callback ignores that errno and returns;
- console registration/removal logging is outside the callback.

## Offline build validation

Validation used a fresh, case-sensitive arm64 tree at
`/build/linux-ticket011` in the `kbuild` container, based on
`origin/dockchannel` `ba89d30070d4` plus the three patches above:

- console patch apply check after atomic patch: PASS;
- strict `scripts/checkpatch.pl`: 0 errors, 0 warnings, 0 checks;
- `make ARCH=arm64 W=1 -j4 drivers/mailbox/apple-dockchannel.o`: PASS;
- `make ARCH=arm64 W=1 -j4 drivers/tty/apple_dockchannel_tty.o`: PASS;
- `make ARCH=arm64 W=1 -j4 drivers/mailbox/built-in.a`: PASS;
- `make ARCH=arm64 W=1 -j4 drivers/tty/built-in.a`: PASS (the broader
  archive build reported pre-existing `samsung_tty.c` format-overflow
  warnings; neither changed object warned);
- `nm drivers/mailbox/built-in.a` shows
  `T apple_dockchannel_send_atomic` and `nm -u drivers/tty/built-in.a` shows
  the expected `U apple_dockchannel_send_atomic` reference;
- `git diff --check`: PASS.

A full linked `Image` build was started, then intentionally stopped after the
two changed objects and their built-in archives compiled: this tree's broad
configuration was rebuilding unrelated all-platform code, which adds no
useful evidence for this source-only ticket. No linked Image artifact or hash
is claimed. A future rig ticket must use the project kbuild recipe and record
the complete boot-artifact tuple.

## Remaining gate

Do not propose a rig boot from these source drafts alone. A later console test
must first create a dedicated build mode, build and hash Image/DT/initramfs,
prove `console=ttydc0` is the only intended behavioral delta, define a bounded
host-visible marker plus recovery condition, and receive cross-review and
explicit approval. The first live target should validate ordinary printk and
forced atomic flush; destructive panic injection is a separate, later gate.
