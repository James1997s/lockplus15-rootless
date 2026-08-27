from pathlib import Path
import json, shutil

root = Path('/home/ubuntu/lockplus15-rootless')
themes = root / 'themes'
converted = {
    'white-word-wheel',
    'framed-parking',
    'move-the-image',
    'animated-art-gallery',
    'pulse-timeline',
    'brushstroke-time',
    'planet-globe-animated-gif',
    'cookie-monster-lock',
    'cat-hat-side-clock',
}
for theme_id in sorted(converted):
    folder = themes / 'folder-themes' / theme_id
    if folder.exists():
        shutil.rmtree(folder)
    for manifest in themes.glob('*.json'):
        try:
            data = json.loads(manifest.read_text())
        except Exception:
            continue
        if data.get('id') == theme_id:
            manifest.unlink()
            break
catalog_path = themes / 'catalog.json'
catalog = json.loads(catalog_path.read_text())
catalog['themes'] = [item for item in catalog.get('themes', []) if item.get('id') not in converted]
catalog_path.write_text(json.dumps(catalog, indent=2) + '\n')
print('removed:', ', '.join(sorted(converted)))
print('remaining:', ', '.join(item.get('id','') for item in catalog['themes']))
