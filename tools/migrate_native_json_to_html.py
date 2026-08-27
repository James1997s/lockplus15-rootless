from pathlib import Path
import hashlib, json, html, shutil, re

ROOT = Path('/home/ubuntu/lockplus15-rootless')
THEMES = ROOT / 'themes'
FOLDERS = THEMES / 'folder-themes'

SKIP = {'catalog.json'}

def css_value(v, default=''):
    if not isinstance(v, str): return default
    if len(v) > 160 or any(x in v.lower() for x in ('javascript:', 'url(', 'expression(', ';')):
        return default
    return v

def safe_id(v):
    return isinstance(v, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,48}', v or '') is not None

def asset_source(url):
    if not isinstance(url, str): return None
    p = Path(url)
    candidate = ROOT / 'themes' / p
    return candidate if candidate.is_file() else None

def element_style(props):
    allowed = ['position','left','right','top','bottom','width','height','transform','color','font-family','font-size','font-weight','letter-spacing','text-shadow','opacity','border-radius','background','background-color','z-index','padding','box-shadow','text-align']
    out=[]
    for key in allowed:
        val=css_value(props.get(key))
        if val: out.append(f'{key}:{val}')
    return ';'.join(out)

def build_theme(src):
    theme=json.loads(src.read_text())
    theme_id=theme.get('id') or src.stem
    if not safe_id(theme_id) or theme.get('format') == 'folder': return False
    dest=FOLDERS/theme_id
    if dest.exists(): shutil.rmtree(dest)
    dest.mkdir(parents=True)
    copied=[]
    asset_map={}
    for asset in theme.get('assets', []):
        aid=asset.get('id'); source=asset_source(asset.get('url'))
        if safe_id(aid) and source:
            filename=source.name
            shutil.copy2(source, dest/filename)
            asset_map[aid]=filename
            copied.append(filename)
    elements=theme.get('placedElements', {})
    body=[]
    for eid, props in sorted(elements.items(), key=lambda kv: int(str(kv[1].get('z-index','0')).split('.')[0]) if str(kv[1].get('z-index','0')).lstrip('-').isdigit() else 0):
        if not isinstance(props, dict): continue
        typ=props.get('type','text'); style=element_style(props); aid=props.get('asset-id')
        if typ in ('wallpaper','image') and aid in asset_map:
            body.append(f'<img id="{html.escape(eid)}" class="theme-element" src="{html.escape(asset_map[aid])}" style="{style}">')
        elif typ == 'wallpaper':
            gradient=str(props.get('gradient',' #101820|#243447')).strip().split('|')
            c1=css_value(gradient[0], '#101820'); c2=css_value(gradient[-1], '#243447')
            body.append(f'<div id="{html.escape(eid)}" class="theme-element wallpaper" style="{style};background:linear-gradient(145deg,{c1},{c2})"></div>')
        elif typ in ('clock','date','word-clock','ecg-time','brushstroke-time','battery'):
            token={'clock':'clock','date':'date','word-clock':'word-clock','ecg-time':'pulse','brushstroke-time':'brushstroke','battery':'battery'}[typ]
            body.append(f'<div id="{html.escape(eid)}" class="theme-element dynamic {token}" style="{style}"></div>')
        elif typ in ('text','html'):
            content=props.get('innerHTML','')
            if '<' in content:
                content=re.sub(r'<(?!/?(?:span|b|i|strong|em)\b)[^>]*>', '', content, flags=re.I)
            body.append(f'<div id="{html.escape(eid)}" class="theme-element" style="{style}">{content}</div>')
        elif typ in ('panel','blob','particle','ring','widget','overlay'):
            body.append(f'<div id="{html.escape(eid)}" class="theme-element" style="{style}"></div>')
    if not body: body.append('<div id="clock" class="theme-element dynamic clock"></div>')
    html_doc='''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><link rel="stylesheet" href="style.css"></head><body><main id="theme-root">%s</main><script src="script.js"></script></body></html>''' % ''.join(body)
    (dest/'LockBackground.html').write_text(html_doc)
    (dest/'style.css').write_text('''html,body,#theme-root{margin:0;width:100%%;height:100%%;overflow:hidden;background:#101820;color:white;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}#theme-root{position:relative;width:375px;height:667px;transform-origin:top left}.theme-element{position:absolute;box-sizing:border-box}.wallpaper{inset:0!important;z-index:-100!important}.theme-element img{object-fit:cover}.dynamic{display:flex;align-items:center;justify-content:center;white-space:pre-line;text-align:center}.dynamic.clock{font-variant-numeric:tabular-nums}.dynamic.word-clock{white-space:pre-line}.dynamic.pulse{border:2px solid currentColor;border-radius:24px}.dynamic.brushstroke{font-family:cursive;font-weight:700}.dynamic.battery{font-weight:700}img.theme-element{object-fit:cover}'''.replace('%%','%'))
    (dest/'script.js').write_text('''(()=>{const pad=n=>String(n).padStart(2,'0');const words=['TWELVE','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','TEN','ELEVEN'];function tick(){const d=new Date(),h=d.getHours(),m=d.getMinutes();document.querySelectorAll('.clock').forEach(e=>e.textContent=`${pad(h)}:${pad(m)}`);document.querySelectorAll('.date').forEach(e=>e.textContent=d.toLocaleDateString(undefined,{weekday:'long',month:'long',day:'numeric'}));document.querySelectorAll('.word-clock').forEach(e=>e.textContent=`${words[h%12]}\\n${m?pad(m):'O\'CLOCK'}`);document.querySelectorAll('.battery').forEach(e=>e.textContent='');}tick();setInterval(tick,1000)})();''')
    files=[]
    for f in sorted(dest.iterdir()):
        if f.is_file(): files.append({'path':f.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
    manifest={'id':theme_id,'name':theme.get('name',theme_id),'version':theme.get('version','1.0.0'),'format':'folder','basePath':f'folder-themes/{theme_id}','entry':'LockBackground.html','files':files}
    src.write_text(json.dumps(manifest, indent=2)+'\n')
    return True

changed=[]
for src in sorted(THEMES.glob('*.json')):
    if src.name in SKIP: continue
    if build_theme(src): changed.append(src.stem)

catalog=json.loads((THEMES/'catalog.json').read_text())
for record in catalog.get('themes',[]):
    manifest_path = THEMES / (str(record.get('url','')))
    manifest = json.loads(manifest_path.read_text()) if manifest_path.is_file() else {}
    if manifest.get('format') == 'folder': record['format']='folder'
(THEMES/'catalog.json').write_text(json.dumps(catalog, indent=2)+'\n')
print('migrated:', ', '.join(changed))
