from pathlib import Path
import json
import re

ROOT = Path('/home/ubuntu/lockplus15-rootless')
THEMES = ROOT / 'themes'
FOLDERS = THEMES / 'folder-themes'
CATALOG = THEMES / 'catalog.json'

families = [
    ('Japanese', 'japanese', 12, ['Shoji Dawn','Koi Current','Tokyo Rain','Sakura Signal','Zen Ink','Lantern Night','Bamboo Mist','Neon Torii','Origami Sky','Wabi Moon','Fuji Quiet','Kitsune Glow']),
    ('Futuristic', 'future', 12, ['Orbit Glass','Quantum Grid','Chrome Horizon','Solar Console','Deep Space UI','Ion Drift','Lunar Terminal','Prism Reactor','Astro Bloom','Vector Dawn','Holo District','Nova Dial']),
    ('Comic-inspired', 'comic', 10, ['Pop Panel','Ink Burst','Rocket Panel','Hero Halftone','Midnight Pulp','Cosmic Speech','Action Lines','Retro Panels','Electric Zine','Sunday Strip']),
    ('Original fairytale', 'fairytale', 8, ['Storybook Castle','Moonlit Carousel','Wonder Garden','Paper Crown','Midnight Parade','Glass Slipper','Cloud Kingdom','Enchanted Lantern']),
    ('Tattoo', 'tattoo', 8, ['Blackwork Rose','Sailor Swallow','Serpent Line','Lucky Tiger','Sacred Heart','Floral Flash','Old School Dice','Moon Moth']),
    ('Neon', 'neon', 10, ['Neon Alley','Vapor Bloom','Laser Rain','Electric Motel','Cyan Circuit','Pink Voltage','Ultraviolet Club','Digital Sunset','Neon Arcade','Light Leak']),
    ('Colour clocks', 'colour', 10, ['Colour Stack','Candy Time','Spectrum Split','Primary Pulse','Pastel Blocks','Tangerine Tick','Aqua Marker','Lemon Dial','Coral Minute','Prism Clock']),
    ('Dinosaur', 'dinosaur', 8, ['Raptor Run','Jurassic Fern','Fossil Lab','Cretaceous Dawn','Dino Tracks','Amber Bone','Volcanic Rex','Tiny Triceratops']),
    ('Game-inspired', 'game', 10, ['Pixel Quest','Dungeon Map','Sky Runner','Mecha Pilot','Puzzle Field','Boss Room','Star Pilot','Racing HUD','Quest Log','Arcade Quest']),
    ('Game Boy', 'gameboy', 6, ['Pocket Green','Four Shade Quest','Mono Sprite','Handheld Dawn','Cartridge City','Dot Matrix']),
    ('Virtual pet', 'pet', 6, ['Pocket Pet','Care Cycle','Happy Egg','Tiny Friend','Pet Garden','Digital Hatch']),
]

palettes = {
    'japanese': ('#f8efe0','#243443','#d65d70','#3a9ea5','"Hiragino Mincho ProN", "Yu Mincho", Georgia, serif'),
    'future': ('#07111f','#e8f4ff','#70e1ff','#b38cff','"Avenir Next", "Helvetica Neue", sans-serif'),
    'comic': ('#ffe55c','#171717','#ef4056','#137dff','Impact, "Arial Black", sans-serif'),
    'fairytale': ('#171126','#fff5da','#ef9bc6','#9acbff','Georgia, "Times New Roman", serif'),
    'tattoo': ('#eee7dc','#191919','#ba3d43','#3d6b62','"Courier New", monospace'),
    'neon': ('#090718','#f7f2ff','#ff46c8','#42f5ff','"Avenir Next", "Helvetica Neue", sans-serif'),
    'colour': ('#f6f1e8','#1b2330','#ff6b5d','#4f84ff','"Avenir Next", "Helvetica Neue", sans-serif'),
    'dinosaur': ('#173329','#f7f0cf','#f08b45','#88bd58','"Trebuchet MS", sans-serif'),
    'game': ('#111827','#eff6ff','#70e0ff','#f59e0b','"Arial Black", sans-serif'),
    'gameboy': ('#9bbc0f','#0f380f','#306230','#071d07','"Courier New", monospace'),
    'pet': ('#d9f7f2','#163b4a','#ff769c','#8b7cff','"Trebuchet MS", sans-serif'),
}

