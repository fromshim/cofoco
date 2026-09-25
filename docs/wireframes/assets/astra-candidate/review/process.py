"""Alpha-only Vision mask application and aspect-preserving canvas normalization."""
from pathlib import Path
import sys, json, hashlib
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
frame = sys.argv[1]
target_height = int(sys.argv[2]) if len(sys.argv)>2 else 425
source = ROOT/'raw'/f'{frame}-v2-source.png'
maskfile = ROOT/'review/masks'/f'{frame}.png'
im = Image.open(source).convert('RGB')
mask = Image.open(maskfile).convert('L')
assert im.size == mask.size
rgba = im.convert('RGBA'); rgba.putalpha(mask)
assert np.array_equal(np.asarray(rgba)[:,:,:3], np.asarray(im)), 'Extraction must modify alpha only'
rgba.save(ROOT/'review/segmented'/f'{frame}.png')
b = mask.getbbox(); assert b
crop=rgba.crop(b)
size=(round(crop.width*target_height/crop.height),target_height)
out=Image.new('RGBA',(768,512))
out.paste(crop.resize(size, Image.Resampling.LANCZOS), (round(384-size[0]/2),470-size[1]))
out.save(ROOT/f'usagi-smooth-{frame}.png')
a=out.getchannel('A'); bb=a.getbbox()
stats={'frame':frame,'source':str(source.relative_to(ROOT)),'mask':str(maskfile.relative_to(ROOT)),'method':'macOS Vision VNGenerateForegroundInstanceMaskRequest, allInstances; generated scaled mask applied to alpha only','rgb_unchanged_before_normalization':True,'source_size':im.size,'source_alpha_bbox':b,'scale':target_height/crop.height,'size':out.size,'bbox':bb,'center':[(bb[0]+bb[2])/2,(bb[1]+bb[3])/2],'baseline':bb[3]-1,'margins':[bb[0],bb[1],768-bb[2],512-bb[3]],'sha256':hashlib.sha256((ROOT/f'usagi-smooth-{frame}.png').read_bytes()).hexdigest()}
(ROOT/'review'/f'{frame}-processing.json').write_text(json.dumps(stats,indent=2))
print(json.dumps(stats))
# Full source/result comparison at normalized 200% scale on three QA grounds.
display=crop.resize(size,Image.Resampling.LANCZOS).resize((size[0]*2,size[1]*2))
rawcrop=im.crop(b).resize(size,Image.Resampling.LANCZOS).resize(display.size)
qa=Image.new('RGB',(display.width*4,display.height+40),'#dddddd'); d=ImageDraw.Draw(qa)
qa.paste(rawcrop,(0,40));d.text((12,12),'RAW SOURCE (same crop, 200%)',fill='black')
for i,bg in enumerate(['#ffffff','#808080','#101010'],1):
 tile=Image.new('RGBA',display.size,bg);tile.alpha_composite(display);qa.paste(tile.convert('RGB'),(i*display.width,40));d.text((i*display.width+12,12),f'ALPHA RESULT {bg} (200%)',fill='black')
qa.save(ROOT/'review'/f'{frame}-edges-200.png')
