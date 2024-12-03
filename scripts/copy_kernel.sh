#!/bin/bash
#
# Embedded Linux kernel partition extractor
#
# This script extracts the kernel partition from a firmware dump.
# Tested on HiSilicon and Ingenic firmware dumps from NOR SPI flash chips.
# Use at your own risk.
#
# 2023, Paul Philippov <paul@themactep.com>

if [ -z "$1" ]; then
    echo "Usage: $0 <stock firmware dump>"
    exit 1
fi

echo_c() {
    echo -e "\e[38;5;$1m$2\e[0m"
}

die() {
    echo_c 124 "Error! $1"
    exit 1
}

run() {
    echo_c 94 "$1"
    eval $1
}

say() {
    echo_c 72 "\n$1"
}

full_binary_file="$1"

bootcmd=$(strings "$full_binary_file" | grep -E "mtdparts=\w+_sfc:[0-9]" | tail -1)
[ -z "$bootcmd" ] && die "Cannot determine boot command!"
say "Boot command: $bootcmd"

offset_bytes=0
n=0

say "looking for mtd partitions"
mtdparts=$(echo $bootcmd | sed -E "s/(.*)(mtdparts=jz_sfc)/\\2/" | cut -d ' ' -f 1 | cut -d: -f2)
[ -z "$mtdparts" ] && die "Cannot determine partitioning!"
say "Partitioning: $mtdparts"

for p in ${mtdparts//,/ }; do
    p_size=$(echo $p | cut -d '(' -f 1)
    p_name=$(echo $p | cut -d '(' -f 2 | cut -d ')' -f 1)

    if [ "-" = "$p_size" ]; then
        p_size_bytes=""
    elif [ "0x" = "${p_size:0:2}" ]; then
        ## convert hex values
        p_size_bytes=$(($p_size))
    else
        p_size_value=$(echo $p_size | sed -E 's/[^0-9]//g')
        p_size_unit=$(echo $p_size | sed -E 's/[0-9]+//')
        if [ "k" = "${p_size_unit,,}" ]; then
            p_size_bytes=$((p_size_value * 1024))
        elif [ "m" = "${p_size_unit,,}" ]; then
            p_size_bytes=$((p_size_value * 1024 * 1024))
        else
            p_size_bytes=$p_size_value
        fi
    fi

    printf "%-14s\toffset: %8d\tsize: %8d\n" $p $offset_bytes $p_size_bytes
    if [ "$p_name" = "kernel" ]; then
        echo_c 190 "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        kernel_file=kernel.bin
        kernel_offset=$offset_bytes
        kernel_size=$p_size_bytes
    fi

    offset_bytes=$((offset_bytes + p_size_bytes))
    n=$((n + 1))
done

[ -z "$kernel_file" ] && die "Kernel partition not found!"

say "extract kernel partition from full dump: $kernel_size bytes at offset $kernel_offset"
run "dd if=$full_binary_file bs=1 skip=$kernel_offset count=$kernel_size of=$kernel_file status=progress"

say "Kernel partition extracted to $kernel_file"

say "Done!"

exit 0