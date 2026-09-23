"""Package the approved 2026-09-13 logo for iOS and Web; no redrawing."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / 'ios/Brand/bsmart-logo-20260913.png').convert('RGB')
# Fixed artwork bounds in the approved image. Keep the original letter shapes/colors.
wordmark = source.crop((132, 513, 1123, 741)).convert('RGBA')
pixels = []
for r, g, b, _ in wordmark.getdata():
    alpha = 0 if r >= 238 or g - r < 5 else max(0, min(1, (248 - r) / 210))
    if alpha:
        rgb = [round(max(0, min(255, (v - 248 * (1 - alpha)) / alpha))) for v in (r, g, b)]
        pixels.append((*rgb, round(alpha * 255)))
    else:
        pixels.append((0, 0, 0, 0))
wordmark.putdata(pixels)
brand = ROOT / 'web/public/brand'
brand.mkdir(parents=True, exist_ok=True)
source.save(brand / 'bsmart-wordmark-beta.png', optimize=True)
wordmark.save(brand / 'bsmart-wordmark.png', optimize=True)
asset = ROOT / 'ios/BSmart/Assets.xcassets/BSmartWordmark.imageset'
asset.mkdir(parents=True, exist_ok=True)
wordmark.save(asset / 'wordmark.png', optimize=True)
(asset / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'wordmark.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
source.resize((1024, 1024), Image.Resampling.LANCZOS).save(ROOT / 'ios/BSmart/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
# The arrow-r is the approved wordmark's compact signature, not a new symbol.
r_mark = wordmark.crop((767, 31, 898, 223))
icon = Image.new('RGB', (512, 512), '#f8f8f5')
r_mark = r_mark.resize((242, 354), Image.Resampling.LANCZOS)
icon.paste(r_mark, ((512-r_mark.width)//2, (512-r_mark.height)//2), r_mark)
for path, size in [('web/app/icon.png', 64), ('web/public/icon-192.png', 192), ('web/public/icon-512.png', 512), ('web/public/apple-touch-icon.png', 180)]:
    icon.resize((size, size), Image.Resampling.LANCZOS).save(ROOT / path)
icon.save(ROOT / 'web/public/favicon.ico', sizes=[(16, 16), (32, 32), (48, 48)])
print('Updated approved wordmark, iOS AppIcon, favicon and touch icons.')
