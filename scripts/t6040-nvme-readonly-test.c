// SPDX-License-Identifier: MIT
// Fixed-scope, O_RDONLY/O_DIRECT test. No filesystem mounts or device writes.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/fs.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHUNK 16384U
#define BYTES (64U * 1024U * 1024U)
#define PASSES 4U
static int kmsg;

static void fail(const char *why)
{
    fprintf(stderr, "NVME-READONLY STOP: %s (errno=%d %s)\n", why, errno, strerror(errno));
    exit(1);
}

static void check_log(void)
{
    char line[8192];
    ssize_t n;
    while ((n = read(kmsg, line, sizeof(line) - 1)) > 0) {
        line[n] = 0;
        const char *bad[] = {"assert", "SError", "I/O error", "timed out", "timeout:", "timeout while",
            "controller is down", "crashed", "panic", "translation fault", "BUG:", "Oops:"};
        for (unsigned i = 0; i < sizeof(bad) / sizeof(*bad); i++)
            if (strcasestr(line, bad[i])) {
                fprintf(stderr, "NVME-READONLY kernel stop: %s", line);
                exit(1);
            }
    }
    if (n < 0 && errno != EAGAIN) fail("kernel log read/overrun");
}

int main(void)
{
    struct stat st;
    uint64_t size;
    int ro = 1;
    void *reference = NULL, *block = NULL;
    setvbuf(stdout, NULL, _IONBF, 0);
    // Userspace deadline; a kernel-blocked syscall can outlive SIGALRM.
    // The host must enforce its own stop/recovery deadline.
    alarm(240);
    kmsg = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (kmsg < 0) fail("open kernel log");
    check_log();
    int fd = open("/dev/nvme0n1", O_RDONLY | O_DIRECT | O_CLOEXEC);
    if (fd < 0) fail("open namespace read-only/direct");
    if (fstat(fd, &st) || !S_ISBLK(st.st_mode)) fail("not a block device");
    if (ioctl(fd, BLKROSET, &ro) || ioctl(fd, BLKROGET, &ro) || ro != 1)
        fail("set/verify block read-only");
    if (ioctl(fd, BLKGETSIZE64, &size) || size < BYTES) fail("namespace size");
    if (posix_memalign(&reference, CHUNK, BYTES) || posix_memalign(&block, CHUNK, CHUNK))
        fail("allocate aligned RAM buffers");
    printf("NVME-READONLY START bytes=%u chunk=%u passes=%u namespace_bytes=%" PRIu64 " ro=%d\n",
           BYTES, CHUNK, PASSES, size, ro);
    unsigned completed = 0;
    for (unsigned pass = 0; pass < PASSES; pass++) {
        for (unsigned off = 0; off < BYTES; off += CHUNK) {
            check_log();
            void *dst = pass ? block : (char *)reference + off;
            ssize_t n = pread(fd, dst, CHUNK, off);
            if (n != CHUNK) fail("short/failed direct read");
            if (pass && memcmp(block, (char *)reference + off, CHUNK))
                fail("data differs from first pass");
            completed++;
            if (!(completed % 256))
                printf("NVME-READONLY progress pass=%u direct_reads=%u\n", pass + 1, completed);
        }
        check_log();
        printf("NVME-READONLY pass=%u complete%s\n", pass + 1,
               pass ? " byte-for-byte match" : " reference retained in RAM");
    }
    check_log();
    close(fd);
    free(block);
    free(reference);
    printf("NVME-READONLY PASS direct_reads=%u bytes=%u repeated_bytes_match=yes\n",
           completed, BYTES * PASSES);
    return 0;
}
