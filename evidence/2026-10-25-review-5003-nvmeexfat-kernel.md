# Review 5003: NVMe exFAT write kernel config vs the reviewed 6001 config — PASS

Date: 2026-10-25. Reviewer: claude (Mythos Wallace session), offline, at
Opus Wallace's request. Build 1 only; build 2 hashes were not yet available.

Compared `~/code/linux-build-out/config-hid-type-fix-nbcon-nvmeexfat.build1`
(sha256 `1b19dabafc21c9103f3b1e42fc0bb97f3eb3e1f24aef747e1818cec00648e863`)
against the reviewed 6001 payload config
`~/code/linux-build-out/nvme-ioq-20261024b/payload/config`
(sha256 `02f1f1343c03878ef1de0d29c3c7a7b00be9abc3c470f13bb3f9e9561ad0ed6f`)
with `diff`. The complete difference is one hunk at line 10919:
`# CONFIG_EXFAT_FS is not set` becomes `CONFIG_EXFAT_FS=y` plus
`CONFIG_EXFAT_DEFAULT_IOCHARSET="utf8"`, which is the `NVME_EXFAT=1`
contract in commit `64dcbaf` and nothing else. No NVMe, SART, RTKit, SPMI,
block or driver-model symbol moved. **PASS** on the config gate: the
kernel is the reviewed 6001 kernel plus the exFAT filesystem. The write
test's other gates (byte-identical build 2, the `linux` partition
label-and-GPT-type check, payload review) are outside this check.
