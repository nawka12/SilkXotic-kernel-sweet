#!/usr/bin/env bash
# Build SilkXotic — crDroid sweet kernel + Safe optimizations, with the exact clang-r563880c.
# Run from anywhere; resolves the kernel tree as this script's grandparent dir.
set -euo pipefail

SX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KROOT="$(cd "$SX_DIR/.." && pwd)"        # kernel tree root
cd "$KROOT"

# Toolchain: exact AOSP clang-r563880c (clang 21.0.0) that built crDroid's stock kernel.
# Override with: TC_DIR=/path/to/clang  ./build-silkxotic.sh
TC_DIR="${TC_DIR:-/home/kayfa/Projects/kernel-sweet/toolchain/clang-r563880c}"
export PATH="$TC_DIR/bin:$PATH"
export ARCH=arm64 SUBARCH=arm64
JOBS="${JOBS:-6}"
OUT="${OUT:-out}"

if ! command -v clang >/dev/null || [ ! -x "$TC_DIR/bin/clang" ]; then
  echo "!! clang not found in TC_DIR=$TC_DIR — set TC_DIR to your clang-r563880c dir." >&2
  exit 1
fi

# LLVM_IAS=1 is REQUIRED: this clang-only toolchain ships no GNU 'as'; without it the
# Makefile adds -no-integrated-as and the build dies in scripts/mod with an assembler error.
TOOLS="LLVM_IAS=1 CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy \
OBJDUMP=llvm-objdump STRIP=llvm-strip READELF=llvm-readelf \
CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu-"

V="arch/arm64/configs/vendor"
echo ">>> $(date)  clang: $(clang --version | head -1)"
echo ">>> .config = sdmsteppe-perf + sweet + silkxotic-opts + silkxotic-slim + silkxotic-zram-zstd + silkxotic-net-bbr + buildhost-lowram + silkxotic-brand"
rm -rf "$OUT" && mkdir -p "$OUT"
ARCH=arm64 bash scripts/kconfig/merge_config.sh -O "$OUT" \
  "$V/sdmsteppe-perf_defconfig" \
  "$V/sweet.config" \
  "$V/silkxotic-opts.config" \
  "$V/silkxotic-slim.config" \
  "$V/silkxotic-zram-zstd.config" \
  "$V/silkxotic-net-bbr.config" \
  "$V/buildhost-lowram.config" \
  "$V/silkxotic-brand.config"

make O="$OUT" ARCH=arm64 $TOOLS olddefconfig

echo ">>> sanity: SilkXotic knobs + LTO mode + brand"
grep -E "CONFIG_(CPU_BOOST|SCHED_CORE_CTL|MSM_PERFORMANCE|SCHED_AUTOGROUP|BALANCE_ANON_FILE_RECLAIM|SLUB_CPU_PARTIAL|LTO_CLANG|THINLTO|LOCALVERSION)=" "$OUT/.config" | sort

echo ">>> building Image.gz (-j$JOBS, ThinLTO)  $(date +%T)"
make O="$OUT" ARCH=arm64 $TOOLS -j"$JOBS" Image.gz

# Base dtb carries the EAS energy model (sdmmagpie.dtsi). We ship a value-only-edited
# copy via AK3 (keeps the stock sweet dtbo). DTB build is fast; always rebuild fresh.
echo ">>> building base dtb (energy-model carrier: qcom/xiaomi-sdmmagpie.dtb)  $(date +%T)"
rm -f "$OUT/arch/arm64/boot/dts/qcom/xiaomi-sdmmagpie.dtb"
make O="$OUT" ARCH=arm64 $TOOLS qcom/xiaomi-sdmmagpie.dtb

img="$OUT/arch/arm64/boot/Image.gz"
dtb="$OUT/arch/arm64/boot/dts/qcom/xiaomi-sdmmagpie.dtb"
echo ">>> DONE $(date).  -> $img"
ls -lh "$img" "$dtb"
python3 - "$img" <<'PY'
import sys, gzip, io
d=gzip.GzipFile(fileobj=io.BytesIO(open(sys.argv[1],'rb').read())).read()
i=d.find(b'Linux version 4.14'); print(d[i:i+90].decode('latin1','replace'))
PY
echo ">>> Next: package with silkxotic/package-ak3.sh (ships modified base dtb, keeps crDroid dtbo)."
