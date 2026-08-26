#!/usr/bin/env python3
"""Build a compact, bounded GIF from a 3×4 sprite sheet.

The source sheet is divided evenly row-major into twelve cells. Each cell is
resized without cropping to retain the complete supplied drawing frame.
"""
from pathlib import Path
import sys
from PIL import Image


FRAME_COLUMNS = 4
FRAME_ROWS = 3
FRAME_SIZE = (72, 52)
FRAME_DURATION_MS = 160
MAX_COLORS = 64


def main(source_path: str, output_path: str) -> None:
    source = Image.open(source_path).convert("RGBA")
    source_width, source_height = source.size
    frames = []

    for row in range(FRAME_ROWS):
        top = round(row * source_height / FRAME_ROWS)
        bottom = round((row + 1) * source_height / FRAME_ROWS)
        for column in range(FRAME_COLUMNS):
            left = round(column * source_width / FRAME_COLUMNS)
            right = round((column + 1) * source_width / FRAME_COLUMNS)
            cell = source.crop((left, top, right, bottom))
            frame = cell.resize(FRAME_SIZE, Image.Resampling.LANCZOS).convert("L")
            frames.append(frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=MAX_COLORS, dither=Image.Dither.NONE))

    destination = Path(output_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        destination,
        save_all=True,
        append_images=frames[1:],
        loop=0,
        duration=FRAME_DURATION_MS,
        optimize=True,
        disposal=2,
    )

    print(f"built {destination} ({FRAME_SIZE[0]}x{FRAME_SIZE[1]}, {len(frames)} frames)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} SOURCE_SHEET OUTPUT_GIF")
    main(sys.argv[1], sys.argv[2])
