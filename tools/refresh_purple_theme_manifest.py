from pathlib import Path
import json, hashlib
root=Path('/home/ubuntu/lockplus15-rootless/themes/folder-themes/purple-anime-stack-clock')
manifest_path=root/'purple-anime-stack-clock.json'
manifest=json.loads(manifest_path.read_text())
manifest['files']=[{'path':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(root.iterdir()) if p.is_file() and p.name!='purple-anime-stack-clock.json']
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
print('manifest_refreshed', manifest['files'])
