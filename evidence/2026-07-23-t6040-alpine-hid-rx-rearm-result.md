# T6040 Alpine HID RX re-arm result

Date: 2026-07-23  
Rig ticket: 071  
Result: **FAIL — Alpine/ttydc0 pass, DockChannel HID still absent**

## Exact inputs

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-hid-rx-rearm` | `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff` |
| `t6040-j614s-dcuart-hid-rx-rearm.dtb` | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| `initramfs-alpine-ramroot.cpio.gz` | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |
| embedded/config file | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The right-side USB stick was disconnected. The boot used the reviewed
single-core arguments and no `root=`.

## Result

Linux reached the Alpine RAM-root shell over `/dev/ttydc0`:

```text
Linux wallace-ramroot 7.1.3-g96ac043df12f-dirty ... aarch64 Linux
Alpine 3.24.0 (aarch64)
wallace-ramroot:~#
```

The bounded checks returned:

```text
3.24.0
aarch64

ls: /dev/input: No such file or directory

major minor  #blocks  name
```

`/proc/bus/input/devices` was empty, so the expected Apple `05ac:0359`
identity and keyboard event device were still absent. The operator key test
was not attempted because missing input registration was already the
pre-registered stop condition.

The shell remained responsive, `/proc/partitions` had no block devices, and no
SError, DART fault, watchdog reset, or lost DockChannel occurred. No module,
mount, network, storage, or extra diagnostic command was run.

This disproves the RX mask/drain/re-arm race as a sufficient explanation for
the current-kernel failure. The patch may still improve IRQ discipline, but it
must not be described as the HID fix or proposed upstream on this evidence.

## Recovery and evidence

The run stopped immediately after the missing-input result. DebugUSB recovery
returned the M4 to a quiescent `Running proxy...`; the lease was released
healthy.

| Evidence | Bytes | SHA-256 |
|---|---:|---|
| `linux-build-out/dcuart-console.log` | 874 | `9cf492446776b4cb3894e44de695814df24e4ac2b2c9646636a249277368d172` |
| `linux-build-out/dcuart-boot.log` | 25,483 | `66c05d30e40bc48d7210f2d0a8b5094711f49035c99dd20d5a4bb15b2498ab24` |
| `linux-build-out/dcuart-chainload.log` | 4,724 | `0e0fb79d099430e0690f8192c5a3f128c001a5f913f119141cc4ac9e3ae680cc` |

Next: use an observation-only kernel trace to locate the boundary among
DockChannel IRQ delivery, FIFO drain, DCHID event/report parsing, STM ready,
and identity/interface creation. Do not add another receive kick or retry the
same image.
