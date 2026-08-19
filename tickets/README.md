# Ticket queue

Ticket location is authoritative workflow state:

- `tickets/*.json`: active work;
- `tickets/done/*.json`: completed deliverables;
- `tickets/archive/*.json`: superseded, deprecated, deferred, or wontfix work.

Use `scripts/rig-lease.sh queue` to create, approve, ready, and complete
tickets. `queue add` allocates the sequence number inside the calling agent's
own block (fable 1000+, opus 2000+, sol 3000+, terra 4000+, claude 5000+), so
different agents never collide. Same-agent concurrent adds can still race, so
immediately verify every newly allocated sequence. A rig ticket is runnable only
after approval, exact hashes, completed dependencies, independent artifact
review, and `runnable: true`.

## Record shape

Keep `desc` focused on the current objective, boundary, and pass/fail contract.
Put durable narrative, transcripts, retractions, and detailed results under
`evidence/`. New or materially revised tickets should link them explicitly:

```json
"evidence": [
  "evidence/2026-08-03-t6040-205-smp-cow-investigation.md",
  "evidence/logs/example-transcript.log"
]
```

## Sequence numbers

`queue show` and `queue done` resolve a sequence against `tickets/` first,
then `tickets/done/`; `tickets/archive/` is history only and is never
resolved. A re-scoped successor may keep its predecessor's sequence (191 is
the example): the archived record keeps the original slug, and the active
file is the current work. New sequences are allocated inside the calling
agent's block (see above); numbers below 1000 are the frozen legacy space from
the pre-2026-08-19 odd/even scheme and are never re-issued.

The `state` string may preserve a concise result qualifier, but directory
placement decides whether the ticket is active, completed, or archived.
Archived tickets must include `archived.at`, `archived.by`, and a concrete
reason. Do not put long append-only progress journals in `desc`; move that
material into evidence and leave a short current summary plus links.
