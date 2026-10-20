"""在 macOS 上用 sips 从已确认的图标母版导出平台尺寸，不改变图案。"""

import json
import struct
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'assets/branding/app_icon.png'


def export(size, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ['sips', '-z', str(size), str(size), str(SOURCE), '--out', str(target)],
        check=True, stdout=subprocess.DEVNULL,
    )


def main():
    targets = {}
    for folder in [
        'ios/Runner/Assets.xcassets/AppIcon.appiconset',
        'macos/Runner/Assets.xcassets/AppIcon.appiconset',
    ]:
        directory = ROOT / folder
        contents = json.loads((directory / 'Contents.json').read_text())
        for item in contents['images']:
            if 'filename' in item:
                pixels = round(float(item['size'].split('x')[0]) *
                               float(item['scale'].removesuffix('x')))
                targets[directory / item['filename']] = pixels
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        targets[ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'] = size
    for size in [192, 512]:
        targets[ROOT / f'web/icons/Icon-{size}.png'] = size
        targets[ROOT / f'web/icons/Icon-maskable-{size}.png'] = size
    targets[ROOT / 'web/favicon.png'] = 32
    targets[ROOT / 'linux/runner/resources/app_icon.png'] = 256
    for target, size in targets.items():
        export(size, target)
    # ICO 容器保存多尺寸 PNG，图案仍来自同一母版。
    with tempfile.TemporaryDirectory() as temporary:
        images = []
        for size in [16, 32, 48, 64, 128, 256]:
            target = Path(temporary) / f'{size}.png'
            export(size, target)
            images.append((size, target.read_bytes()))
        header = struct.pack('<HHH', 0, 1, len(images))
        offset = 6 + 16 * len(images)
        entries = bytearray()
        for size, data in images:
            dimension = 0 if size == 256 else size
            entries.extend(struct.pack('<BBBBHHII', dimension, dimension,
                                       0, 0, 1, 32, len(data), offset))
            offset += len(data)
        (ROOT / 'windows/runner/resources/app_icon.ico').write_bytes(
            header + entries + b''.join(data for _, data in images))
    print(f'Exported {len(targets)} PNG assets and a 6-size Windows ICO.')


if __name__ == '__main__':
    main()
