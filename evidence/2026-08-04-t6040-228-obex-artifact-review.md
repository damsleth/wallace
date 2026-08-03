# Ticket 228 (BT OBEX object push) — independent exact-artifact review

# VERDICT: **FAIL — do not `queue ready`, do not boot**

Date: 2026-08-04. Reviewer: claude (independent second pair of eyes).
Ticket author/builder: fable. Rig use by this review: **none** — offline hash,
archive, DTB, and source inspection only. No lease taken, no rig script run, no
hardware touched, no external post. Nothing in the ticket, the queue, or any
script was modified.

Reviewed against `AGENTS.md`, `docs/COORDINATION.md` §"Safety review",
`docs/AGENT_ONBOARDING.md` §"Exact review", `docs/BUILD_RECIPE.md`, and
`docs/SPMI_SAFETY.md`.

The artifacts are hash-clean and the *hardware-safety* posture is sound. The
FAIL is not about hardware risk: it is that the run as specified **cannot
succeed**, would fail on the second step and again on the fourth, and it fails a
mandatory mechanical gate. Two of the blockers are provable offline in seconds,
which is exactly the rig cycle this review exists to save.

---

## BLOCKING

### B1. `obexd --no-input` is not a valid option — obexd exits before it ever registers

`scripts/t6040-bt-obex.sh:95`

```sh
"$OBEXD" --root="$INBOX" --auto-accept --no-input >/dev/null 2>&1 &
```

The shipped obexd has no such option. From the binary in the pinned initramfs
(`./usr/lib/bluetooth/obexd`, 336 KiB):

- its GOption long names are exactly `debug`, `noplugin`, `nodetach`, `root`,
  `root-setup`, `symlinks`, *capability*, `auto-accept`, `system-bus`, `version`;
- a search of the whole binary for `no-input` **and** `noinput` returns **zero**
  hits — a GOption long name must exist as a literal in the binary, so it cannot
  be accepted;
- `g_option_context_set_ignore_unknown_options` is **not** referenced (0 hits;
  the only GOption symbols are `_new`, `_add_main_entries`, `_parse`, `_free`),
  so an unknown option is a hard parse failure and obexd exits non-zero before
  claiming `org.bluez.obex`.

Consequence: `start_obexd()` never sees a pid, spins 15 s, and `die`s with
`STOP: obexd did not start`. That kills **every** command that needs obexd —
`up`, `receive`, and `send`. The ticket's step 4 ("`t6040-bt-obex receive` and
confirm … `org.bluez.obex` PRESENT") is unreachable.

Worse for triage: obexd's stdout *and* stderr are sent to `/dev/null`, so the
actual message ("Unknown option --no-input") is discarded and the operator sees
only the generic `did not start`. Whoever debugs this on the rig will suspect
D-Bus, the session bus, or hci0 first.

Fix is one word: drop `--no-input` (use `--nodetach` if foreground was the
intent — but note `--nodetach` would block the `&`-backgrounded call differently
than the code assumes). Do not merely un-silence the redirect.

### B2. WiFi auto-association is dead in this artifact, so the ticket's ssh step cannot run

The pinned initramfs ships `/etc/wpa_supplicant/wpa_supplicant.conf`, 57 bytes,
mode 0600, whose entire content is:

```text
p2p_disabled=1
wpa_passphrase 'Bilbo Laggins' '<PSK redacted>'
```

That second line is the `wpa_passphrase` **command**, not its output. There is no
`network={ … ssid=… psk=… }` block anywhere in the file.

`/init:66` gates association on exactly that:

```sh
if grep -q '^[[:space:]]*ssid=' /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null; then
```

No `ssid=` ⇒ `wpa_supplicant` is **never started**, `wlan0` is never brought up,
`udhcpc` never runs. sshd does start (authorized_keys is present) and `/init:84`
will print `sshd up; wlan0: no address`. The ticket procedure — "wait for
WiFi+sshd, then **over ssh** run `t6040-bt-obex receive`" — is not executable.
Even if the gate were removed, wpa_supplicant would refuse to parse the file at
all (line 2 is not a valid global directive), so this is not a one-line-of-init
workaround either.

