# SilkXotic — brand identity

> **SilkXotic** · *“exotic tuning, silk finish”*
> A smooth-tuned crDroid kernel for Redmi Note 10 Pro (`sweet`). The refined, silk-smooth
> sibling of **BruthXotic / Tobrut Exotic** — same Exotic tuning DNA, none of the bloat.

## Name
- **SilkXotic** (one word, capital S and X). Spoken: *“Silk-Xotic.”*
- The `-Xotic` suffix is the lineage marker (BruthXotic family); **Silk** is the promise (smoothness).
- Positioning line: **“BruthXotic was brutal — this is silk.”**

## Taglines
- Primary: **exotic tuning, silk finish**
- Alt: *smooth-tuned, exotic core* · *six cuts, zero bloat* · *brutal, refined to silk*

## Story / positioning
BruthXotic delivers raw Exotic tuning but ships heavy (debug on, LTO off) and breaks on ROM bumps.
SilkXotic takes the **genuinely useful** part of that tuning and grafts it onto crDroid's own kernel:
LTO kept on, debug stripped, KSU/SUSFS intact, dtbo untouched — so it's smooth *and* it can't bootloop
the way the prebuilt did. Lean by design: **6 surgical knobs, nothing else touched.**

## Versioning
- **v1.0 — “Mulberry”** (silk's source). Future releases follow a silk-weave codename scheme:
  Mulberry → Charmeuse → Habotai → Dupioni → Organza …
- Kernel `uname`: `4.14.357-silkxotic` (set via `vendor/silkxotic-brand.config`).

## What's inside (the elevator pitch)
crDroid `4.14.357` stock + 6 Safe knobs: `CPU_BOOST`, `SCHED_CORE_CTL`, `MSM_PERFORMANCE`,
`SCHED_AUTOGROUP`, `BALANCE_ANON_FILE_RECLAIM`, `SLUB_CPU_PARTIAL`. Built with the exact `clang-r563880c`.

## Color palette
| Token | Hex | Use |
|---|---|---|
| Ink (warm black) | `#16120F` | backgrounds, banner bg |
| Silk (highlight) | `#ECEEF3` | primary text, "SILK" wordmark |
| Steel (mid silver) | `#9AA1AD` | secondary text, rules |
| Magenta (Xotic accent) | `#E0218A` | accent, "XOTIC", links, the ribbon |
| Orchid (deep) | `#7A1B5B` | gradient anchor / shadows |

Signature gradient — **Silk → Magenta**: `#ECEEF3 → #E0218A` (the silk ribbon).

## Typography
- **Wordmark / display:** a smooth geometric sans (Poppins / Montserrat), heavy weight, wide tracking —
  reads as "silk." `XOTIC` set in the same face but in Magenta to mark the lineage.
- **Technical / uname / code:** a mono (JetBrains Mono / monospace) — for banners, version strings, sysfs.

## Logo
`silkxotic-logo.svg` — an **S-ribbon** emblem (silk curve, Silk→Magenta gradient on Ink tile) + the
`SILKXOTIC` wordmark with a thin silk-wave underline.
- Clear space: ≥ the height of the "S" on all sides. Min emblem size: 32 px.
- Don't: recolor the ribbon outside the Silk→Magenta gradient; stretch; put on busy backgrounds.

## Credits (always carry these)
- **Tuning DNA:** BruthXotic / *Tobrut Exotic* — **Morat Engine**, by **@MasMasBertelur**.
- **Base:** crDroid 16 (`android_kernel_xiaomi_sm6150`, branch `16.0`).
- **Refined / built by:** **nawka12** (GitHub) · *kayfahaarukku*. *(swap this handle as you like.)*

## Voice
Confident, lean, a little cheeky about the "brutal → silk" glow-up. Never overclaims —
"smoother and clean," not "200% faster."
