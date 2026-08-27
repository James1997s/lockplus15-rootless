from pathlib import Path
import hashlib, json

root = Path('/home/ubuntu/lockplus15-rootless')
themes = root / 'themes'
folder = themes / 'folder-themes' / 'geometric-twenty-four'
folder.mkdir(parents=True, exist_ok=True)

(folder / 'LockBackground.html').write_text('''<!doctype html>
<html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><link rel="stylesheet" href="style.css"></head>
<body><main id="theme-root">
<img class="wallpaper" src="wallpaper.jpg" alt="">
<div class="top-surface"></div>
<section class="header" aria-label="Time and date">
  <div id="word-time" class="word-time">EIGHT FIFTY EIGHT</div>
  <div class="rule"></div>
  <div class="meta cyan"><span class="dot"></span><span id="weekday">SATURDAY</span></div>
  <div class="meta pink"><span class="dot"></span><span id="month-day">MAY THE 2ND</span></div>
  <div class="toggle"><span></span></div>
  <div id="twenty-four" class="twenty-four">Twenty-four</div>
</section>
</main><script src="script.js"></script></body></html>''')

(folder / 'style.css').write_text('''
html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#080a13;color:#e9e9ee;-webkit-font-smoothing:antialiased}#theme-root{position:relative;width:375px;height:667px;overflow:hidden;background:#080a13;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}.wallpaper{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:center;filter:brightness(.84) contrast(1.04) saturate(1.04)}.top-surface{position:absolute;left:0;top:0;width:100%;height:205px;background:linear-gradient(180deg,rgba(6,8,17,.97) 0%,rgba(6,8,17,.92) 74%,rgba(6,8,17,.58) 100%);z-index:1}.header{position:absolute;left:58px;top:42px;width:285px;z-index:2;color:#e8e7e9}.word-time{font-family:"Arial Narrow",Impact,sans-serif;font-size:24px;font-weight:800;letter-spacing:-.04em;line-height:1;text-transform:uppercase;text-shadow:0 2px 8px rgba(0,0,0,.4)}.rule{height:2px;margin-top:9px;background:rgba(227,208,215,.82);box-shadow:0 0 3px rgba(255,255,255,.1)}.meta{display:flex;align-items:center;height:27px;margin-top:6px;font-family:"Arial Narrow",sans-serif;font-size:15px;font-weight:800;letter-spacing:.02em}.meta .dot{width:17px;height:17px;margin-right:12px;border-radius:50%;background:#20bdc9;box-shadow:0 0 12px rgba(32,189,201,.18)}.meta.pink .dot{background:#c85772;box-shadow:0 0 12px rgba(200,87,114,.18)}.toggle{position:relative;width:48px;height:25px;margin-top:5px;border-radius:16px;background:#23b8c2;box-shadow:0 3px 12px rgba(0,0,0,.25)}.toggle span{position:absolute;right:1px;top:1px;width:23px;height:23px;border-radius:50%;background:#f8f8f7;box-shadow:0 1px 4px rgba(0,0,0,.35)}.twenty-four{margin-top:13px;margin-left:3px;font-size:12px;color:rgba(222,222,229,.72);letter-spacing:.01em}.header:after{content:"";position:absolute;left:-8px;right:0;bottom:-13px;height:1px;background:linear-gradient(90deg,rgba(255,255,255,.13),transparent)}
''')

(folder / 'script.js').write_text('''(()=>{const words=['TWELVE','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','TEN','ELEVEN'];const ord=n=>{const s=['TH','ST','ND','RD'],v=n%100;return n+(s[(v-20)%10]||s[v]||s[0])};function render(){const d=new Date(),h=d.getHours(),m=d.getMinutes(),month=d.toLocaleDateString(undefined,{month:'long'}).toUpperCase();document.getElementById('word-time').textContent=`${words[h%12]} ${m===0?'O\'CLOCK':words[Math.round(m/5)%12]}`;document.getElementById('weekday').textContent=d.toLocaleDateString(undefined,{weekday:'long'}).toUpperCase();document.getElementById('month-day').textContent=`${month} THE ${ord(d.getDate()).toUpperCase()}`;document.getElementById('twenty-four').textContent=h<12?'Twenty-four':'Twenty-four';}render();setInterval(render,1000)})();''')

files=[]
for f in sorted(folder.iterdir()):
    if f.is_file(): files.append({'path':f.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
manifest={'id':'geometric-twenty-four','name':'Geometric Twenty-Four','version':'1.0.0','format':'folder','basePath':'folder-themes/geometric-twenty-four','entry':'LockBackground.html','files':files}
(themes/'geometric-twenty-four.json').write_text(json.dumps(manifest,indent=2)+'\n')

catalog_path=themes/'catalog.json'
catalog=json.loads(catalog_path.read_text())
if not any(x.get('id')=='geometric-twenty-four' for x in catalog.get('themes',[])):
    catalog['themes'].append({'id':'geometric-twenty-four','name':'Geometric Twenty-Four','description':'Dark geometric prism lock screen with cyan and pink indicators, a compact word clock, and a live date header.','format':'folder','url':'geometric-twenty-four.json'})
catalog_path.write_text(json.dumps(catalog,indent=2)+'\n')
print('created geometric-twenty-four')