Root cause is host-side, not in the image: `$HOME/wpa.conf` is 42 bytes, mtime
2026-07-29 21:04, and contains the un-run command. The builder
(`scripts/t6040-build-alpine-wifi.sh:143-148`) faithfully does
`{ echo p2p_disabled=1; cat "$WPA_CONF"; }`. Fix `$HOME/wpa.conf` by actually
running `wpa_passphrase 'SSID' 'PSK' > ~/wpa.conf`, then rebuild — which changes
the initramfs hash, so the ticket must be re-pinned.

The image does document a manual fallback on the console (`/init:95-96`), and
the OBEX test itself does not need WiFi. If the intent is to accept that, the
ticket must say so: drive `t6040-bt-obex` from the **ttydc0** shell, not over
ssh. As written it does not.

### B3. The mandatory image preflight FAILS: no Norwegian keymap

`scripts/t6040-image-preflight.sh --kernel …/Image --initramfs …v3build1.cpio.gz`
→ **exit 1**, `preflight: 1 FAILURE(S) -- do not enroll or boot this`:

```text
PASS  kernel contains pcie-apple
PASS  kernel contains macsmc
PASS  kernel contains dockchannel-hid
PASS  kernel version string readable: Linux version 7.1.3-g4f2429104009-dirty …
FAIL  NO Norwegian keymap -- every image must ship one
PASS  init loads the keymap (loadkmap present)      <-- false positive, see below
PASS  member init
PASS  member bin/busybox
WARN  no fsck.exfat -- a dirty SD64 cannot be repaired in place
PASS  firmware brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin
PASS  firmware brcmbt4388c2-apple,mriya-u.bin
```

Confirmed by hand: no `*.bmap` member anywhere in the 1127-entry archive, and no
`loadkmap` invocation in `/init`. `scripts/t6040-build-alpine-wifi.sh` never
installs `etc/wallace-no.bmap` and `scripts/t6040-wifi-init` never calls it — so
this is a builder-level omission that every image from this builder shares, not a
228 regression.

`AGENTS.md` and `docs/BUILD_RECIPE.md` §1 admit **no exemption**: "Including
throwaway diagnostic images, rescue shells, and initramfs-only boots." The
preflight is described in AGENTS.md as the thing to "Run … before anything is
enrolled, handed to CJ, or booted", and it says do not boot this. It is not the
reviewer's call to waive that.

Mitigating context, for CJ to weigh rather than for an agent to assume: this root
is headless (`/chosen/framebuffer@0` is disabled) and its shell is driven from
the M1 over KIS, so the internal keyboard is not the input path for this run. If
CJ wants a standing exemption for DockChannel-only roots, that belongs in
`BUILD_RECIPE.md` as a recorded exception, and the preflight should encode it —
not be silently overridden per ticket.

**Sub-finding — the preflight's own second check is broken and masks B3.** It
tests `gzip -dc "$INITRAMFS" | grep -ac 'loadkmap'` against the *whole
decompressed archive*, which matches Alpine's stock OpenRC file
`/etc/conf.d/loadkmap` that this image ships and this `/init` never uses. So it
reports "init loads the keymap" on an image that loads no keymap at all. Any
future image that ships the `.bmap` but forgets the call would pass both checks.

### B4. The ticket's "no SMC/SPMI/PMU/NVRAM write" claim is materially wrong for the pinned DTB

The pinned DTB enables the system-PMU SPMI bus, and the pinned kernel has the
driver that writes to it:

- DTB: `/soc/spmi@509014000` `status = "okay"` (`apple,t6040-spmi`), child
  `pmic@e` = `apple,abbey-pmic`, `apple,spmi-nvmem`, with an nvmem layout
  containing `pm-setting@2001`, `rtc-offset@2100`, `boot-stage@f801`,
  `boot-error-count@f802` bits 0-3, `panic-count@f802` bits 4-7, and
  `shutdown-flag@f80f` bit 3.
- DTB: `/soc/smc@50c600000/reboot` (`apple,smc-reboot`) consumes exactly those
  four cells as `shutdown_flag`, `boot_stage`, `boot_error_count`, `panic_count`.
- Kernel: `macsmc-reboot` and `apple-spmi`/`apple,spmi-nvmem` are **builtin**
  (string counts in `Image`: `macsmc-reboot` 2, `apple-spmi` 2,
  `apple,spmi-nvmem` 1, `Failed to write boot_stage` 1).
