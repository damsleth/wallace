# J614s machine-private ALS calibration preflight (ticket 087)

Date: 2026-07-24  
State: corrected after initial independent-review NO-GO; corrected procedure
and extractor independently re-reviewed **PASS**. **Do not leave the healthy
proxy unattended to run this.** The capture requires a later
maintainer-attended boot of this exact M4 into its main macOS installation.

## Primary-source contract

Asahi installer commit `c53d66dc71937efa2530d4323c81addaebb5a09b`
(`asahi_firmware/als.py`) defines the source and output:

- run `ioreg -r -a -n als -l`;
- follow the first child three times and read `CalibrationData`;
- emit it as `apple/aop-als-cal.bin`;
- copy regular `HmCA*` files from
  `/System/Volumes/Hardware/FactoryData/System/Library/Caches/com.apple.factorydata`
  under `apple/`.

The data is machine-private. Never capture it from the M1 or substitute IPSW
contents.

## M4 capture (read-only hardware/configuration)

Boot the M4's main macOS normally. Do not enter recovery, alter Boot Policy,
touch NVRAM, run `kmutil`/`bputil`, or access SPMI/PMU. In Terminal, create
only a temporary ordinary-filesystem capture:

```sh
set -eu
umask 077
CAPTURE=$(/usr/bin/mktemp -d /private/tmp/wallace-j614s-als.XXXXXX)
ARCHIVE="${CAPTURE}.tgz"
[ ! -e "$ARCHIVE" ]
/bin/mkdir -m 700 "$CAPTURE/factory"
MODEL=$(/usr/sbin/sysctl -n hw.model)
[ "$MODEL" = Mac16,8 ]
/usr/bin/printf '%s\n' "$MODEL" > "$CAPTURE/hw.model"
/usr/bin/sw_vers > "$CAPTURE/sw_vers.txt"
/usr/sbin/ioreg -r -a -n als -l > "$CAPTURE/als-ioreg.plist"
[ -s "$CAPTURE/als-ioreg.plist" ]
FACTORY=/System/Volumes/Hardware/FactoryData/System/Library/Caches/com.apple.factorydata
SOURCE_COUNT=$(sudo /usr/bin/find "$FACTORY" \
  -maxdepth 1 -type f -name 'HmCA*' -print |
  /usr/bin/tee "$CAPTURE/HMCA_SOURCE_PATHS" |
  /usr/bin/wc -l | /usr/bin/tr -d ' ')
[ "$SOURCE_COUNT" -ge 1 ]
sudo /usr/bin/find \
  "$FACTORY" \
  -maxdepth 1 -type f -name 'HmCA*' \
  -exec /bin/cp -p '{}' "$CAPTURE/factory/" ';'
COPIED_COUNT=$(/usr/bin/find "$CAPTURE/factory" \
  -maxdepth 1 -type f -name 'HmCA*' -size +0c -print |
  /usr/bin/wc -l | /usr/bin/tr -d ' ')
[ "$COPIED_COUNT" -eq "$SOURCE_COUNT" ]
/usr/bin/tar -C "$CAPTURE" -czf "$ARCHIVE" .
/bin/chmod 600 "$ARCHIVE"
/usr/bin/shasum -a 256 "$ARCHIVE" |
  /usr/bin/tee "${ARCHIVE}.sha256"
/bin/chmod 600 "${ARCHIVE}.sha256"
```

Stop if `hw.model` is not exactly `Mac16,8`, `ioreg` is empty/fails, the
FactoryData directory is unavailable, or no `HmCA*` file is copied. Record the
archive hash and transfer the mode-0600 archive confidentially to the M1. The
commands fail on the first error, use a fresh unguessable mode-0700 capture,
verify the source/copy counts and non-empty files, and refuse an existing
archive. They only read IORegistry/FactoryData and write ordinary temporary
files; they do not change machine configuration. Do not delete the capture
until the transferred archive and two derived bundles verify.

## M1 extraction and fail-closed guards

After transfer, unpack the archive into a new directory and run:

```sh
umask 077
python3 scripts/t6040-extract-als-calibration.py \
  --ioreg-plist /path/to/capture/als-ioreg.plist \
  --factory-dir /path/to/capture/factory \
  --model-file /path/to/capture/hw.model \
  --output /private/tmp/t6040-j614s-als-vendorfw
```

The parser:

- refuses a model other than `Mac16,8`;
- uses the exact upstream three-child plist path rather than searching for an
  arbitrary same-named property;
- requires non-empty byte `CalibrationData`;
- rejects symlink/empty model, IORegistry, FactoryData, and `HmCA*` inputs;
- requires all three input paths to share the same fresh capture root;
- copies only non-empty regular, non-symlink `HmCA*` inputs;
- refuses to overwrite an existing output;
- atomically publishes the bundle only after it is complete;
- creates directories mode 0700 and private files mode 0600;
- emits private `SHA256SUMS` and `SOURCE_MODEL`.

Compare `apple/aop-als-cal.bin` and all `apple/HmCA*` hashes with a second
independent extraction from the same raw capture. Preserve the raw archive,
its hash, macOS version, and the upstream commit with the result. Only then
may a later ticket place these files into a Linux firmware bundle.

## Pass / stop

Pass is an exact `Mac16,8` bundle containing non-empty
`apple/aop-als-cal.bin`, at least one `apple/HmCA*`, and a verified manifest.
This ticket does not boot Linux or enable the ALS driver.

Stop on any model/path/type/hash mismatch or missing raw file. Never broaden
the FactoryData glob, use another machine's data, or “repair” an unexpected
plist shape by guessing.

## Independent review result

The initial review found stale-path failure handling and mode-0644 exposure of
machine-private output. After the changes above, independent re-review
reproduced the valid bundle and manifest; verified directories mode 0700 and
files mode 0600; exercised wrong/empty/symlink/mixed-root/missing-type,
overwrite, and forced-copy-failure cases; and confirmed failed extraction
publishes no output or staging residue. Verdict: **PASS for a later
maintainer-attended capture**. The current healthy proxy remains untouched and
the rig ticket stays `runnable=false` until that attended window.
