from pathlib import Path
import hashlib, json

root = Path('/home/ubuntu/lockplus15-rootless/themes')
for manifest_path in sorted(root.glob('*.json')):
    if manifest_path.name == 'catalog.json':
        continue
    manifest = json.loads(manifest_path.read_text())
    if manifest.get('format') != 'folder':
        continue
    theme_id = manifest.get('id')
    folder = root / 'folder-themes' / theme_id
    files = []
    for item in sorted(folder.iterdir()):
        if item.is_file():
            files.append({'path': item.name, 'sha256': hashlib.sha256(item.read_bytes()).hexdigest()})
    manifest['files'] = files
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    print('refreshed', theme_id)
