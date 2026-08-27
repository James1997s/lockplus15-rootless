from pathlib import Path
import json, shutil

root = Path('/home/ubuntu/lockplus15-rootless')
themes = root / 'themes'
folder = themes / 'folder-themes' / 'geometric-twenty-four'
manifest = themes / 'geometric-twenty-four.json'
if folder.exists():
    shutil.rmtree(folder)
if manifest.exists():
    manifest.unlink()
catalog_path = themes / 'catalog.json'
catalog = json.loads(catalog_path.read_text())
catalog['themes'] = [item for item in catalog.get('themes', []) if item.get('id') != 'geometric-twenty-four']
catalog_path.write_text(json.dumps(catalog, indent=2) + '\n')
print('reset geometric-twenty-four')
