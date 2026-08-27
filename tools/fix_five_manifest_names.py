import json
from pathlib import Path

root = Path('/home/ubuntu/lockplus15-rootless/themes')
names = {
    'aurora-glass': 'Aurora Glass',
    'ink-garden': 'Ink Garden',
    'desert-sun': 'Desert Sun',
    'ocean-night': 'Ocean Night',
    'neon-architecture': 'Neon Architecture',
}
for theme_id, name in names.items():
    path = root / f'{theme_id}.json'
    data = json.loads(path.read_text())
    data['name'] = name
    path.write_text(json.dumps(data, indent=2) + '\n')
    print(theme_id, name)
