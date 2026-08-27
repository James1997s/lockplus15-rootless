from pathlib import Path
import hashlib
import json
import sys

folder = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2]).resolve()
theme_id = folder.name
files = []
for path in sorted(folder.rglob('*')):
    if path.is_file():
        relative = path.relative_to(folder).as_posix()
        files.append({'path': relative, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
manifest = {
    'id': theme_id,
    'name': 'iOS 26 Big Glass Clock',
    'version': '1.0.0',
    'format': 'folder',
    'basePath': f'folder-themes/{theme_id}',
    'entry': 'LockBackground.html',
    'files': files,
}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(f'Wrote {manifest_path} with {len(files)} files')
