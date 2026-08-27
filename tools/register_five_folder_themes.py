import json
from pathlib import Path

catalog_path = Path('/home/ubuntu/lockplus15-rootless/themes/catalog.json')
data = json.loads(catalog_path.read_text())
existing = {item.get('id') for item in data.get('themes', [])}
entries = [
    ('aurora-glass', 'Aurora Glass'),
    ('ink-garden', 'Ink Garden'),
    ('desert-sun', 'Desert Sun'),
    ('ocean-night', 'Ocean Night'),
    ('neon-architecture', 'Neon Architecture'),
]
for theme_id, name in entries:
    if theme_id not in existing:
        data['themes'].append({'id': theme_id, 'name': name, 'url': theme_id + '.json', 'format': 'folder'})
catalog_path.write_text(json.dumps(data, indent=2) + '\n')
print('registered', ', '.join(theme_id for theme_id, _ in entries))
