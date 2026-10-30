# Gravity Linux second look (claude, 2026-10-30)

Independent pass over github.com/GravityLinux, read through the GitHub API only (no
clones; this host has no `~/code/gravitylinux`). It checks the claims in
[the 2026-10-29 survey](2026-10-29-gravitylinux-survey.md) and adds what that
survey did not cover. Nothing here changes a ticket or the capability table.

## Confirmed

- **CTRR reservation (5015 lead).** `bootloader` `eb6cab77f5` ("kboot: reserve the
  firmware CTRR range") says what the survey says: T8132/T8140 only, bounds read
  from the CTRR registers, validated against advertised RAM, page-aligned range
  added to the FDT memory reservation map. The lead still rests on 5012's
  observation and the Asahi commits; Gravity is a cross-check, not an
  independent finding. The T8132/T8140 gate means nothing from Gravity shows
  the T6040 range, so 5015's register read stays the deciding step.
- **Max bring-up doc.** `Documentation/arch/arm64/apple-m4max-experimental.rst`
  (`replacement/000-devicetree`): "Max hardware tests use all sixteen CPUs."
  The doc carries no SMP recipe beyond that, so the SMP claim for Max is the
  doc's word plus the reservation commit.
- **Branch set.** `linux` has `replacement/{000-devicetree,010-soc,020-dart,090-spi-hid,
  115-pmp,160-usb,170-atc,171-dptxphy,200-dcp,210-gpu,260-spmi-typec}`, `bits/*` and
  `gravity-m4`. `000-devicetree` is rebased onto Linux 7.3 as of 2026-10-29
  ("Merge shared Rust API compatibility for Linux 7.3").
- **T6041 files** (`t6041-{aop,audio,cpufreq,display,gpu-config,gpu-memory,isp,
  mtp,pmgr,pmp,wireless}.dtsi`, `t6041-j616c.dts`, `configs/t6041-cpufreq.config`).
  The survey lists nine of these. `t6041-gpu-config.dtsi` and
  `t6041-gpu-memory.dtsi` are not in its list; relevant to 4004 and 5018.
- CPU OPP frequencies are filled in by m1n1 from board data, per the doc. The
  matching bootloader change is required for the Max DT. Relevant to our
  `t6040-cpufreq.dtsi`: the same split (m1n1 supplies, Linux reads FDT) may
  already apply to us.

## New: not in the survey

1. **USB-PD select interrupt off-by-one (305).** `linux` `gravity-m4`
   `4cb9998f58` (2026-10-08, Thomas Glanzmann, tested on Mac mini M4 j773g):
   the SN201202x node at SPMI slave 8 listed `select` one line too low (64
   instead of 65). The commit message says the driver blocks on the select
   interrupt while addressing the chip, so "every register access times out
   and the controller never probes", and the port never appears under
   `/sys/class/typec`. Pattern: irq, select, sleep, wake, with select always
   two lines above irq.
   - Relevance: that is the failure shape of 305 runs 6/7 (probe fails, no
     typec class). Our transport does not use interrupts (the draft DT says
     "No interrupts property"; we poll register 0), so this exact bug cannot
     hit us. It does mean the ADT-derived `select`/`sleep`/`wake` numbers have
     to be right if we ever move to the IRQ-driven transport. It also adds to
     the survey's note that Asahi's transport waits on the `wake` IRQ.
   - Run 7's zero-write encoding diagnosis stands. This does not contradict it.
2. **Gravity keeps FIFO reads in dockchannel-hid on M4 branches.**
   `gravity-m4` `a48a449524` ("retain FIFO reads and baseline packet dispatch
   policy") uses the blocking FIFO receive API and shares dispatch between FIFO
   and ring frames. So the driver carries both paths. The survey's 5013
   progress note says M4 Max uses the shared-ring transport. I did not verify
   which path J616c takes, and the 5013 comparison itself hedges ("exact
   commit attribution ... unverified"). Treat "ring transport is the top
   hypothesis for the HID stall" as unverified until the J616c DT's MTP node
   and mode are read. The Max doc says only that the MTP block is extended.
3. **Provenance trailers.** The commits I opened carry `Assisted-By:` trailers
   naming an LLM (`eb6cab77f5`: OpenAI Codex; `4cb9998f58`: DeepSeek). The
   survey's policy note is about Gravity's contribution policy. This is a
   separate point for importing: keep the original `From:` and add our
   sign-off, and decide whether to keep their `Assisted-By:` trailer.
   AGENTS.md says nothing on it.
4. **Bootloader activity since the survey's pins.** Newest `bootloader` commit
   is `f02d4a52` (2026-10-14: licence-identifier fix). Others in the window:
   `467c3272` ("chainload: default to raw mode"), `0036fb2c` (adds an
   `AGENTS.md`, worth reading for their agent rules), `093767c9` (chainload
   allows larger stage2 images), `56c8d214` ("nvme: support T8132"). `chainload`
   changes are worth diffing against our fork before a stage2 build.
5. **Camera calibration firmware (Max doc).** J616c sensor0958 needs
   `apple/isp_2224_01XX.dat` (magic `0x22240106`, 28660 bytes), extracted from
   the target OS's `appleh16camerad`. The calibration bytes are not committed.
   Only relevant once the camera track opens.

## Not verified

- `CTRR_C` coverage on T6040/J614s: no Gravity commit touches it.
- The 48 KiB vs more-than-256 KiB mismatch in 5012: Gravity adds no data.
- Whether Gravity's Max kernel runs 16 CPUs stably: only the doc's statement.
- Contents of unpublished Gravity commits (`4a0545d5`, per the survey).

## Suggested follow-ups (not ticketed)

- Read `bootloader/AGENTS.md` and diff `chainload` against our fork.
- When 305 moves toward an IRQ-driven transport, read the hpm2 `select`/`sleep`/
  `wake` numbers from the ADT, not from a neighbouring node.
- Read the J616c MTP node to settle FIFO vs ring before leaning on it in 5013.
