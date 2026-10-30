WALLACE M4 (J614s) - boot object cheat sheet
=============================================

Files
  wallace-5019/wallace-5019.build1.bin   5019 onboard debug kernel object (kexec, ftrace, pstore/ramoops)
                                         sha256 starts 28127903fb83ad4a
  wallace-nvmedesk/wallace-nvmedesk.build1.bin  5014 object (known-good), sha256 starts 6a522d648cf8e48d
  wallace-root.img                       Alpine root image. Never let 1TR repair or write this partition.

1) Enroll the 5019 object (in 1TR)
----------------------------------
Is it mounted?
  ls /Volumes/linux
If not (170 GiB Microsoft Basic Data partition, probably disk0s3):
  diskutil list
  diskutil mount disk0s3

Check the hash (must start with 28127903fb83ad4a):
  shasum -a 256 /Volumes/linux/wallace-5019/wallace-5019.build1.bin

Enroll:
  kmutil configure-boot -c /Volumes/linux/wallace-5019/wallace-5019.build1.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1

Dirty partition: macOS may mount it read-only or offer to repair. Read-only is fine for kmutil.
Do not let 1TR repair or write it.

Roll back to 5014: same kmutil command with /Volumes/linux/wallace-nvmedesk/wallace-nvmedesk.build1.bin
(hash starts 6a522d648cf8e48d), or with rollback-m1n1-1394c345.bin if that is on the partition.

2) Shutting down Linux
----------------------
Always poweroff or reboot. The SSD ignores Flush; a hard reset loses the newest writes.
  sync; poweroff

2b) Does the CURRENTLY enrolled kernel (5014) support kexec? Check first, on the running Linux
------------------------------------------------------------------------------------------
The 5014 kernel config and image strings suggest yes (CONFIG_KEXEC / KEXEC_FILE = y). Confirm:
  ls /sys/kernel/kexec_loaded /sys/kernel/kexec_crash_loaded   # files exist = kexec compiled in
  zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_KEXEC(_FILE)?="   # if /proc/config.gz exists
  grep -E "kexec|kimage" /proc/kallsyms | head -3
  ls /sys/kernel/kexec_loaded && cat /sys/kernel/kexec_loaded   # 0 = nothing loaded yet
Also check:
  cat /sys/block/nvme0n1/queue/write_cache                      # must say: write through
  uname -r; mount | grep -E "linux|nvme"                       # note which partition is mounted where
If kexec is present, you can run section 3 from 5014 and kexec straight into the 5019 files,
with no 1TR visit. Caveat: 5014 has no ramoops region, so a hung kexec leaves no pstore record.
If kexec is NOT present, enroll 5019 first (section 1).

2c) Is the exFAT partition clean?
---------------------------------
uname does not tell you. On the running Linux:
  dmesg | grep -i exfat           # "not properly unmounted" / "data may be corrupt" = dirty last shutdown
  mount | grep nvme0n1p3          # "ro" = kernel may have remounted read-only after an error
  dump.exfat /dev/nvme0n1p3 | grep -i "volume flags"    # needs exfatprogs; bit 0x2 = dirty.
                                  # While mounted rw the kernel sets it itself, so only trust it unmounted.
Authoritative, unmounted, read-only (-n makes no changes):
  Linux (not the partition holding the running root):
    umount /mnt/linux; fsck.exfat -n /dev/nvme0n1p3
  macOS:
    diskutil unmount disk0s3; fsck_exfat -n /dev/rdisk0s3; diskutil mount disk0s3
Never let macOS or 1TR repair it (wallace-root.img lives there).
Normal check: after a clean poweroff/reboot, the next boot's dmesg shows no exfat warning.

3) New kernel without 1TR: kexec (ticket 5021, feasibility test)
----------------------------------------------------------------
From the Mac (build with the kbuild container first), copy files to the running M4 Linux:
  scp Image  root@<m4-ip>:/root/Image
  scp board.dtb root@<m4-ip>:/root/board.dtb

On the M4 (Linux):
  apk add kexec-tools
  cat /sys/block/nvme0n1/queue/write_cache        # must say: write through
  sync

Step 1, handoff to the SAME kernel (tests kexec itself, no new kernel in the way):
  # needs the 5024 object booted (nr_cpus=1); with maxcpus=1 alone the kernel refuses:
  # "Can't kexec: CPUs are stuck in the kernel"
  kexec -l /mnt/linux/wallace-5019/Image --dtb=/mnt/linux/wallace-5019/board.dtb --initrd=/mnt/linux/wallace-5019/initramfs.cpio.gz \
        --command-line="nr_cpus=1 maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel printk.devkmsg=on console=ttydc0 console=tty0 rdinit=/init"
  sync
  kexec -e

(wallace-5019/ holds the uncompressed Image, board.dtb and initramfs of the running 5019 kernel. The partition is probably at /mnt/linux; adjust if not.)
KEXEC_FILE is also built in, so `kexec -s -l ...` works if the plain load fails.

Step 2, once step 1 passes, load the new kernel instead:
  kexec -l /root/Image --dtb=/root/board.dtb --initrd=<initramfs> --command-line="<same cmdline>"
  sync; kexec -e

If it hangs: hard power cycle, then read the crash record after the next boot:
  mount -t pstore pstore /sys/fs/pstore; ls /sys/fs/pstore
(Check /proc/iomem for "ramoops" - the region address is unverified.)

Checks after a successful handoff: uname -r, NVMe root mounted clean, WiFi, keyboard/trackpad,
dmesg for DART faults or RTKit crashes.

Cmdline source: wallace-5019/bootargs.txt
