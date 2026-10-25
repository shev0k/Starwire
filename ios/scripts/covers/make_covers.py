"""Cover art for the Vibeshine test apps the iOS device runs use.

Writes one 600x800 SVG per app (the size of Vibeshine's own covers) in Starwire's look: the
night sky with violet nebulae and stars from the app's starfield, the rainbow from the wordmark,
and a picture of what the app shows. install-covers.ps1 turns them into PNGs with headless
Chrome and points the apps' image-path at them.

The stars come from a fixed seed, so the same SVGs come out every time:
    python3 ios/scripts/covers/make_covers.py <output folder>
"""

import random
import sys
from pathlib import Path

WIDTH, HEIGHT = 600, 800
# Starwire's colours: the rainbow (RainbowPalette.stops) and the stars (StarfieldModel.starColours)
RAINBOW = ["#0894FF", "#C959DD", "#FF2E54", "#FF9004"]
STAR_COLOURS = ["#FFFFFF", "#E9D5FF", "#BFDBFE", "#FDE68A"]
SEED = 0x7015

COVERS = {
    "starwire-test-pattern": "Starwire test pattern",
    "starwire-colour-bars": "Starwire colour bars",
    "starwire-gamepad-tester": "Starwire gamepad tester",
    "starwire-input-latency": "Starwire input latency",
}


def sky(seed: int) -> str:
    """The background: dark sky, the starfield's three nebulae, and seeded stars."""
    rng = random.Random(seed)
    stars = []
    for _ in range(90):
        x, y = rng.uniform(0, WIDTH), rng.uniform(0, HEIGHT)
        r = rng.choice([0.6, 0.8, 1.0, 1.2, 1.6])
        colour = rng.choice(STAR_COLOURS)
        opacity = rng.uniform(0.35, 0.95)
        stars.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{colour}" opacity="{opacity:.2f}"/>')
    return f"""
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0B0A1F"/><stop offset="1" stop-color="#05040D"/>
    </linearGradient>
    <radialGradient id="neb1"><stop offset="0" stop-color="#7C3AED" stop-opacity="0.45"/><stop offset="1" stop-color="#7C3AED" stop-opacity="0"/></radialGradient>
    <radialGradient id="neb2"><stop offset="0" stop-color="#C026D3" stop-opacity="0.32"/><stop offset="1" stop-color="#C026D3" stop-opacity="0"/></radialGradient>
    <radialGradient id="neb3"><stop offset="0" stop-color="#2563EB" stop-opacity="0.25"/><stop offset="1" stop-color="#2563EB" stop-opacity="0"/></radialGradient>
    <linearGradient id="rainbow" x1="0" y1="0" x2="1" y2="0">
      {''.join(f'<stop offset="{i / (len(RAINBOW) - 1):.3f}" stop-color="{c}"/>' for i, c in enumerate(RAINBOW))}
    </linearGradient>
  </defs>
  <rect width="{WIDTH}" height="{HEIGHT}" fill="url(#sky)"/>
  <circle cx="{0.12 * WIDTH}" cy="{0.18 * HEIGHT}" r="{0.55 * HEIGHT}" fill="url(#neb1)"/>
  <circle cx="{0.88 * WIDTH}" cy="{0.92 * HEIGHT}" r="{0.50 * HEIGHT}" fill="url(#neb2)"/>
  <circle cx="{0.30 * WIDTH}" cy="{0.75 * HEIGHT}" r="{0.40 * HEIGHT}" fill="url(#neb3)"/>
  {''.join(stars)}"""


def title(text: str) -> str:
    """The app's name at the bottom, over a rainbow rule, as the game screen's hero does."""
    words = text.split(" ", 1)
    return f"""
  <rect x="48" y="636" width="120" height="6" rx="3" fill="url(#rainbow)"/>
  <text x="48" y="690" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-weight="900" font-size="30"
        fill="#E9D5FF" letter-spacing="6">{words[0].upper()}</text>
  <text x="48" y="740" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-weight="800" font-size="44"
        fill="#FFFFFF">{words[1] if len(words) > 1 else ''}</text>"""


def ufo() -> str:
    """testufo.com's alien in its saucer, drawn again in Starwire's colours."""
    return """
  <g transform="translate(300 330)">
    <path d="M-70 40 L-150 260 L150 260 L70 40 Z" fill="#FDE68A" opacity="0.10"/>
    <ellipse cx="0" cy="-10" rx="78" ry="70" fill="#BFDBFE" opacity="0.22" stroke="#E9D5FF" stroke-width="3"/>
    <g fill="#4ADE80">
      <ellipse cx="0" cy="-12" rx="34" ry="40"/>
      <ellipse cx="-14" cy="-20" rx="11" ry="15" fill="#05040D"/>
      <ellipse cx="14" cy="-20" rx="11" ry="15" fill="#05040D"/>
      <circle cx="-11" cy="-25" r="4" fill="#FFFFFF"/>
      <circle cx="17" cy="-25" r="4" fill="#FFFFFF"/>
    </g>
    <ellipse cx="0" cy="38" rx="190" ry="52" fill="#7C3AED"/>
    <ellipse cx="0" cy="26" rx="190" ry="40" fill="#A78BFA"/>
    <ellipse cx="0" cy="22" rx="150" ry="22" fill="#C4B5FD"/>
    <g>
      <circle cx="-120" cy="44" r="10" fill="#0894FF"/>
      <circle cx="-60" cy="58" r="10" fill="#C959DD"/>
      <circle cx="0" cy="62" r="10" fill="#FF2E54"/>
      <circle cx="60" cy="58" r="10" fill="#FF9004"/>
      <circle cx="120" cy="44" r="10" fill="#0894FF"/>
    </g>
  </g>"""


