Reviewer harness (sonnet, 2026-10-25). It extracts the probe section of the
*committed* `scripts/t6040-init-nvme-p3-identity` (from `# u32/u8` to
`say 'IDENTITY-DONE'`, with `park` stubbed), rewrites `/dev/nvme0n1` to a loop
device, and runs it under the initramfs's own BusyBox (`61781806…`) against
four GPT images built with sgdisk/mkfs.exfat. Run in the podman machine as root:

    awk '/^# u32\/u8 little-endian/{f=1} f{print} /^say .IDENTITY-DONE./{exit}' \
        scripts/t6040-init-nvme-p3-identity > $S/t_section.sh
    podman machine ssh "sudo podman run --rm --privileged --platform linux/arm64 \
        -v <extracted initramfs>/bin:/b:ro -v $S:/t:ro alpine:3.22 sh /t/run-in-podman.sh"

(run-in-podman.sh expects to be copied next to t_section.sh as `/t/t_run.sh`.)
Write counters in the "stats after" lines include sgdisk/mkfs writes made by the
harness, so they are not evidence about the probe.
