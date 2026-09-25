"""Refine a Vision semantic foreground mask with image-aware graph cut.

Vision supplies the foreground identity and trimap. Graph cut refines its boundary
using local image appearance; this is not color-keying or background flood fill.
Only the output alpha mask changes. Source RGB is never edited.
"""
from pathlib import Path
import sys, json
import numpy as np
import cv2
from PIL import Image

root=Path(__file__).resolve().parent.parent
frame=sys.argv[1]
p=root/'review/masks'/f'{frame}.png'
vision=Image.open(p).convert('L')
original=p.with_name(f'{frame}-vision.png')
if not original.exists(): vision.save(original)
v=np.asarray(Image.open(original).convert('L'))
rgb=np.asarray(Image.open(root/'raw'/f'{frame}-v2-source.png').convert('RGB'))
kernel=cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(41,41))
envelope=cv2.dilate((v>12).astype(np.uint8),kernel)>0
sure=cv2.erode((v>250).astype(np.uint8),np.ones((9,9),np.uint8))>0
labels=np.full(v.shape,cv2.GC_PR_BGD,np.uint8)
labels[~envelope]=cv2.GC_BGD
labels[v>100]=cv2.GC_PR_FGD
labels[sure]=cv2.GC_FGD
bg=np.zeros((1,65));fg=np.zeros((1,65))
cv2.grabCut(cv2.cvtColor(rgb,cv2.COLOR_RGB2BGR),labels,None,bg,fg,5,cv2.GC_INIT_WITH_MASK)
mask=np.isin(labels,[cv2.GC_FGD,cv2.GC_PR_FGD]).astype(np.uint8)*255
Image.fromarray(mask).save(p)
print(json.dumps({'frame':frame,'method':'Vision semantic trimap + 5-iteration OpenCV GrabCut boundary refinement','vision_nonzero':int((v>0).sum()),'refined_nonzero':int((mask>0).sum()),'refinement_reason':'Vision clipped dark ear outline and retained matte halo','source_rgb_untouched':True}))