- Driver: `drivers/power/reset/macsmc-reboot.c` at probe does
  `nvmem_cell_set_u8(boot_stage, BOOT_STAGE_KERNEL_STARTED)` (line ~242-244) and
  then, if either counter is nonzero, `nvmem_cell_set_u8(panic_count, 0)` and
  `nvmem_cell_set_u8(boot_error_count, 0)` (lines ~196-199). On shutdown/reboot
  it also writes `boot_stage` and `shutdown_flag`.

So booting this artifact performs **SPMI writes into the abbey PMU's nvmem
scratchpad** — precisely the class `docs/SPMI_SAFETY.md` calls out ("Never write
PMU … RTC/scratchpad … through SPMI or any other transport"; the abbey PMU
children "remain completely out of scope").

I am **not** asking for the artifact to change. This is a pre-existing property
of the standard daily-driver DTB (`dts/t6040-j614s-dcuart-wifi.dts` enables
`nub_spmi0` deliberately, for the RTC-offset cell) that has already been booted
under several approved tickets, it is upstream Asahi boot-stage bookkeeping
rather than a voltage/charger/firmware write, and `apple,smc-reboot` is on
AGENTS.md's permitted list. What blocks is the **claim**: the safety review
exists to confirm "only the reviewed SMC keys or SPMI endpoint/operation appear",
and a ticket that asserts *no* SPMI/PMU/NVRAM write while pinning a DTB+kernel
pair that writes PMU nvmem on every boot defeats that check for every reader
after us. Correct the `desc` to name the boot-stage/panic-count nvmem writes as
in-scope-and-expected (citing the smc-reboot permission), or point at a recorded
exception.

### B5. Stop conditions, fixture, and recovery are not explicit; the hash field is empty

`docs/COORDINATION.md` §"Safety review" requires "hashes, stop conditions,
fixture, and recovery are explicit"; `docs/AGENT_ONBOARDING.md` §"Exact review"
requires "explicit pass, stop, fixture, and recovery conditions". Ticket 228 has:

- **pass** — yes: "a file arrives with a matching SHA-256 in either direction";
- **stop** — none. No abort criterion for a failed BT probe, an hci0 that never
  comes up, an obexd that will not start (B1), a pairing dialog that never
  appears, or a lost DebugUSB tether. `grep -ci 'stop\|recover\|abort'` over the
  ticket JSON = 0;
- **fixture** — partial: the M1 controller MAC `F8:4D:89:6C:92:CB` is named, but
  not the tether/port layout, nor which side is driven from where;
