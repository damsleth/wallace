# Project evidence

This directory is the durable experiment record: preflights, exact-artifact
reviews, results, analyses, retractions, manifests, and milestone reports. A
file here is historical evidence, not necessarily a successful experiment or
the current project state.

Current priorities live in `docs/NEXT_STEPS.md`; durable operating knowledge
lives in `docs/DEVLOG.md`; executable work and dependency state live in
`tickets/`.

## Layout and naming

- Reports and small manifests remain at this directory's root so existing
  chronological filenames continue to sort usefully.
- Raw transcripts live in `evidence/logs/` and should be linked from a report or ticket
  with their SHA-256 whenever possible.
- New files should use
  `YYYY-MM-DD-t6040-NNN-slug-kind.ext`, where `NNN` is the owning ticket.
- Legacy filenames are retained to preserve provenance and avoid needless
  rename churn.

Do not delete an unreferenced transcript solely because it lacks a backlink.
First determine whether its Git commit, content, or recorded hash supplies
unique evidence.

## Relationship to tickets

`tickets/done/` means a ticket's deliverable is complete; `tickets/archive/`
means a ticket was superseded, deprecated, deferred, or rejected. Neither is a
replacement for this evidence collection.

New or materially revised tickets should use a top-level `evidence` array for
repository-relative paths instead of burying paths in an append-only `desc`.
Historical tickets may retain their older prose references until touched.
