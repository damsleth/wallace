# T6040 SPTM NVMe guarded-handler argument decode (2026-07-23)

Ticket 051 is complete. Static Apple `objdump` disassembly of the decompressed
`sptm.t8132.release.im4p` byte-proves what each guarded NVMe handler consumes.
No firmware binary is stored here, and no rig or storage access occurred.

## Proven contract

| op | handler role | guarded-side input registers |
|---:|---|---|
| 0 | initialise NVMe instance | none |
| 1 | establish a CID's TCB and DMA pages | `x0=qid`, `x1=cid`, `x2=TCB PA`, `x3=page-list PA`, `x4=page count` |
| 2 | complete/invalidate a CID TCB | `x0=qid`, `x1=cid`, `x2=direction/state flag` (low bit) |
| 3 | configure negotiated limits | `x0=queue entries`, `x1=protocol version` |
| 4 | admin queue registers | `x0=ASQ PA`, `x1=ASQ depth`, `x2=ACQ PA`, `x3=ACQ depth` |
| 5 | I/O queue attributes | `x0=IOSQ entries`, `x1=IOCQ entries` |
| 6 | I/O submission queue register | `x0=IOSQ register PA/value` |
| 7 | I/O completion queue register | `x0=IOCQ register PA/value` |
| 8 | ANS SHA register | `x0=SHA base PA`, `x1=buffer size`, `x2=packed-write config` |

This confirms ticket 007's formerly unverified op-4 shape: the handler compares
both depths against `0xfff`, validates both 64-bit page-aligned addresses, and
writes the ASQ low/high words followed by ACQ low/high words. The contract is
not inferred from the old debug patch.

## Ops 0–3

- Op 0, starting at `0xfffffff0270bb72c`, reads only the global NVMe instance.
  It derives controller values, programs the guarded BAR window, and opens the
  next allowed-function bits. It consumes no incoming argument.
- Op 1, at `0xfffffff0270bb00c`, bounds qid to two queues, cid to the ADT queue
  count, and page count below `0x102`. It maps the 128-byte TCB at `x2`, maps
  the `x4 * 8` page-address list at `x3`, validates every page, and changes the
  CID state.
- Op 2, at `0xfffffff0270ba808`, validates qid/cid and consumes the low bit of
  `w2` to select the CID transition/invalidation path. It unmaps the recorded
  TCB/pages and clears guarded state.
- Op 3, at `0xfffffff0270ba6e8`, directly calls the queue-entry and protocol
  validators. String xrefs at file offsets `0x45ee`/`0x460a` and
  `0x4618`/`0x4637` remove the earlier ambiguity: `w0` is queue entries and
  `x1` is protocol version.

The GetNVMe protocol and queue-entry values therefore feed op 3.
`NVMeCoastGuardSetTCB` is the op-1 TCB/page registration path; op 2 is its
completion/invalidation transition.

## Ops 4–8

The functions are contiguous and their `allowed_functions` bit tests pin their
indices. Ops 6 and 7 each validate a single 64-bit, page-aligned address and
write its low/high words to IOSQ/IOCQ BAR registers. Op 5 bounds two entry
counts and packs them as low/high 16-bit halves. Op 8 validates the SHA base,
requires `buffer_size == queue_entries << 14`, and consumes the low packed
configuration bits before programming the ANS SHA registers.

## Boundary that remains

This proves the ABI *inside* the NVMe guarded dispatch. It does not prove the
outer XNU-to-IOMMU call path, where IOMMU id, op index, argument registers,
caller domain, and return value are marshalled. The former M4 hypervisor trace
route is dead because GXF cannot be trapped there; the remaining route is the
exact-blob/static work in ticket 052 plus the XNU-shim escalation in ticket
055. The header intentionally keeps `sptm_nvme_call()` stubbed.

The decoded contract is reflected in `xnu-shim/include/sptm_nvme_iface.h`; no
callable hardware path was added.
