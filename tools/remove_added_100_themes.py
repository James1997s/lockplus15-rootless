from pathlib import Path
import subprocess, json, shutil
ROOT=Path('/home/ubuntu/lockplus15-rootless')
CAT=ROOT/'themes/catalog.json'
BASE='2a04c45246c0e0832961fda193bbdd2672fbfd76'
old=json.loads(subprocess.check_output(['git','show',f'{BASE}:themes/catalog.json'],cwd=ROOT))
old_ids={x['id'] for x in old['themes']}
current=json.loads(CAT.read_text())
current_ids={x['id'] for x in current['themes']}
remove=sorted(current_ids-old_ids)
if len(remove)!=100:
    raise SystemExit(f'expected exactly 100 added themes, found {len(remove)}')
for tid in remove:
    d=ROOT/'themes/folder-themes'/tid
    if d.exists(): shutil.rmtree(d)
CAT.write_text(json.dumps(old,indent=2)+'\n')
print('removed',len(remove))
print('preserved',len(old_ids))
print('removed_ids')
print('\n'.join(remove))
