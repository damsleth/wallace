# Ticket queue

Ticket location is authoritative workflow state:

- `tickets/*.json`: active work;
- `tickets/done/*.json`: completed deliverables;
- `tickets/archive/*.json`: superseded, deprecated, deferred, or wontfix work.

Use `scripts/rig-lease.sh queue` to create, approve, ready, and complete
tickets. Sequence allocation is not atomic; immediately verify every newly
allocated sequence. A rig ticket is runnable only after approval, exact hashes,
completed dependencies, independent artifact review, and `runnable: true`.

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

The `state` string may preserve a concise result qualifier, but directory
placement decides whether the ticket is active, completed, or archived.
Archived tickets must include `archived.at`, `archived.by`, and a concrete
reason. Do not put long append-only progress journals in `desc`; move that
material into evidence and leave a short current summary plus links.
