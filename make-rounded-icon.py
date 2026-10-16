#!/usr/bin/env python3
"""Install the start-menu (desktop entry) icon and assets.

The source is center-cropped to a square so no aspect-ratio distortion occurs,
and the full square is kept (no corner rounding). The original image file is
never modified.

Writes the icon set to ~/.local/share/icons/hicolor AND, when run with sudo,
a copy to /usr/share/pixmaps/nginix-control-panel.png (used by the .desktop file
and the native window icon).
"""

import argparse
import os
import shutil
import sys

from PIL import Image

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(SCRIPTS_DIR, "icon_1024.png")
ICON_DIR = os.path.expanduser("~/.local/share/icons/hicolor")
PIXMAP_PATH = "/usr/share/pixmaps/nginix-control-panel.png"
SIZES = [16, 32, 48, 64, 128, 256, 512]


def center_crop_square(img):
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    return img.crop((left, top, left + side, top + side))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--icon-dir",
        default=ICON_DIR,
        help="Override the base hicolor directory (used by package builds)",
    )
    args = ap.parse_args()
    icon_dir = args.icon_dir or ICON_DIR

    img = Image.open(SRC).convert("RGBA")
    img = center_crop_square(img)
    for size in SIZES:
        icon = img.resize((size, size), Image.LANCZOS)
        path = os.path.join(icon_dir, f"{size}x{size}", "apps", "nginix-control-panel.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        icon.save(path)
        print(f"wrote {path} ({size}x{size})")

    if icon_dir == ICON_DIR and sys.platform.startswith("linux") and os.geteuid() == 0:
        os.makedirs("/usr/share/pixmaps", exist_ok=True)
        shutil.copy2(SRC, PIXMAP_PATH)
        print(f"wrote {PIXMAP_PATH} (unmodified copy)")
    elif icon_dir == ICON_DIR:
        print(f"\n[note] Run with sudo to also install {PIXMAP_PATH}")


if __name__ == "__main__":
    main()