#!/usr/bin/env bash
# Package the built Image.gz into a flashable AnyKernel3 zip that KEEPS crDroid's dtb/dtbo
# (no dtb/dtbo in the zip => no DT mismatch => no bootloop). Requires an AnyKernel3 template
# zip (any sweet AK3 works as the tools/installer carrier).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMG="${IMG:-out/arch/arm64/boot/Image.gz}"
AK3_TEMPLATE="${AK3_TEMPLATE:?set AK3_TEMPLATE=/path/to/anykernel3-sweet.zip}"
VER="${VER:-v1.0-Mulberry}"
OUTZIP="${OUTZIP:-SilkXotic-sweet-$VER.zip}"

[ -f "$IMG" ] || { echo "!! $IMG missing — build first."; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

cp -f "$AK3_TEMPLATE" "$OUTZIP"
zip -dq "$OUTZIP" Image.gz Image Image.gz-dtb dtbo.img dtb.img 2>/dev/null || true   # drop any payload + DT
cp -f "$IMG" "$work/Image.gz"
cp -f silkxotic/branding/banner "$work/banner" 2>/dev/null || true
unzip -oq "$OUTZIP" anykernel.sh -d "$work"
sed -i "s|^kernel.string=.*|kernel.string=SilkXotic $VER - smooth-tuned 4.14.357 (Tobrut Exotic DNA)|" "$work/anykernel.sh"
( cd "$work" && zip -q "$OLDPWD/$OUTZIP" Image.gz anykernel.sh banner 2>/dev/null || zip -q "$OLDPWD/$OUTZIP" Image.gz anykernel.sh )

echo ">>> $OUTZIP"
unzip -l "$OUTZIP" | grep -E "Image.gz|banner|anykernel|update-binary"
unzip -l "$OUTZIP" | grep -q "dtbo.img" && echo "!! WARNING: dtbo.img present" || echo "dtbo: absent (keeps ROM dtbo) OK"
