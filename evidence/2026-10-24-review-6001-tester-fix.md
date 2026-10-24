# Independent review: ticket 6001 run-3 payload (tester case-sensitivity fix)

Reviewer: independent (non-builder) offline review, 2026-10-24. No rig, lease,
boot or build. Nothing reviewed was edited.

**Verdict: PASS-with-notes.** Run 3 may be readied on this payload. No must-fix.

## What was checked

- `27a9596` diff: tester and checker now match `SError`, `panic`, `BUG:`,
  `Oops:`, `RTKit: Exception` (and the checker `NVME-READONLY STOP` / `kernel stop`)
  case-sensitively; `assert`, `I/O error`, `timed out`, `timeout:`,
  `timeout while`, `controller is down`, `crashed`, `translation fault` stay
  case-insensitive. The pre-fix sources hash to `287160ef…` (tester) and
  `78889c1d…` (checker), exactly the values the gate-fix manifest `84b0275f…` pins.
- Manifest `nvme-ioq-20261024b/manifest.json` = `c34f4391…`. A JSON diff
  against `nvme-ioq-20261024/manifest.json` shows only: candidate/run labels and
  payload directory path, the `initramfs.cpio.gz` hash (`c76063ac…` → `524d94c3…`),
  the checker hash (`78889c1d…` → `0481319f…`), the tester source hash
  (`287160ef…` → `9372f143…`), `supersedes`, and the new `testerfix` block.
  Image `6eef9eef…`, System.map, config, DTB `a96d04a7…`, m1n1 files, `/init`
  `91d94421…` and every other pinned script are unchanged.
- Initramfs `524d94c3…`: extracted, contains `/sbin/nvme-readonly-test` =
  `aef24ab9…` (the manifest's `testerfix.tester_sha256`) and `/init` = `91d94421…`.
  `strings` on that binary shows the five exact tokens and the lower-case set.
- Verify-only launcher: PASS (all 241 manifest files hash-match; preflight OK).
  I also re-hashed all 241 files with an independent script: 0 mismatches.
- Kernel strings at `4f2429104009` (`apple.c`, `rtkit.c`, `rtkit-crashlog.c`,
  `sart.c`, `apple-dart`): `RTKit crashed; unable to recover`, `RTKit: co-processor
  has crashed`, `RTKit: Exception dump:`, `I/O %d(aq:%d) timeout: resetting
  controller`, `controller is down`, `translation fault` are all matched.
- Replayed the new checker on the real run-2 transcript (`51451988…` per the
  evidence; I recomputed `514519889271…` for the `t6040-console-…falsestop.log`
  file, which is the same file). Removing only the tester's own stop line, no
  stop condition remains (`debug:` and `PANICLOG … ERR_ABORT` are tolerated).
  With one synthetic fault line appended each, the checker stops on: kernel panic,
  `BUG:`, `Oops:`, `SError`, RTKit crashed, RTKit Exception dump, controller is
  down, I/O timeout, translation fault.

## How it could be wrong, and how I ruled it in/out

1. *Case-sensitivity drops a real fault.* Checked above; every upper-case token
   Linux emits for these faults is capitalised exactly as matched
   (`SError Interrupt`, `Kernel panic` is matched by lower-case `panic`, `Oops:`,
   `BUG:`). Not found missing.
2. *Checker run over the m1n1 phase.* `SError` also appears in m1n1 text
   (`dapf: Skipping … (async L2C SError on this M4 SoC)`) in `dcuart-boot.log`
   (checker stops on that file). The run transcript (`t6040-console-…log`) has no
   such line, so run 2 was unaffected; but the checker must only be pointed at
   the console transcript, not the boot log. (Same under `re.I` before.)
3. *Binary not built from the committed source.* I cannot build; evidence says
   the original source rebuilds byte-for-byte to the reviewed binary
   (`0ffb3e55…`) and the fixed source builds `aef24ab9…` twice. Ruled in only by
   those claims plus the strings check, not independently reproduced.

## Notes (not blocking)

- Fault strings from `nvme-apple` that no pattern covers: `ANS did not boot`,
  `ANS did not initialize`, `Reset failure status: %d`, `invalid id %d completed`,
  `Deferred flush failed`. Unchanged from before; a boot failure still ends in
  missing PASS/exit markers, so the run cannot validate, but the tester will not
  *stop early* on them. Consider adding `ANS did not` / `Reset failure` for run 4.
- `strcasestr("assert")`/`"crashed"` could in theory false-stop on benign ANS
  syslog text; none occurs in the run-2 log.

## Commands run

```text
git show 27a9596 --stat; git show 27a9596 -- scripts
diff <(python3 -m json.tool nvme-ioq-20261024/manifest.json) <(python3 -m json.tool nvme-ioq-20261024b/manifest.json)
shasum -a 256 <manifest, tester .c, checker, payload/*, nvme-readonly-test-fix>
python3 scripts/t6040-run-nvme-ioq.py <nvme-ioq-20261024b/manifest.json>      # verify-only, no --run
python3 (re-hash all manifest files)
gunzip -c payload/initramfs.cpio.gz | cpio -idm; shasum -a 256 init sbin/nvme-readonly-test
git show 27a9596^:scripts/<file> | shasum -a 256
strings -a nvme-readonly-test-fix | grep …
git grep -n … 4f2429104009 -- drivers/nvme/host/apple.c drivers/soc/apple/rtkit*.c drivers/iommu/apple-dart.c
python3 scripts/t6040-check-nvme-ioq-transcript.py <run-2 transcript, base and +synthetic lines>
```
