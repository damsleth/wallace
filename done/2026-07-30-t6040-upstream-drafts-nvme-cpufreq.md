# Upstream drafts for CJ — NVMe `reg_len`, firmware gating, cpufreq overflow

These are drafts only. CJ posts externally; agents do not.

## 1. m1n1 NVMe: `reg_len` is bytes, not an entry count

Suggested subject:

```
nvme: compare the ANS reg property length in bytes
```

Suggested commit message:

```
adt_getprop() returns the encoded property length in bytes. Each
/arm-io/ans reg tuple contains two address cells and two size cells, so
one entry is 16 bytes.

Testing reg_len >= 10 therefore selects the extended M4 layout on every
existing ANS node with at least one reg entry. Pre-M4 machines then try
to fetch the nonexistent reg[9] controller aperture instead of retaining
reg[3] as the combined controller/NVMMU window.

Compare against ten encoded entries. The captured J614s /arm-io/ans
property is exactly 160 bytes and contains reg[9]; older layouts remain
on reg[3].

Signed-off-by: CJ Damsleth <kim@damsleth.no>
```

Suggested delta:

```diff
-	if (reg_len >= 10) {
+	if (reg_len >= 10 * 16) {
```

Prefer `10 * 16` in the upstream diff because it directly expresses that the
left side is bytes. If m1n1 gains a shared ADT-reg tuple-size constant, use
that instead of the literal.

## 2. m1n1 NVMe: an unknown exact string has no chronological meaning

Suggested subject:

```
nvme: do not order V_UNKNOWN against firmware releases
```

Suggested report/commit message:

```
detect_firmware() uses an exact full-string match and maps every unlisted
iBoot/mBoot string to V_UNKNOWN, whose enum value is zero. The NVMe
legacy-register gate currently orders that sentinel against V15_0B1.

This is unsafe in both directions. A new build such as
mBoot-18000.121.3 compares older than 15.0 and re-enables
LINEAR_SQ_CTRL/UNKNOWN_CTRL accesses that no longer exist; on a T6040
J614s the LINEAR_SQ_CTRL access raised an asynchronous SError. Conversely,
treating every V_UNKNOWN as new would skip required legacy setup for an
unlisted pre-15 beta, security release, or vendor build.

Use the parsed iBoot/mBoot build number (or a hardware capability) for
this boundary instead of ordering the exact-match enum sentinel. m1n1's
firmware_sfw_in_range() already compares parsed system-firmware build
numbers; if the ANS contract follows OS firmware, add the equivalent
OS-firmware helper rather than special-casing V_UNKNOWN.

On mBoot-18000.121.3 the correct result is post-15: skip the two legacy
accesses.

Signed-off-by: CJ Damsleth <kim@damsleth.no>
```

Do **not** upstream the Wallace-local condition
`version != V_UNKNOWN && version < V15_0B1` as a general fix. It is the
correct fail-safe for this exact T6040 experiment, but it silently
misclassifies genuinely old unknown strings.

If maintainers confirm that the register contract follows system firmware,
the intended form is:

```c
if (!firmware_sfw_in_range(V15_0B1, FW_MAX)) {
	set32(nvme_base + NVME_LINEAR_SQ_CTRL, NVME_LINEAR_SQ_CTRL_EN);
	clear32(nvme_base + NVME_UNKNOWN_CTRL,
		NVME_UNKNOWN_CTRL_PRP_NULL_CHECK);
}
```

## 3. Linux cpufreq: widen the kHz-to-Hz multiplication

Suggested subject:

```
cpufreq: apple-soc: avoid overflow converting kHz to Hz
```

Suggested commit message:

```
freq_table[i].frequency is unsigned int in kHz. Multiplying it by 1000
therefore happens in 32-bit arithmetic before the result is assigned to
unsigned long. Frequencies above UINT_MAX / 1000 wrap, causing
dev_pm_opp_find_freq_floor() to search below the real OPP and fail with
-ERANGE.

This prevents the affected policy from registering. It is easy to miss
because this return path has no driver error message; the cpufreq core
only reports the ->init() failure at debug level.

The issue is reproducible with the 4,416,000 and 4,512,000 kHz P-cluster
OPPs on a T6040 J614s. Its E-cluster policy registers normally, while
both P-cluster policies fail. Widening before the multiplication makes
the P policy register and transition through 1,260,000–4,512,000 kHz.

Use an unsigned-long multiplier so the arithmetic has the destination
width.

Fixes: 6286bbb40576 ("cpufreq: apple-soc: Add new driver to control Apple SoC CPU P-states")
Signed-off-by: CJ Damsleth <kim@damsleth.no>
```

Suggested delta:

```diff
-		unsigned long rate = freq_table[i].frequency * 1000 + 999;
+		unsigned long rate = freq_table[i].frequency * 1000UL + 999;
```

Avoid the broader claim “M4 is the first possible machine affected” unless
the complete upstream OPP history has been checked. The concrete, sufficient
claim is that T6040's observed 4.416/4.512 GHz entries cross the 32-bit
kHz-to-Hz boundary and reproduce the failure.
