from PIL import Image
from pathlib import Path

src = Path('/home/ubuntu/upload/IMG_0280.jpeg')
out = Path('/home/ubuntu/lockplus15-rootless/themes/folder-themes/geometric-twenty-four/wallpaper.jpg')
out.parent.mkdir(parents=True, exist_ok=True)
image = Image.open(src).convert('RGB')
# Remove the screenshot status bar, Reddit chrome, and white side margins.
crop = image.crop((68, 22, 568, 911))
crop = crop.resize((750, 1334), Image.Resampling.LANCZOS)
crop.save(out, 'JPEG', quality=94, optimize=True, progressive=True)
print(out, crop.size, out.stat().st_size)
