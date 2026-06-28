#!/usr/bin/env bash
# Package the built Image.gz (+ optional value-only-edited base dtb) into a flashable AK3 zip.
# We ship the modified xiaomi-sdmmagpie.dtb as AK3's "dtb" (AK3 prefers $AKHOME/dtb over the
# stock split dtb), so the EAS energy-model edit applies. The sweet DTBO stays crDroid's — it
# is NEVER in the zip => no overlay mismatch => no bootloop. Needs an AK3 template zip (carrier).
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMG="${IMG:-out/arch/arm64/boot/Image.gz}"
DTB="${DTB:-out/arch/arm64/boot/dts/qcom/xiaomi-sdmmagpie.dtb}"   # base dtb (energy model); missing => kernel-only
AK3_TEMPLATE="${AK3_TEMPLATE:?set AK3_TEMPLATE=/path/to/anykernel3-sweet.zip}"
VER="${VER:-v1.0-Mulberry}"
OUTZIP="${OUTZIP:-SilkXotic-sweet-$VER.zip}"

[ -f "$IMG" ] || { echo "!! $IMG missing — build first."; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

cp -f "$AK3_TEMPLATE" "$OUTZIP"
zip -dq "$OUTZIP" Image.gz Image Image.gz-dtb dtb dtbo.img dtb.img 2>/dev/null || true  # drop any payload + DT
cp -f "$IMG" "$work/Image.gz"
cp -f silkxotic/branding/banner "$work/banner" 2>/dev/null || true

zipfiles="Image.gz anykernel.sh"
[ -f "$work/banner" ] && zipfiles="$zipfiles banner"
if [ -n "$DTB" ] && [ -f "$DTB" ]; then
  cp -f "$DTB" "$work/dtb"                 # AK3 ships this as the boot.img base dtb; stock dtbo untouched
  zipfiles="$zipfiles dtb"
  echo ">>> including modified base dtb: $DTB  (md5 $(md5sum "$DTB" | cut -d' ' -f1))"
else
  echo ">>> no dtb at '$DTB' — kernel-only (keeps stock dtb too)"
fi

unzip -oq "$OUTZIP" anykernel.sh -d "$work"
sed -i "s|^kernel.string=.*|kernel.string=SilkXotic $VER - smooth-tuned 4.14.357 (Tobrut Exotic DNA)|" "$work/anykernel.sh"
( cd "$work" && zip -q "$OLDPWD/$OUTZIP" $zipfiles )

echo ">>> $OUTZIP"
unzip -l "$OUTZIP" | grep -E "Image.gz| dtb$|banner|anykernel|update-binary"
unzip -l "$OUTZIP" | grep -qE " dtb$" && echo "dtb: present (modified base dtb) OK" || echo "dtb: absent (kernel-only)"
unzip -l "$OUTZIP" | grep -q "dtbo.img" && echo "!! WARNING: dtbo.img present" || echo "dtbo: absent (keeps ROM dtbo) OK"
