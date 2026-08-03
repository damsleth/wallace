# T6040 trackpad — 25F63 pairing hypothesis refuted

Date: 2026-08-03

Ticket: 212 (offline half)

Rig use: **none**. This is static inspection of the pinned Mac16,8 25F84
restore and the already-extracted firmware corpus.

## Outcome

The existing `tpmtfw-j614s.bin` with SHA-256 `a1f4131d...` is already the
Apple-paired downstream firmware for the J614S MTP runtime that reports SDK
`25F63`. There is no 25F84-versus-25F63 mismatch to cure.

The key distinction is that `25F84` is the macOS restore build, while `25F63`
is the SDK string embedded in that restore's MTP coprocessor firmware. Apple's
single `j614sap` BuildIdentity pairs both of these payloads:

```text
Firmware/J614S_MtpFirmware.im4p
Firmware/J614s_Multitouch.im4p
```

The first decompresses to the exact runtime identity observed on the rig:

```text
AppleMTPFirmwareMac-5340.61.4~438
MTP_SYS
25F63
2026-04-18__18:25:06
```

The second is the source from which the existing
`vendorfw/apple/tpmtfw-j614s.bin` was extracted. Therefore hunting a separate
public "25F63 IPSW" was based on a category error: Apple itself ships the
25F63-built MTP runtime and this Multitouch payload together in 25F84 for
Mac16,8/J614s.

This refutes the version-skew hypothesis in ticket 212. Re-running the same
`a1f4131d...` blob under a different label cannot discriminate anything. The
observed failure remains the first post-upload `CMD_RESET_INTERFACE` state-0
request, not `CMD_SEND_FIRMWARE`; next work belongs in command/sequence and DMA
validation.

## Paired identity proof

The 25F84 BuildManifest identity has:

```text
Ap,ProductType = Mac16,8
Ap,Target      = J614sAP
Ap,TargetType  = j614s
DeviceClass    = j614sap
BuildNumber    = 25F84
```

Within that same identity:

```text
MtpFirmware:
  Path = Firmware/J614S_MtpFirmware.im4p
  IsFUDFirmware = true
  IsLoadedByiBoot = true

Multitouch:
  Path = Firmware/J614s_Multitouch.im4p
  IsFUDFirmware = true
  IsLoadedByiBoot = false
```

The decompressed MTP image contains the observed identity at byte offsets:

```text
374304  AppleMTPFirmwareMac-5340.61.4~438
374346  25F63
374352  2026-04-18__18:25:06
```

## Hashes

```text
a6e764ca158e10ea2ace9b74701f445eefbf012c9cdb5aaa616aa10a0b5197ef  BuildManifest.plist
d025f4478b5ad79fab920413eaa0bce57764535f8fb9b66380710fb1726bac81  J614S_MtpFirmware.im4p
6528799d227f2a78bc23ddd1870a70171587b3531da9e9950e6e402ac96763ed  J614S_MtpFirmware.bin
4f06afea3e412010fc56ed7dc1214d62fa48b400dbf4f75e261f14e8afe00bf4  J614s_Multitouch.im4p
a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2  tpmtfw-j614s.bin
```

Sizes:

```text
26534801  BuildManifest.plist
  897617  J614S_MtpFirmware.im4p
  897592  J614S_MtpFirmware.bin
  110787  J614s_Multitouch.im4p
   79960  tpmtfw-j614s.bin
```

The two Multitouch sizes differ because `tpmtfw-j614s.bin` is the HIDF artifact
emitted from the personalised IM4P input by the firmware extractor; equality
of those container hashes is neither expected nor asserted.

## Reproduction

```sh
ipsw download ipsw --device Mac16,8 --build 25F84 --macos \
  --pattern '(^|/)Firmware/J614S_MtpFirmware\.im4p$' \
  --output /private/tmp/wallace-offline-25F84 --confirm
ipsw img4 im4p info Firmware/J614S_MtpFirmware.im4p
ipsw img4 im4p extract --output J614S_MtpFirmware.bin \
  Firmware/J614S_MtpFirmware.im4p
strings -a J614S_MtpFirmware.bin | grep -A3 AppleMTPFirmwareMac
plutil -p BuildManifest.plist
shasum -a 256 BuildManifest.plist J614S_MtpFirmware.im4p \
  J614S_MtpFirmware.bin J614s_Multitouch.im4p tpmtfw-j614s.bin
```

## Next offline question

Compare Apple's first-party post-`0x95` state transition with the Linux patch's
unconditional reset sequence `0x40, 1, iface, 0` then
`0x40, 1, iface, 2`. Also instrument the three commands distinctly before any
repeat so a neighboring reset failure cannot again be attributed to upload.
That is source/firmware RE work; it does not justify a new blob or a rig run by
itself.

