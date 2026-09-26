"""使用文字だけに絞った Noto Sans JP Bold を作る（Web 書き出しを軽くするため）

    py -3.10 tools/make_font.py
"""
import glob
import os
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = r"C:\Windows\Fonts\NotoSansJP-VF.ttf"
chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= set("…　、。「」『』（）［］！？：・ー―％＋−／〜")
# 仮名と全角英数記号は全部入れておく（文言を少し直しただけで化けないように）
chars |= set(chr(c) for c in range(0x3040, 0x3100))
chars |= set(chr(c) for c in range(0xFF01, 0xFF5F))
for p in glob.glob(os.path.join(ROOT, "scripts", "*.gd")):
    with open(p, encoding="utf-8") as f:
        for ch in f.read():
            if ord(ch) > 0x7F:
                chars.add(ch)
font = TTFont(SRC)
font = instancer.instantiateVariableFont(font, {"wght": 700})
opts = subset.Options()
opts.layout_features = ["*"]
sub = subset.Subsetter(opts)
sub.populate(text="".join(sorted(chars)))
sub.subset(font)
out = os.path.join(ROOT, "fonts", "NotoSansJP-Bold-subset.ttf")
font.save(out)
print(len(chars), "chars ->", os.path.getsize(out), "bytes")
