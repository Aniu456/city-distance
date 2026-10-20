"""Convert taiwan-atlas towns TopoJSON to the app's GeoJSON collections.
Usage: python3 tool/import_taiwan.py /path/to/towns-10t.json
Source: https://cdn.jsdelivr.net/npm/taiwan-atlas/towns-10t.json
"""
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1] / 'assets' / 'maps'
topology = json.loads(Path(sys.argv[1]).read_text())
transform = topology['transform']
arcs = []
for raw in topology['arcs']:
    x = y = 0
    arc = []
    for dx, dy in raw:
        x += dx
        y += dy
        arc.append([round(x * transform['scale'][0] + transform['translate'][0], 6),
                    round(y * transform['scale'][1] + transform['translate'][1], 6)])
    arcs.append(arc)


def ring(indices):
    points = []
    for index in indices:
        part = arcs[index] if index >= 0 else list(reversed(arcs[~index]))
        points.extend(part if not points else part[1:])
    return points


def feature(geometry, code, name, level, child_count):
    raw = geometry['arcs']
    coordinates = ([ring(r) for r in raw] if geometry['type'] == 'Polygon'
                   else [[ring(r) for r in polygon] for polygon in raw])
    return {'type': 'Feature', 'properties': {'adcode': code, 'name': name,
            'level': level, 'childrenNum': child_count},
            'geometry': {'type': geometry['type'], 'coordinates': coordinates}}


def write(code, features):
    (root / f'{code}.json').write_text(json.dumps({'type': 'FeatureCollection',
        'features': features}, ensure_ascii=False, separators=(',', ':')))


counties = []
for county in topology['objects']['counties']['geometries']:
    p = county['properties']
    code = 'tw_' + p['COUNTYCODE']  # 源编码加命名空间，不伪装为大陆行政区划代码。
    towns = [g for g in topology['objects']['towns']['geometries']
             if g['properties']['COUNTYCODE'] == p['COUNTYCODE']]
    counties.append(feature(county, code, p['COUNTYNAME'], 'city', len(towns)))
    write(code, [feature(g, 'tw_' + g['properties']['TOWNCODE'],
                        g['properties']['TOWNNAME'], 'district', 0) for g in towns])
write('710000', counties)
national = json.loads((root / '100000.json').read_text())
for f in national['features']:
    if f['properties']['adcode'] == 710000:
        f['properties']['childrenNum'] = len(counties)
(root / '100000.json').write_text(json.dumps(national, ensure_ascii=False, separators=(',', ':')))
print(f'Imported {len(counties)} counties and 368 townships.')
