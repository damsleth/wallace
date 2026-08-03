# T6040 Alpine keyboard-control result

Date: 2026-07-23  
Rig ticket: 070  
Result: **FAIL before framebuffer shell; keyboard result inconclusive**

## Runs

The approved control used:

| Artifact | SHA-256 |
|---|---|
| m1n1 | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-keyboard` | `cc2b3de15efbf4fbf5c4d7ac7d6b8155e5c4c52e0deabd9e012ffa379b37fb58` |
| `t6040-j614s-kbd.dtb` | `2c23495973edb37f07cc7abab2377578a1f57837ca9f93fc5ae15b8a70961577` |
| Alpine RAM-root | `fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b` |

Both the approved run and one maintainer-requested exact retry completed the
m1n1/Linux upload and handoff. In both runs m1n1 reported DAPF initialization
for `dart-mtp`, armed the warm-reset watchdog, and vectored to Linux.

The operator saw kernel text followed by the Asahi/m1n1 logo. The expected
Alpine framebuffer prompt never appeared, so `ALPINE_KBD_OK` could not be
entered. This is consistent with a watchdog warm reset before the framebuffer
shell, but the old kernel intentionally has no ttydc0 and therefore provided no
post-handoff host log to locate the final kernel line.

This does **not** show that Alpine rejects keyboard input. It shows that the
old 7.2-rc2 keyboard kernel plus the current keyboard DT and 3.9 MB Alpine
initramfs is not a usable control combination. The exact 7.2-rc2 kernel remains
valid evidence for its earlier BusyBox/keyboard run, but should not be retried
with this Alpine combination.

After the retry, DebugUSB recovery returned the M4 to a stable
`Running proxy...` state.

## Next

Continue offline ticket 069: fix the DockChannel HID receive regression in the
current 7.1.3 storage-disabled kernel while retaining ttydc0. That path already
boots this exact Alpine RAM-root and gives a host-visible failure boundary; it
is a better base than further old-kernel recombinations.
