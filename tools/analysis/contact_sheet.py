import sys, glob
from PIL import Image
files = sorted(glob.glob(sys.argv[1] + '/*.png'))[::int(sys.argv[3])]
ims = [Image.open(f) for f in files]
w, h = ims[0].size
w, h = w // 2, h // 2
cols = 6
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (cols * w, rows * h))
for i, im in enumerate(ims):
    sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
sheet.save(sys.argv[2])
print(len(ims), sheet.size)
