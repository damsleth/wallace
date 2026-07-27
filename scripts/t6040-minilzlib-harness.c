#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "minilzlib/minlzma.h"

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <file.xz>\n", argv[0]); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open"); return 2; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *in = malloc(n);
    if (fread(in, 1, n, f) != (size_t)n) { perror("read"); return 2; }
    fclose(f);

    // Exactly as m1n1 payload.c decompress_xz: dest_len starts at 1 GiB.
    uint32_t source_len = (uint32_t)n;
    uint32_t dest_len = 1u << 30;
    uint8_t *dest = malloc(dest_len);   // real buffer; on target this is heap top
    if (!dest) { fprintf(stderr, "OOM allocating 1 GiB output\n"); return 3; }

    printf("Uncompressing... ");
    fflush(stdout);
    int ret = XzDecode(in, &source_len, dest, &dest_len);
    if (!ret) { printf("XZ decode failed\n"); return 1; }
    printf("%u bytes uncompressed to %u bytes\n", source_len, dest_len);
    return 0;
}
