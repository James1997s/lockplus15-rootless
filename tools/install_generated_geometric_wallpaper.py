from PIL import Image
from pathlib import Path

src = Path('/home/ubuntu/lockplus15-rootless/themes/folder-themes/geometric-twenty-four/wallpaper_clean.jpg.jpeg.png')
out = Path('/home/ubuntu/lockplus15-rootless/themes/folder-themes/geometric-twenty-four/wallpaper.jpg')
image = Image.open(src).convert('RGB')
# Remove the generated/reference framing margins while preserving the full central composition.
left, top, right, bottom = 72, 0, image.width - 72, image.height
image = image.crop((left, top, right, bottom)).resize((750, 1334), Image.Resampling.LANCZOS)
image.save(out, 'JPEG', quality=94, optimize=True, progressive=True)
print(out, image.size, out.stat().st_size)
