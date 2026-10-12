"""Review sheets only; numbered screenshot originals remain unmodified."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

folder = Path(sys.argv[1])
pattern = sys.argv[2]
prefix = sys.argv[3]
files = sorted(folder.glob(pattern))
for page in range((len(files) + 5) // 6):
    sheet = Image.new('RGB', (1500, 1500), '#dddddd')
    draw = ImageDraw.Draw(sheet)
    for n, path in enumerate(files[page * 6:page * 6 + 6]):
        pic = Image.open(path).convert('RGB')
        pic.thumbnail((490, 695))
        x, y = n % 3 * 500, n // 3 * 750
        sheet.paste(pic, (x + (500-pic.width)//2, y+45))
        name = path.name
        draw.text((x+5, y+5), name[:65], fill='black')
        if len(name)>65: draw.text((x+5, y+20), name[65:], fill='black')
    dest = folder / f'{prefix}_{page}.jpg'
    sheet.save(dest, quality=90)
    print(dest)