- **recovery** — none stated. (It is in practice trivial — see N7 — but "it's
  obvious" is what the checklist exists to stop.)
- `"hashes": null` — the three hashes live only in free-text `desc`, so no tool
  can check them. Every other pinned field in the queue is machine-readable; this
  one is prose.

---

## NON-BLOCKING

**N1. Hashes — all four verified independently, all match.**

| artifact | bytes | sha256 |
|---|---|---|
| `Image` | 56,396,288 | `43e1a7d4656b7cd692b7217fdccb77bf68c96a28b79e8579dad1d73ee369b8e5` |
| `t6040-j614s-dcuart-wifi-cpufreq.dtb` | 60,613 | `7fea8942aadb47ed83915f95e210c489d64264ca1420913a13635ca48d702cfa` |
| `initramfs-alpine-wifi-obex.v3build1.cpio.gz` | 24,554,412 | `6de5abfea4ca552c608667031f8a6f92da2dd5894823d22c9b802910d9005c41` |
| `initramfs-alpine-wifi-obex.v3build2.cpio.gz` | 24,554,412 | `6de5abfea4ca552c608667031f8a6f92da2dd5894823d22c9b802910d9005c41` |

The two v3 builds are **byte-identical** (same size, same hash). 1127 cpio
entries. The `gzip -n -9` reproducibility fix is real and effective.

**N2. Kernel identity — real, current, driver-complete; not the stale-`$OUT/Image` trap.**

```text
Linux version 7.1.3-g4f2429104009-dirty (wallace@t6040-kbuild)
  (gcc Debian 12.2.0-14+deb12u1, GNU ld 2.40) #1 SMP PREEMPT 2026-08-03T18:17:34+02:00
```

mtime 2026-08-03 18:26:41 (yesterday). Driver string counts: `pcie-apple` 2,
`macsmc` 17, `brcmfmac` 83, `hci_bcm4377` 1 (with `bcm4377_hci_free_dev`,
`bcm4377_hci_unregister_dev`, `bcm4377_pci_free_irq_vectors` and the
`brcm/BCM%s.%s.hcd` firmware pattern — builtin, not a module stub), plus
`dockchannel-hid` for the preflight guard. `Image` is byte-identical to
`Image-macsmc-hid-type-fix-trackpad-nbcon-ppp-cpufreq` (same 43e1a7d4… hash,
same mtime), so it genuinely is the named artifact and `boot-dcuart.sh`'s
driverless-kernel guard would pass. The ticket's `desc` writes the version as
`7.1.3-g4f2429104009` and drops the `-dirty` suffix — cosmetic.

**N3. DTB — matches policy on GPIOs; PCIe layout is exactly what the test needs.**
Decompiled clean with `dtc -I dtb -O dts` (DTC 1.7.2, one benign
`simple_bus_reg` warning about `/soc/serial`).

- **PCIe** `/soc/pcie@1cb0000000`: `pci@0,0` enabled → `wifi@0,0`
  (`pci14e4,4434`, `apple,antenna-sku = "X3"`, `brcm,board-type = "apple,mriya"`)
  and `bluetooth@0,1` (`pci14e4,5f72`, `apple,mriya`). `pci@1,0` enabled → SD
  reader `mmc@0,0` (`pci17a0,9755`). `pci@2,0` and `pci@3,0` **disabled**.
- **`pwren-gpios` appear exactly twice, and only on the approved SMC GPIOs**:
  `pwren-gpios = <0x7a 0x13 0x00>` on `pci@0,0` and `<0x7a 0x19 0x00>` on
  `pci@1,0`. Phandle `0x7a` resolves to `/soc/smc@50c600000/gpio`
  (`apple,smc-gpio`) — i.e. gP13 (WiFi/BT) and gP19 (SD), exactly the approved
  set, nothing else. The `reset-gpios` (`0x74 0x04…0x07`) are the SoC pinctrl
  gpiochip, not SMC.
- **No other SMC key or GPIO anywhere.** SMC children are only `gpio`, `rtc`
  (`apple,smc-rtc`), and `reboot` (`apple,smc-reboot`) — all three on AGENTS.md's
  permitted list.
- Also enabled: `hid@514600000` + its two mailboxes + `iommu@514800000`
  (DockChannel keyboard/trackpad), `smc@50c600000` + `mailbox@50c608000`,
  `pwm@429040000` (keyboard backlight via `led-controller`).
- Disabled: all three `usb@…` controllers and their six DARTs,
  `serial@429200000`, `/chosen/framebuffer@0`, `cpu@10105`,
  `power-management@502280000/power-controller@10000`.
- Nothing enabled that the WiFi/BT/SD/HID/SMC set does not explain.

**N4. ANS/NVMe are NOT disabled** — `mailbox@409608000`, `iommu@40dc50000`
(SART) and `nvme@44dcc0000` are all `status = "okay"`. Deliberate in
`dts/t6040-j614s-dcuart-wifi.dts`. Nothing in userspace mounts it (see N7), but
the kernel *will* probe the internal SSD, which carries the known
first-CQ-wrap ANS firmware assert. For a Bluetooth-only test that is gratuitous
exposure of the machine's internal storage; `dts/t6040-j614s-dcuart-wifi-nonvme.dts`
already exists and would remove it at zero cost to the experiment (at the price
of a rebuild and a fresh DTB hash). Not blocking — precedent exists and the risk
is read-path only — but if this ticket is re-pinned for B1/B2 anyway, that is the
moment to switch DTBs.

**N5. The obexd bus-activation hazard is real, and the evidence doc overstates
the mitigation.** The image ships
`/usr/share/dbus-1/services/org.bluez.obex.service`:

```text
[D-BUS Service]
Name=org.bluez.obex
Exec=/usr/lib/bluetooth/obexd -n
```

No `--root`, no `--auto-accept`. If anything touches `org.bluez.obex` on the
cached session bus before `start_obexd()` runs, the bus activates that instance;
`start_obexd()`'s `pidof obexd` guard then **silently skips** launching the
properly-flagged one. The activated instance roots at obexd's documented default
(its own help text: "Default `$XDG_CACHE_HOME`" → `/root/.cache` with `HOME=/root`),
i.e. **outside** `$INBOX = /root/obex-inbox`; and with `--auto-accept` absent an
inbound push needs an `org.bluez.obex.Agent1` authorization, which nothing here
registers — the helper's `bluetoothctl --agent=NoInputNoOutput` is
`org.bluez.Agent1` on the **system** bus, a different interface for a different
purpose (pairing). So the push is rejected, files land nowhere, and `report()`
still prints `org.bluez.obex PRESENT` next to an empty inbox: a green report over
a silent failure. Answering the question directly — **rejected, not misfiled**, is
the likelier outcome, with misfiling to `/root/.cache/obexd` possible if an agent
ever is registered.

The evidence doc claims "the helper starts obexd explicitly and thereby owns the
bus name before any on-demand activation can win with the wrong flags". There is
no such guarantee — the guard is a pid check, not bus-name ownership — and given
B1 the explicit start never succeeds at all, so *only* the wrong-flag path can
ever produce a live obexd here. Suggested hardening: have `report()` assert the
running obexd's actual flags (`tr '\0' ' ' < /proc/$(pidof obexd)/cmdline`) and
require `--root=$INBOX` and `--auto-accept`, rather than trusting name presence.

**N6. No private key material of any kind is baked in.** `/etc/ssh` contains only
`sshd_config` (241 bytes) and an empty `sshd_config.d`; host keys are generated
at boot by `ssh-keygen -A` (`/init:79`). `/root/.ssh/authorized_keys` is 98 bytes,
mode 0600, and is a single **public** ed25519 key. A recursive grep for
`PRIVATE KEY` across all 1127 members returns nothing. `sshd_config` is key-only
(`PermitRootLogin prohibit-password`, `PasswordAuthentication no`,
`KbdInteractiveAuthentication no`) and the builder locks the root password
(`sed -i 's/^root:[^:]*:/root:*:/' /etc/shadow`). Nit: the authorized_keys
comment field carries the retired `kim@damsleth.com` identity that AGENTS.md
says not to use — cosmetic, it is a comment.

**N7. No `/etc/machine-id`** and no `/var/lib/dbus/machine-id` in the archive —
the reproducibility fix holds. The only match for "machine-id" is Alpine's stock
OpenRC service `/etc/init.d/machine-id`, which this `/init` never runs (it
deliberately does not use OpenRC).

**N8. Plaintext WiFi credential in the artifact — acceptable where it lives, but
it is a passphrase, not a derived PSK.** `/etc/wpa_supplicant/wpa_supplicant.conf`
is mode 0600 and contains the SSID and its cleartext passphrase. Confirmed it
cannot reach git: `~/Code/linux-build-out` is **outside** the wallace repo
(`git check-ignore` reports "outside repository") and is not itself a git repo (no
`.git`), so no `.gitignore` entry is needed or possible; `git status` shows no
build artifact staged, only `tickets/228-bt-obex-file-transfer.json`. So this is a
host-local secret in a host-local file — fine for a bench rig. Two notes anyway:
the value is the *passphrase*, so it is reusable anywhere that password is reused
(a `wpa_passphrase`-derived `psk=` hash would not be — and fixing B2 properly
yields exactly that, so strip the cleartext comment line `wpa_passphrase` emits);
and the secret is now duplicated into both 25 MB artifacts.

**N9. Reversibility and non-persistence — confirmed, and the ticket's RAM-root
claim holds.** `/init` mounts only `proc`, `sysfs`, `devtmpfs`, `tmpfs` on `/tmp`,
and `tmpfs` on `/run`. There is **no `switch_root`**, no block-device mount, no
`nvme`/`mmcblk` reference anywhere in `/init` or the `/usr/local/sbin` helpers,
and `/etc/fstab` holds only two `noauto` entries (cdrom, usbdisk). `/var/lib/bluetooth`
exists but is **empty** (mode 0700) — no pairing keys are baked in — and lives on
the initramfs rootfs, so BlueZ link keys, the volatile `/etc/machine-id`, the
cached session-bus address in `/run`, and the entire `$INBOX` all vanish on
reboot. Recovery is a power cycle; nothing to undo.

**N10. Helper scope — clean, with one caveat about reuse.**
`scripts/t6040-bt-obex.sh` (9.3 KiB) performs **no** SMC key write, no SPMI, no
PMU/charger access, no NVRAM, no firmware load or update, no block-device I/O, no
`mount`, no partition or filesystem operation. `rfkill unblock bluetooth` is the
only rfkill action, as the ticket claims, and it is tolerated-on-failure. Its
filesystem writes are confined to `/run/dbus`, `/run/t6040-obex-session-bus`,
`/etc/machine-id`, `/var/lib/dbus/machine-id`, `/var/lib/bluetooth`, and `$INBOX`
— all RAM-backed for this ticket. Caveat for later reuse: the script's own header
says it also runs on an **SD root**, where those same writes are persistent; that
is out of scope for 228 but should not be forgotten when it is reused.

The copy in the initramfs is hash-identical to the repo script:
`204cd1dc0f099c0a9393bd2ed005c948c13e0b093739f53f63abdc6d6a68ae22` for both
`./usr/local/sbin/t6040-bt-obex` and `scripts/t6040-bt-obex.sh` (verified again
after the two commits that landed during this review). obexd is present at
`/usr/lib/bluetooth/obexd` as claimed, and `gdbus`, `dbus-daemon`, `dbus-send`,
`dbus-uuidgen`, `bluetoothctl`, `hciconfig`, `rfkill`, `pidof`, `sha256sum` are
all present. There is no `dbus-launch`, and correctly the script does not use it.

**N11. No shell injection; the inbox is bounded by default but unvalidated.**
`$mac`, `$file`, and `$INBOX` are always double-quoted and always passed as
separate argv elements to `bluetoothctl`/`gdbus`/`sha256sum`/`mkdir`; there is no
`eval`, no `sh -c` with interpolation, and no unquoted expansion into a command
string. `send` validates `[ -f "$file" ]` first. The `sed -n "s/…/\1/p"` parses of
gdbus output are anchored to `/org/bluez/obex…` and are safe. The one soft spot:
`INBOX=${T6040_OBEX_INBOX:-/root/obex-inbox}` is env-overridable with **no
validation**, and it becomes obexd's `--root` — an operator who exports it to a
mounted SD or NVMe path would silently void the ticket's "touches no storage"
property. Default is bounded and RAM-backed; consider rejecting a path outside
the rootfs/tmpfs.

**N12. `receive` leaves a wide-open window that the ticket does not bound.**
`discoverable-timeout 0` means discoverable **indefinitely** (until reboot), the
backgrounded `NoInputNoOutput` agent gives JustWorks pairing with no local
confirmation for 600 s, and obexd runs `--auto-accept`. For that window any
nearby device can pair unprompted and push files into the inbox. Acceptable on a
bench, but it deserves to be a stated, time-boxed step, and the run should end
with `discoverable off`.

**N13. Bootargs and the blind panel.** `scripts/t6040-boot-dcuart.sh` defaults to
`maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0
fbcon=font:TER16x32 ignore_loglevel rdinit=/init` — `maxcpus=1` matches the ticket
and respects ticket 205, and `console=tty0` is last as the preflight requires.
But this DTB disables `/chosen/framebuffer@0`, so the `T6040_SMP_REPORT_BEGIN/END`
block `/init` writes to `/dev/console` renders nowhere and its "greppable in a
photo" comment no longer holds for this DTB; ttydc0 over KIS is the only channel.
Harmless, worth knowing before someone waits for panel output.

---

## What would make this PASS

1. Drop `--no-input` from `scripts/t6040-bt-obex.sh:95` and stop discarding
   obexd's stderr (B1). Ideally also assert the live obexd's real flags in
   `report()` (N5).
2. Repair `$HOME/wpa.conf` with real `wpa_passphrase` output and rebuild — or
   rewrite the ticket procedure to drive the helper from the ttydc0 console and
   drop the ssh dependency (B2).
3. Ship `etc/wallace-no.bmap` and call `busybox loadkmap` from
   `scripts/t6040-wifi-init`, so the mandated preflight exits 0 — or get a
   recorded `BUILD_RECIPE.md` exemption for DockChannel-only headless roots and
   fix the preflight's false-positive `loadkmap` check (B3).
4. Correct the ticket's "no SMC/SPMI/PMU/NVRAM write" sentence to acknowledge the
   `apple,smc-reboot` boot-stage/panic-count nvmem writes over SPMI that this
   DTB+kernel pair performs on every boot (B4).
5. Add explicit stop conditions, the fixture, and recovery, and populate the
   machine-readable `hashes` field (B5).

Items 1-2 change the initramfs, so the pinned initramfs hash must be
re-generated, re-built twice, and re-reviewed. Item 3 does too. Since a rebuild
is unavoidable, N4 (switch to the `-nonvme` DTB) is nearly free at the same time.
