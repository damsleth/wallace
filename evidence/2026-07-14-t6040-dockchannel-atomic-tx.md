# DockChannel bounded atomic TX primitive

Ticket 011 is complete offline. The draft is
`patches/t6040-dockchannel-atomic-tx.patch`, SHA-256
`a217182c4abb85d7c77c10083c617cb36677b16c454cd2d9fe7ab69339cef51a`.
It is a mailbox-controller primitive only; it does **not** register a printk
console. Ticket 033 owns the nbcon/TTY integration.

## Patch base and ordering

The patch is based on the actual T6040 build state:

1. Linux `origin/dockchannel` at `ba89d30070d4`;
2. `patches/t6040-dockchannel-poll.patch`, SHA-256
   `627d0805f103f56ad20cc24785d4e747740e774c1660604611298adf6bcd0e63`;
3. `patches/t6040-dockchannel-atomic-tx.patch`.

This ordering matters because the poll fallback and the atomic primitive both
touch TX completion. The draft releases the asynchronous owner in both the
normal IRQ completion path and the T6040 5 ms poll completion path.

The patch deliberately is not enabled by default in `t6040-kbuild.sh` yet.
Ticket 033 should apply it explicitly before its nbcon integration so the
console work remains opt-in and build-reviewable.

## API and bound

The controller exports:

```c
int apple_dockchannel_send_atomic(struct mbox_chan *chan,
                                  const void *data, size_t len,
                                  unsigned int timeout_us);
```

The hard contract is:

- payload length is `1..0x800` bytes (one hardware FIFO);
- timeout is `1..100000` microseconds;
- the call never allocates, sleeps, schedules work, or waits for an IRQ;
- the call never takes the controller's regular spinlock;
- another normal or atomic owner, or a non-empty FIFO, returns `-EBUSY`;
- a FIFO which does not drain in the caller's bound returns `-ETIMEDOUT`;
- the function emits no printk on any failure path.

`readl_relaxed_poll_timeout_atomic()` supplies the timekeeping-independent,
1-microsecond delayed poll. A zero timeout is rejected rather than inheriting
that helper's “poll forever” meaning. The public ceiling prevents a caller from
turning the primitive into an unbounded panic stall.

## Serialization

An atomic three-state owner (`IDLE`, `ASYNC`, `ATOMIC`) serializes the existing
mailbox path and the new direct path:

- normal mailbox TX claims `ASYNC` before taking the existing spinlock;
- IRQ or poll completion returns `ASYNC` to `IDLE` before calling
  `mbox_chan_txdone()`;
- atomic TX claims `ATOMIC` with `atomic_cmpxchg()`, writes, polls for drain,
  and returns to `IDLE`;
- shutdown releases only an `ASYNC` owner.

This is intentionally fail-fast. If another CPU stops with a normal TX in
flight, panic output returns `-EBUSY` instead of deadlocking on its spinlock or
stealing the mailbox client's completion. Ticket 033 must treat that as a
dropped console fragment, not retry it recursively through printk.

## MMIO audit

There are no new addresses and no IRQ/config writes in the atomic path. It
uses only the same ADT-described DockChannel data resource and accessors as the
existing reviewed mailbox driver:

- read `DATA_TX_FREE` at data resource `+0x14`;
- write aligned words to `DATA_TX32` at `+0x10`;
- write remaining bytes with a 32-bit accessor to `DATA_TX8` at `+0x4`.

The path first requires `DATA_TX_FREE == 0x800`, so the complete bounded
payload fits before the first write. It then polls only for the FIFO to return
to `0x800`. It does not touch `IRQ_MASK`, `IRQ_FLAG`, `TX_THRESH`, or
`RX_THRESH`; it cannot perturb the unresolved RX BIT(1) experiment.

## Offline validation

Validation ran in the case-sensitive arm64 `kbuild` container in a fresh
`/build/linux-ticket011` clone:

- poll patch apply check: PASS;
- atomic patch apply check after poll patch: PASS;
- strict `scripts/checkpatch.pl`: 0 errors, 0 warnings, 0 checks;
- `make ARCH=arm64 W=1 -j4 drivers/mailbox/apple-dockchannel.o`: PASS;
- `nm` confirms global text symbol `apple_dockchannel_send_atomic` plus its
  export metadata;
- `git diff --check`: PASS.

No rig access occurred and no live artifact was produced.

## Handoff to ticket 033

The nbcon draft should:

- call this API directly, never `apple_dctty_write()` or the kfifo/workqueue;
- split records into at most `0x800`-byte fragments;
- perform any CR/LF policy outside the mailbox primitive;
- use a small per-fragment timeout below the 100 ms API ceiling;
- stop on `-EBUSY` or `-ETIMEDOUT` without printk or blind retry (a timed-out
  fragment may already have reached the host);
- keep console registration opt-in until an offline atomic/panic validation
  matrix and a separately reviewed artifact exist.

The primitive is therefore panic-safe in the bounded/fail-fast sense required
by NEXT_STEPS §2.2. It does not promise delivery when a pre-existing normal TX
owns the FIFO, which is the safe tradeoff until the nbcon layer controls the
TTY/console interaction.