def colour_bars() -> str:
    """SMPTE-style bars on a tilted card: the page the colour checks measure."""
    bars = ["#C0C0C0", "#C0C000", "#00C0C0", "#00C000", "#C000C0", "#C00000", "#0000C0"]
    width = 300 / len(bars)
    top = "".join(f'<rect x="{-150 + i * width:.2f}" y="-150" width="{width + 0.5:.2f}" height="200" fill="{c}"/>'
                  for i, c in enumerate(bars))
    lower = ["#0000C0", "#131313", "#C000C0", "#131313", "#00C0C0", "#131313", "#C0C0C0"]
    middle = "".join(f'<rect x="{-150 + i * width:.2f}" y="50" width="{width + 0.5:.2f}" height="28" fill="{c}"/>'
                     for i, c in enumerate(lower))
    ramp = "".join(f'<rect x="{-150 + i * 30}" y="78" width="30.5" height="72" fill="#{v:02X}{v:02X}{v:02X}"/>'
                   for i, v in enumerate(range(0, 256, 28)))
    return f"""
  <g transform="translate(300 330) rotate(-6)">
    <rect x="-166" y="-166" width="332" height="332" rx="22" fill="#0B0A1F" stroke="url(#rainbow)" stroke-width="6"/>
    <clipPath id="card"><rect x="-150" y="-150" width="300" height="300" rx="10"/></clipPath>
    <g clip-path="url(#card)">{top}{middle}{ramp}</g>
  </g>"""


def gamepad() -> str:
    """A controller with its buttons in the rainbow's colours."""
    return """
  <g transform="translate(300 340)">
    <path d="M-150 -70 C-200 -70 -230 -20 -238 60 C-246 140 -214 180 -180 180 C-150 180 -130 140 -100 110
             L100 110 C130 140 150 180 180 180 C214 180 246 140 238 60 C230 -20 200 -70 150 -70 Z"
          fill="#1E1B3A" stroke="#A78BFA" stroke-width="5"/>
    <g fill="#E9D5FF">
      <rect x="-172" y="-6" width="64" height="22" rx="5"/>
      <rect x="-151" y="-27" width="22" height="64" rx="5"/>
    </g>
    <circle cx="150" cy="-22" r="15" fill="#FF9004"/>
    <circle cx="182" cy="8" r="15" fill="#FF2E54"/>
    <circle cx="118" cy="8" r="15" fill="#0894FF"/>
    <circle cx="150" cy="38" r="15" fill="#C959DD"/>
    <circle cx="-62" cy="62" r="30" fill="#0B0A1F" stroke="#E9D5FF" stroke-width="4"/>
    <circle cx="62" cy="62" r="30" fill="#0B0A1F" stroke="#E9D5FF" stroke-width="4"/>
    <circle cx="-62" cy="62" r="12" fill="#A78BFA"/>
    <circle cx="62" cy="62" r="12" fill="#A78BFA"/>
    <rect x="-34" y="-16" width="24" height="10" rx="5" fill="#BFDBFE"/>
    <rect x="10" y="-16" width="24" height="10" rx="5" fill="#BFDBFE"/>
    <rect x="-150" y="-100" width="80" height="20" rx="10" fill="#7C3AED"/>
    <rect x="70" y="-100" width="80" height="20" rx="10" fill="#7C3AED"/>
  </g>"""


def latency() -> str:
    """The input latency page: the two squares that flip, over a list being scrolled."""
    rows = "".join(f'<rect x="-150" y="{-60 + i * 44}" width="300" height="34" rx="8" fill="#1E1B3A" opacity="{0.9 - i * 0.12:.2f}"/>'
                   for i in range(6))
    return f"""
  <g transform="translate(300 320)">
    <rect x="-166" y="-166" width="332" height="332" rx="22" fill="#0B0A1F" stroke="url(#rainbow)" stroke-width="6"/>
    <rect x="-150" y="-150" width="70" height="70" rx="8" fill="#FFFFFF"/>
    <rect x="-70" y="-150" width="70" height="70" rx="8" fill="#05040D" stroke="#E9D5FF" stroke-width="3"/>
    <path d="M40 -140 L40 -90 M25 -105 L40 -88 L55 -105" stroke="#FDE68A" stroke-width="6" fill="none" stroke-linecap="round"/>
    {rows}
    <path d="M110 -60 L110 150" stroke="#A78BFA" stroke-width="6" stroke-linecap="round" opacity="0.6"/>
  </g>"""


ART = {
    "starwire-test-pattern": ufo,
    "starwire-colour-bars": colour_bars,
    "starwire-gamepad-tester": gamepad,
    "starwire-input-latency": latency,
}


def cover(name: str) -> str:
    """The SVG for one cover, by file name (without .svg)."""
    seed = SEED + sorted(COVERS).index(name)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
            f'viewBox="0 0 {WIDTH} {HEIGHT}">{sky(seed)}{ART[name]()}{title(COVERS[name])}\n</svg>\n')


def main(folder: str) -> None:
    out = Path(folder)
    out.mkdir(parents=True, exist_ok=True)
    for name in COVERS:
        (out / f"{name}.svg").write_text(cover(name), encoding="utf-8")
        print(out / f"{name}.svg")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