def safe(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')

def html(title, family):
    return f'''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><meta name="theme-color" content="{palettes[family][0]}"><link rel="stylesheet" href="style.css"></head><body><main class="lock"><section class="top"><div class="eyebrow">{family.upper()} / SPECIALLOCK</div><div class="clock" id="clock">00:00</div><div class="word" id="word">MIDNIGHT</div><div class="date" id="date">LOADING DATE</div><div class="weather" id="weather">WALSALL · WEATHER…</div></section><section class="art"><div class="shape s1"></div><div class="shape s2"></div><div class="shape s3"></div><div class="grain"></div><div class="caption">{title.upper()}</div></section></main><script src="script.js"></script></body></html>'''

def css(title, family):
    bg, fg, a, b, font = palettes[family]
    return f''':root{{--bg:{bg};--fg:{fg};--a:{a};--b:{b};--font:{font}}}*{{box-sizing:border-box}}html,body{{margin:0;width:100%;height:100%;overflow:hidden;background:var(--bg);color:var(--fg);font-family:var(--font)}}body{{-webkit-font-smoothing:antialiased}}.lock{{position:fixed;inset:0;display:flex;flex-direction:column;background:radial-gradient(circle at 70% 30%,color-mix(in srgb,var(--b) 25%,transparent),transparent 42%),var(--bg)}}.top{{position:relative;z-index:4;padding:28px 28px 16px;min-height:205px;display:grid;grid-template-columns:1fr auto;grid-template-rows:auto auto auto auto;column-gap:16px;align-content:start}}.eyebrow{{grid-column:1/-1;font-size:10px;letter-spacing:.2em;opacity:.68;margin-bottom:8px}}.clock{{font-size:clamp(42px,15vw,74px);line-height:.9;font-weight:800;letter-spacing:-.07em;text-shadow:0 5px 22px color-mix(in srgb,var(--a) 35%,transparent)}}.word{{font-size:clamp(12px,4vw,19px);font-weight:700;letter-spacing:.18em;align-self:end;color:var(--a)}}.date{{font-size:12px;letter-spacing:.1em;opacity:.82;margin-top:14px}}.weather{{font-size:10px;letter-spacing:.12em;opacity:.64;margin-top:7px}}.art{{position:relative;flex:1;overflow:hidden;background:linear-gradient(145deg,color-mix(in srgb,var(--a) 22%,var(--bg)),var(--bg) 55%,color-mix(in srgb,var(--b) 18%,var(--bg)))}}.shape{{position:absolute;filter:drop-shadow(0 20px 30px rgba(0,0,0,.22));mix-blend-mode:screen;animation:float 9s ease-in-out infinite}}.s1{{width:64vw;height:64vw;max-width:340px;max-height:340px;left:7%;top:18%;background:linear-gradient(135deg,var(--a),transparent 68%);clip-path:polygon(50% 0,100% 28%,78% 100%,12% 78%,0 28%)}}.s2{{width:72vw;height:72vw;max-width:380px;max-height:380px;right:-12%;top:35%;background:linear-gradient(35deg,var(--b),transparent 65%);clip-path:polygon(0 15%,73% 0,100% 57%,52% 100%,8% 72%);animation-delay:-3s}}.s3{{width:42vw;height:42vw;max-width:230px;max-height:230px;left:34%;top:48%;border:2px solid color-mix(in srgb,var(--fg) 28%,transparent);transform:rotate(24deg);animation-delay:-6s}}.grain{{position:absolute;inset:0;opacity:.12;background-image:radial-gradient(color-mix(in srgb,var(--fg) 50%,transparent) .7px,transparent .7px);background-size:5px 5px;pointer-events:none}}.caption{{position:absolute;left:28px;bottom:26px;font-size:11px;letter-spacing:.22em;opacity:.7}}@keyframes float{{0%,100%{{transform:translate3d(0,0,0) rotate(0deg)}}50%{{transform:translate3d(0,-14px,0) rotate(4deg)}}}}@media(prefers-reduced-motion:reduce){{.shape{{animation:none}}}}'''

def js():
    return '''(() => { const words=['TWELVE','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','TEN','ELEVEN']; const pad=n=>String(n).padStart(2,'0'); const ordinal=n=>{const s=['TH','ST','ND','RD'];const v=n%100;return `${n}${s[(v-20)%10]||s[v]||s[0]}`}; function tick(){const d=new Date();const h=d.getHours(),m=d.getMinutes();document.getElementById('clock').textContent=`${pad(h)}:${pad(m)}`;document.getElementById('word').textContent=`${words[h%12]} ${words[Math.floor(m/5)%12]}`;document.getElementById('date').textContent=d.toLocaleDateString('en-GB',{weekday:'long',month:'long'}).toUpperCase()+` THE ${ordinal(d.getDate())}`;} async function weather(){try{const r=await fetch('https://api.open-meteo.com/v1/forecast?latitude=52.5862&longitude=-1.9829&current=temperature_2m,weather_code&timezone=Europe%2FLondon');const j=await r.json();const t=Math.round(j.current.temperature_2m);document.getElementById('weather').textContent=`WALSALL · ${t}°C · LIVE WEATHER`;}catch(e){document.getElementById('weather').textContent='WALSALL · WEATHER UNAVAILABLE';}} tick();weather();setInterval(tick,1000);setInterval(weather,900000);})();'''

new = []
for category, family, count, names in families:
    for i, title in enumerate(names, 1):
        tid = safe(f'{family}-{i:02d}-{title}')
        folder = FOLDERS / tid
        folder.mkdir(parents=True, exist_ok=True)
        (folder/'LockBackground.html').write_text(html(title, family), encoding='utf-8')
        (folder/'style.css').write_text(css(title, family), encoding='utf-8')
        (folder/'script.js').write_text(js(), encoding='utf-8')
        new.append({'id':tid,'name':title,'description':f'{category} original HTML lock screen with animated artwork, live clock, Walsall weather, and a custom {family} type treatment.','format':'folder','url':f'{tid}.json'})

existing = json.loads(CATALOG.read_text(encoding='utf-8')) if CATALOG.exists() else {'version':1,'themes':[]}
existing_ids = {x.get('id') for x in existing.get('themes',[])}
existing['themes'] = [x for x in existing.get('themes',[]) if x.get('id') not in {n['id'] for n in new}] + new
CATALOG.write_text(json.dumps(existing, indent=2) + '\n', encoding='utf-8')
for n in new:
    manifest = {'id': n['id'], 'name': n['name'], 'version':'1.0.0', 'format':'folder', 'basePath':f'folder-themes/{n["id"]}', 'entry':'LockBackground.html', 'files':[]}
    for name in ['LockBackground.html','script.js','style.css']:
        import hashlib
        data=(FOLDERS/n['id']/name).read_bytes()
        manifest['files'].append({'path':name,'sha256':hashlib.sha256(data).hexdigest()})
    (THEMES/f'{n["id"]}.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
print(f'generated {len(new)} new themes; catalog now has {len(existing["themes"])} entries')
