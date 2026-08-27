const fs = require('fs');
const path = 'themes/catalog.json';
const catalog = JSON.parse(fs.readFileSync(path, 'utf8'));
if (!catalog.themes.some((theme) => theme.id === 'ios26-big-clock')) {
  catalog.themes.push({
    id: 'ios26-big-clock',
    name: 'iOS 26 Big Glass Clock',
    url: 'ios26-big-clock.json',
    format: 'folder'
  });
}
fs.writeFileSync(path, JSON.stringify(catalog, null, 2) + '\n');
