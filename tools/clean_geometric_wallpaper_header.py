from PIL import Image, ImageDraw
from pathlib import Path
import random

src = Path('/home/ubuntu/upload/IMG_0280.jpeg')
out = Path('/home/ubuntu/lockplus15-rootless/themes/folder-themes/geometric-twenty-four/wallpaper.jpg')
image = Image.open(src).convert('RGB').crop((68, 22, 568, 911)).resize((750, 1334), Image.Resampling.LANCZOS)
width, height = image.size
pixels = image.load()
rng = random.Random(2408)
header_end = 330
for y in range(header_end):
    # Match the dark lock-screen tone and fade cleanly into the untouched artwork.
    fade = max(0.0, min(1.0, (y - 245) / 85.0))
    base = (7, 8, 17)
    for x in range(width):
        texture = rng.choice((-2, -1, 0, 0, 0, 1, 2))
        original = pixels[x, y]
        if fade < 1.0:
            target = tuple(max(0, min(255, base[i] + texture)) for i in range(3))
            pixels[x, y] = tuple(int(target[i] * (1.0 - fade) + original[i] * fade) for i in range(3))
        else:
            pixels[x, y] = tuple(max(0, min(255, base[i] + texture)) for i in range(3))
image.save(out, 'JPEG', quality=94, optimize=True, progressive=True)
print(out, image.size, out.stat().st_size)
