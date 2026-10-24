/* SPDX-License-Identifier: MIT
 * Read-only, identity-bound GPT/ext4 gate for the external USB root.
 * Author: CJ Damsleth <kim@damsleth.no>
 *
 * This validates media metadata, NOT USB ancestry, fsck or live correctness.
 * The init-side caller must establish the reviewed USB/sysfs identity first.
 * --image accepts regular files only; --disk accepts Linux block devices only.
 * Neither mode has a write, mount, repair, reset or ioctl mutation operation.
 */
#define _FILE_OFFSET_BITS 64
#define _POSIX_C_SOURCE 200809L
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __linux__
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <sys/sysmacros.h>
#endif

#define SECTOR 512u
#define MAX_ARRAY (1024u * 1024u)
#define LINUX_FS "0fc63daf-8483-4772-8e79-3d69d8477de4"
static int fd = -1;
static uint64_t media_bytes;

static void die(const char *why)
{
    fprintf(stderr, "usb-root-metadata: STOP: %s\n", why);
    if (fd >= 0) close(fd);
    exit(1);
}
static uint16_t le16(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }
static uint32_t le32(const uint8_t *p)
{ return (uint32_t)le16(p) | (uint32_t)le16(p + 2) << 16; }
static uint64_t le64(const uint8_t *p)
{ return le32(p) | (uint64_t)le32(p + 4) << 32; }
static uint32_t crc32(const uint8_t *p, size_t n)
{
    uint32_t c = UINT32_MAX;
    while (n--) {
        c ^= *p++;
        for (int b = 0; b < 8; b++) c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1u)));
    }
    return ~c;
}
static void read_at(void *p, size_t n, uint64_t off)
{
    if (off > media_bytes || n > media_bytes - off || off > INT64_MAX)
        die("read outside pinned media bounds");
    uint8_t *q = p;
    while (n) {
        ssize_t k = pread(fd, q, n, (off_t)off);
        if (k < 0 && errno == EINTR) continue;
        if (k <= 0) die("short or failed read");
        q += k; off += (uint64_t)k; n -= (size_t)k;
    }
}
static uint64_t number(const char *s)
{
    char *end; unsigned long long n;
    if (!s[0] || strspn(s, "0123456789") != strlen(s)) die("invalid decimal argument");
    errno = 0; n = strtoull(s, &end, 10);
    if (errno || *end || !n) die("invalid numeric argument");
    return (uint64_t)n;
}
static int nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}
static void uuid(const char *s, uint8_t out[16], int gpt)
{
    uint8_t b[16]; size_t i = 0, j = 0;
    if (strlen(s) != 36) die("UUID must use lowercase canonical format");
    while (i < 36) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if (s[i++] != '-') die("invalid UUID separator");
            continue;
        }
        int a = nibble(s[i++]), c = nibble(s[i++]);
        if (a < 0 || c < 0 || j >= 16) die("invalid UUID digit");
        b[j++] = (uint8_t)(a * 16 + c);
    }
    if (j != 16) die("invalid UUID length");
    uint8_t any = 0;
    for (i = 0; i < 16; i++) any |= b[i];
    if (!any) die("zero UUID is not an identity");
    if (gpt) {
        const int order[] = {3,2,1,0,5,4,7,6,8,9,10,11,12,13,14,15};
        for (i = 0; i < 16; i++) out[i] = b[order[i]];
    } else memcpy(out, b, 16);
}
struct header {
    uint64_t current, backup, first, last, table;
    uint32_t count, entry_size, array_crc;
    uint8_t guid[16];
};
static struct header header(uint64_t lba, uint64_t layout_sectors)
{
    uint8_t b[SECTOR], copy[SECTOR];
    struct header h;
    read_at(b, sizeof b, lba * SECTOR);
    if (memcmp(b, "EFI PART", 8) || le32(b + 8) != 0x10000 || le32(b + 20))
        die("invalid GPT signature, revision or reserved field");
    uint32_t n = le32(b + 12);
    if (n < 92 || n > SECTOR) die("invalid GPT header size");
    memcpy(copy, b, n); memset(copy + 16, 0, 4);
    if (crc32(copy, n) != le32(b + 16)) die("GPT header CRC mismatch");
    h.current = le64(b + 24); h.backup = le64(b + 32);
    h.first = le64(b + 40); h.last = le64(b + 48);
    memcpy(h.guid, b + 56, 16);
    h.table = le64(b + 72); h.count = le32(b + 80);
    h.entry_size = le32(b + 84); h.array_crc = le32(b + 88);
    if (h.current != lba || h.backup >= layout_sectors || h.first > h.last ||
        h.first < 3 || h.last >= layout_sectors - 1 ||
        h.count == 0 || h.entry_size < 128 || h.entry_size % 128 ||
        (h.entry_size / 128 & (h.entry_size / 128 - 1)) ||
        h.count > MAX_ARRAY / h.entry_size)
        die("invalid or excessive GPT geometry");
    uint64_t array_sectors = ((uint64_t)h.count * h.entry_size + SECTOR - 1) / SECTOR;
    if (h.table < 2 || h.table >= layout_sectors || array_sectors > layout_sectors - h.table)
        die("GPT array outside pinned layout");
    if (lba == 1) {
        if (h.backup != layout_sectors - 1 || h.table != 2 ||
            h.table + array_sectors > h.first)
            die("primary GPT overlaps usable sectors or wrong backup location");
    } else if (h.backup != 1 || h.table <= h.last ||
               h.table + array_sectors != lba) {
        die("backup GPT overlaps usable sectors or wrong primary location");
    }
    return h;
}
static uint8_t *array(const struct header *h)
{
    size_t n = (size_t)h->count * h->entry_size;
    uint8_t *p = malloc(n);
    if (!p) die("allocation failed");
    read_at(p, n, h->table * SECTOR);
    if (crc32(p, n) != h->array_crc) die("GPT partition-array CRC mismatch");
    return p;
}
static int zero(const uint8_t *p, size_t n)
{
    while (n--) if (*p++) return 0;
    return 1;
}
int main(int argc, char **argv)
{
    const char *path = NULL, *disk_id = NULL, *part_id = NULL, *fs_id = NULL;
    uint64_t layout_bytes = 0, expected_media = 0;
    const char *device_number = NULL;
    int disk = -1;
    for (int i = 1; i < argc; i += 2) {
        if (i + 1 == argc) die("option missing value");
        const char *v = argv[i + 1];
        if (!strcmp(argv[i], "--image") || !strcmp(argv[i], "--disk")) {
            if (path) die("multiple input paths");
            path = v; disk = !strcmp(argv[i], "--disk");
        } else if (!strcmp(argv[i], "--disk-guid") && !disk_id) disk_id = v;
        else if (!strcmp(argv[i], "--partuuid") && !part_id) part_id = v;
        else if (!strcmp(argv[i], "--fsuuid") && !fs_id) fs_id = v;
        else if (!strcmp(argv[i], "--media-bytes") && !expected_media) expected_media = number(v);
        else if (!strcmp(argv[i], "--layout-bytes") && !layout_bytes) layout_bytes = number(v);
        else if (!strcmp(argv[i], "--device-number") && !device_number) device_number = v;
        else die("unknown or repeated option");
    }
    if (!path || !disk_id || !part_id || !fs_id || !layout_bytes || !expected_media)
        die("require input mode, disk-guid, partuuid, fsuuid, media-bytes and layout-bytes");
    if (layout_bytes % SECTOR || expected_media % SECTOR ||
        layout_bytes > expected_media || layout_bytes < 68 * SECTOR || expected_media > INT64_MAX)
        die("invalid pinned layout or media length");
    uint8_t dg[16], pg[16], fg[16], type[16];
    uuid(disk_id, dg, 1); uuid(part_id, pg, 1); uuid(fs_id, fg, 0); uuid(LINUX_FS, type, 1);
    struct stat before;
    if (lstat(path, &before) ||
        (!disk && !S_ISREG(before.st_mode)) ||
        (disk && !S_ISBLK(before.st_mode))) die("input has the wrong type or is a symlink");
    if (disk) {
#ifdef __linux__
        char actual[64];
        snprintf(actual, sizeof actual, "%u:%u", major(before.st_rdev), minor(before.st_rdev));
        if (!device_number || strcmp(device_number, actual)) die("device number differs from sysfs identity");
#else
        die("--disk is Linux-only");
#endif
    } else if (device_number) die("device-number is only valid in disk mode");
    /* O_NOFOLLOW also rejects a surprise device alias at the last path component. */
    fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) die("cannot open input read-only");
    struct stat st;
    if (fstat(fd, &st) || st.st_dev != before.st_dev || st.st_ino != before.st_ino ||
        st.st_rdev != before.st_rdev) die("input identity changed during open");
    if (!disk) {
        if (!S_ISREG(st.st_mode) || st.st_size < 0) die("--image requires a regular file");
        media_bytes = (uint64_t)st.st_size;
    } else {
#ifdef __linux__
        int sector_size = 0;
        if (!S_ISBLK(st.st_mode)) die("--disk requires a block device");
        if (ioctl(fd, BLKSSZGET, &sector_size) || sector_size != SECTOR ||
            ioctl(fd, BLKGETSIZE64, &media_bytes)) die("unsupported block geometry");
#else
        die("--disk is Linux-only");
#endif
    }
    if (media_bytes != expected_media) die("media length differs from pinned capacity");
    uint64_t sectors = layout_bytes / SECTOR;
    uint8_t mbr[SECTOR];
    read_at(mbr, sizeof mbr, 0);
    if (mbr[510] != 0x55 || mbr[511] != 0xaa || mbr[446 + 4] != 0xee ||
        mbr[446] || le32(mbr + 446 + 8) != 1 ||
        le32(mbr + 446 + 12) != (sectors - 1 > UINT32_MAX ? UINT32_MAX : sectors - 1) ||
        !zero(mbr + 462, 48)) die("invalid protective MBR or hybrid partition table");
    struct header a = header(1, sectors), b = header(sectors - 1, sectors);
    if (memcmp(a.guid, dg, 16) || memcmp(b.guid, dg, 16) ||
        a.first != b.first || a.last != b.last || a.count != b.count ||
        a.entry_size != b.entry_size || a.array_crc != b.array_crc)
        die("GPT copies or disk GUID disagree");
    uint8_t *pa = array(&a), *pb = array(&b);
    size_t array_bytes = (size_t)a.count * a.entry_size;
    if (memcmp(pa, pb, array_bytes)) die("GPT partition arrays disagree");
    /* The reviewed image has exactly one partition, at entry 1. No discovery
     * by label, first match, /dev enumeration order, or UUID-only fallback. */
    if (memcmp(pa, type, 16) || memcmp(pa + 16, pg, 16)) die("partition type or PARTUUID mismatch");
    for (uint32_t i = 1; i < a.count; i++)
        if (!zero(pa + (size_t)i * a.entry_size, a.entry_size)) die("unexpected additional GPT partition");
    uint64_t first = le64(pa + 32), last = le64(pa + 40);
    if (first != 2048 || first < a.first || first > last || last > a.last || le64(pa + 48))
        die("unexpected root extent or GPT attributes");
    const char *label = "t6040root";
    for (size_t i = 0; i < 36; i++)
        if (le16(pa + 56 + i * 2) != (i < strlen(label) ? (unsigned char)label[i] : 0))
            die("GPT root label mismatch");
    uint8_t sb[1024];
    read_at(sb, sizeof sb, first * SECTOR + 1024);
    if (le16(sb + 56) != 0xef53 || le32(sb + 76) != 1 || memcmp(sb + 104, fg, 16))
        die("ext4 magic, revision or UUID mismatch");
    char fs_label[16] = "t6040root";
    if (memcmp(sb + 120, fs_label, 16)) die("ext4 label mismatch");
    if (le16(sb + 58) != 1 || (le32(sb + 96) & 4)) die("ext4 is dirty, errored or needs journal replay");
    uint32_t shift = le32(sb + 24);
    if (shift > 6) die("unsupported ext4 block size");
    uint64_t block_size = 1024ull << shift, blocks = le32(sb + 4);
    if (le32(sb + 96) & 0x80) blocks |= (uint64_t)le32(sb + 0x150) << 32;
    uint64_t part_bytes = (last - first + 1) * SECTOR;
    if (!blocks || blocks > part_bytes / block_size) die("ext4 size exceeds root partition");
    free(pa); free(pb); close(fd); fd = -1;
    printf("format=t6040-usb-root-metadata-v1\npartition_number=1\n");
    printf("disk_guid=%s\npartuuid=%s\nfilesystem_uuid=%s\n", disk_id, part_id, fs_id);
    printf("partition_first_lba=%" PRIu64 "\npartition_last_lba=%" PRIu64 "\n", first, last);
    printf("media_bytes=%" PRIu64 "\nlayout_bytes=%" PRIu64 "\n", media_bytes, layout_bytes);
    puts("gpt_copies=verified\nfilesystem_type=ext4\nfilesystem_label=t6040root\next4_state=clean\nmetadata_gate=PASS");
    return 0;
}
