"""Fetch DataV boundaries as bundled, offline assets. Re-running reuses files."""
import concurrent.futures
import json
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'maps'
BASE = 'https://geo.datav.aliyun.com/areas_v3/bound/'


def fetch(code):
    target = ROOT / f'{code}.json'
    if target.exists():
        return json.loads(target.read_text())
    for attempt in range(4):
        try:
            with urllib.request.urlopen(f'{BASE}{code}_full.json', timeout=30) as response:
                data = json.load(response)
            if data.get('type') != 'FeatureCollection' or not data.get('features'):
                raise ValueError(f'Invalid collection: {code}')
            target.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
            return data
        except Exception:
            if attempt == 3:
                raise
            time.sleep(attempt + 1)


def children(data):
    return [f['properties']['adcode'] for f in data['features']
            if f['properties'].get('childrenNum', 0) > 0]


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    national = fetch(100000)
    provinces = [code for code in children(national) if code != 710000]
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        province_maps = list(pool.map(fetch, provinces))
        cities = sorted({code for data in province_maps for code in children(data)})
        list(pool.map(fetch, cities))
    print(f'Downloaded national + {len(provinces)} provinces + {len(cities)} cities.', flush=True)


if __name__ == '__main__':
    main()
