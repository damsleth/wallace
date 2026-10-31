#!/usr/bin/perl
# Dump the /memreserve/ entries of the live FDT (or a .dtb) and show how they relate to the ADT
# reservation, for the 5015 reservation checks. Read-only; needs no Python.
#   t6040-fdt-memreserve.pl                  # reads /sys/firmware/fdt
#   t6040-fdt-memreserve.pl file.dtb
# Output: one line per entry (start, end, size, note). The note marks the entry that begins at
# the ADT end ("TrustCache gap"), anything inside the m1n1 slot, and the per-secondary blocks.
use strict;
use warnings;

my $path = shift // '/sys/firmware/fdt';
open(my $fh, '<:raw', $path) or die "$path: $!\n";
local $/;
my $blob = <$fh>;
close $fh;

my ($magic, $total, $off_struct, $off_strings, $off_rsv) = unpack('N5', $blob);
die "not an FDT (magic " . sprintf('%08x', $magic) . ")\n" if $magic != 0xd00dfeed;

my @e;
for (my $o = $off_rsv;; $o += 16) {
    my ($hi1, $lo1, $hi2, $lo2) = unpack('N4', substr($blob, $o, 16));
    my $st = ($hi1 << 32) | $lo1;
    my $sz = ($hi2 << 32) | $lo2;
    last if !$st && !$sz;
    push @e, [$st, $sz];
}

# The ADT is published as a reserved-memory node labelled "adt" by m1n1; find it via its reg.
my $adt_end;
if ($blob =~ /adt\0/) {
    # label property value "adt"; the sibling reg is easier to read from /proc/device-tree
    my $dir = '/proc/device-tree/reserved-memory';
    if (-d $dir) {
        for my $n (glob("$dir/flash\@*")) {
            open(my $lf, '<', "$n/label") or next;
            my $l = <$lf>; close $lf;
            next unless defined $l && $l =~ /^adt\0?$/;
            open(my $rf, '<:raw', "$n/reg") or next;
            my $r = <$rf>; close $rf;
            my ($h1, $l1, $h2, $l2) = unpack('N4', $r);
            $adt_end = (($h1 << 32) | $l1) + (($h2 << 32) | $l2);
        }
    }
}

printf "%d /memreserve/ entries in %s%s\n", scalar(@e), $path,
    defined $adt_end ? sprintf(", ADT ends at 0x%x", $adt_end) : "";
my $n = 0;
for my $e (sort { $a->[0] <=> $b->[0] } @e) {
    my ($st, $sz) = @$e;
    my $note = '';
    $note = 'starts at the ADT end (TrustCache gap)' if defined $adt_end && $st == $adt_end;
    $note = 'inside the TrustCache gap' if defined $adt_end && $st > $adt_end && $st < $adt_end + 0x60000;
    $note = 'secondary stack-sized block' if $sz == 0x10000;
    printf "  0x%011x .. 0x%011x  size 0x%07x  %s\n", $st, $st + $sz, $sz, $note;
    $n++;
}
if (defined $adt_end) {
    my $gap_covered = grep { $_->[0] <= $adt_end && $_->[0] + $_->[1] >= $adt_end + 0x60000 } @e;
    printf "TrustCache gap [0x%x, 0x%x): %s\n", $adt_end, $adt_end + 0x60000,
        $gap_covered ? 'RESERVED' : 'NOT reserved (Linux can allocate it)';
}
