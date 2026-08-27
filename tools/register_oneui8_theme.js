const fs = require('fs');
const path = 'themes/catalog.json';
const catalog = JSON.parse(fs.readFileSync(path, 'utf8'));
const exists = catalog.themes.some((theme) => theme.id === 'oneui8-adaptive-clock');
if (!exists) {
  catalog.themes.push({
    id: 'oneui8-adaptive-clock',
    name: 'One UI 8 Adaptive Clock',
    url: 'oneui8-adaptive-clock.json',
    format: 'folder'
  });
}
fs.writeFileSync(path, JSON.stringify(catalog, null, 2) + '\n');
