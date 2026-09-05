#!/usr/bin/env python3
"""Mean per-pixel drift between two raw `adb exec-out screencap` captures, as a percentage.

Used by benchgame.sh as the scene gate. A live game's frame rate is dominated by what is on
screen, so an A/B is only meaningful if the scene held still: this quantifies "held still".
Raw RGBA is used rather than PNG so the harness needs no image library.

Rough calibration on hololive Dreams: <1% = character parked and camera still (usable);
~3-8% = idle animation or particles in frame (borderline); >15% = the character moved, a menu
opened, or the in-game day/night cycle rolled over (discard the iteration).

Usage: scenedrift.py <capA.raw> <capB.raw>  -> prints a float percentage
"""
import sys, struct

def load(path):
    b = open(path, "rb").read()
    if len(b) < 16: raise ValueError("capture too short")
    w, h, _f = struct.unpack_from("<III", b, 0)
    px = w * h * 4
    hdr = len(b) - px
    if hdr not in (12, 16):           # screencap grew a colorspace field in Android S
        raise ValueError(f"unexpected header size {hdr} (w={w} h={h} len={len(b)})")
    return w, h, memoryview(b)[hdr:]

def main():
    if len(sys.argv) != 3: sys.exit(__doc__)
    wa, ha, a = load(sys.argv[1])
    wb, hb, b = load(sys.argv[2])
    if (wa, ha) != (wb, hb):
        print("100.0"); return       # resolution changed => definitively a different scene
    # Sample a sparse grid (~40k px) rather than every pixel: same answer, ~60x faster.
    total = wa * ha
    step = max(1, total // 40000)
    acc = n = 0
    for i in range(0, total, step):
        o = i * 4
        acc += abs(a[o] - b[o]) + abs(a[o+1] - b[o+1]) + abs(a[o+2] - b[o+2])
        n += 1
    print(f"{(acc / (n * 3 * 255)) * 100:.3f}")

main()
