"""Build searchable city coordinates and capital markers from bundled map sources."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
maps = root / 'assets/maps'
capitals = {
 '110000':'北京','120000':'天津','130000':'石家庄','140000':'太原',
 '150000':'呼和浩特','210000':'沈阳','220000':'长春','230000':'哈尔滨',
 '310000':'上海','320000':'南京','330000':'杭州','340000':'合肥',
 '350000':'福州','360000':'南昌','370000':'济南','410000':'郑州',
 '420000':'武汉','430000':'长沙','440000':'广州','450000':'南宁',
 '460000':'海口','500000':'重庆','510000':'成都','520000':'贵阳',
 '530000':'昆明','540000':'拉萨','610000':'西安','620000':'兰州',
 '630000':'西宁','640000':'银川','650000':'乌鲁木齐','710000':'台北',
 '810000':'香港','820000':'澳门'}
municipalities = {'110000','120000','310000','500000','810000','820000'}
cities=[]

def points(value):
 if len(value)>=2 and isinstance(value[0],(int,float)):
  yield value
 else:
  for part in value:yield from points(part)

for province in json.loads((maps/'100000.json').read_text())['features']:
 p=province['properties'];code=str(p['adcode'])
 if code not in capitals:continue
 children=([province] if code in municipalities else
           json.loads((maps/f'{code}.json').read_text())['features'])
 for child in children:
  q=child['properties']
  if code not in municipalities and q.get('level')!='city':continue
  name=q['name'];short=name[:-1] if name.endswith('市') else name
  short=short.replace('臺','台')
  capital=code in municipalities or short==capitals[code]
  center=q.get('center')
  if capital:center=p['center']
  if center is None:
   pts=list(points(child['geometry']['coordinates']))
   center=[(min(v[0] for v in pts)+max(v[0] for v in pts))/2,
           (min(v[1] for v in pts)+max(v[1] for v in pts))/2]
  cities.append(dict(code=str(q['adcode']),name=capitals[code] if code in municipalities else short,
     province=p['name'],provinceCode=code,longitude=center[0],latitude=center[1],
     isCapital=capital,capitalKind=('直辖市' if code in municipalities and code not in {'810000','820000'}
       else '特别行政区' if code in {'810000','820000'} else '首府' if code in {'150000','450000','540000','640000','650000'} else '省会')))
assert len([c for c in cities if c['isCapital']])==34
(root/'assets/cities/catalog.json').write_text(json.dumps(cities,ensure_ascii=False,separators=(',',':')))
print(f'{len(cities)} cities, 34 capital / municipality / SAR markers')
