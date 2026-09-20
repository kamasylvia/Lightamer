# GUI-1 判别探针（2026-09-20 21:02:19 +0000)

DSC00012.ARW，经 coordinator.load 真实路径 + RenderPipeline 消融。

```
decode: extent=9504x6336 decoder=v9
A full-seed displayTexture: 2560x1707 bgra8Unorm
A full-seed pixels: mean=(0,6,5) center=(0,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=94.2% >=128=0.3%
A seed instances (22): temperature:on lens:on ashift:on flip:on exposure:on toneequal:on crop:on equalizer:on colorin:on highpass:OFF sharpen:on sigmoid:on agx:on filmicrgb:on colisa:on tonecurve:on levels:on shadhi:on bilat:on soften:OFF colorout:on gamma:on
host DisplayProfile.current=ColorSync fallback (custom ICC)
B trio-only 760x507 bgra8: mean=(23,66,50) center=(69,1,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=30.8% >=128=6.3%
C trio-no-gamma 760x507 f32(125): mean=(0.0685,0.1216,0.0896) center=(0.0599,0.0347,0.0208)
D trio+sigmoid 760x507 bgra8: mean=(21,53,41) center=(1,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=46.2% >=128=6.0%
E trio+filmic 760x507 bgra8: mean=(21,58,45) center=(63,1,0) TL=(0,1,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=39.8% >=128=5.5%
F trio+agx 760x507 bgra8: mean=(21,52,40) center=(1,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=46.5% >=128=5.6%
G trio+shadhi 760x507 bgra8: mean=(23,84,66) center=(83,63,1) TL=(0,68,62) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=11.8% >=128=5.5%
I trio+sigmoid+filmic 760x507 bgra8: mean=(20,48,38) center=(1,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=51.2% >=128=5.3%
J trio+sigmoid+agx 760x507 bgra8: mean=(20,44,34) center=(0,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=56.0% >=128=5.4%
K trio+filmic+agx 760x507 bgra8: mean=(20,47,37) center=(1,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=51.6% >=128=4.9%
L trio+3filmic-stack 760x507 bgra8: mean=(19,40,31) center=(0,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=60.2% >=128=5.0%
H full-seed-via-pipe 760x507 bgra8: mean=(0,0,0) center=(0,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=99.6% >=128=0.0%
M trio+toneeq+shadhi+colisa 760x507 bgra8: mean=(24,84,66) center=(82,63,1) TL=(0,68,62) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=11.7% >=128=5.6%
N trio+temp+expo+tcurve+levels 760x507 bgra8: mean=(23,66,50) center=(69,1,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=30.8% >=128=6.3%
O trio+3stack+shadhi 760x507 bgra8: mean=(20,49,38) center=(0,0,0) TL=(0,0,0) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=52.4% >=128=4.9%
P full-minus-3stack 760x507 bgra8: mean=(0,0,0) center=(0,0,0) TL=(0,69,63) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=99.4% >=128=0.0%
Q1 trio+lens+ashift+flip+crop 760x507 bgra8: mean=(0,0,0) center=(0,0,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=99.4% >=128=0.0%
Q2 trio+equalizer+sharpen+bilat 760x507 bgra8: mean=(23,66,50) center=(69,1,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=30.8% >=128=6.3%
Q3 trio+lens-only 760x507 bgra8: mean=(23,66,50) center=(69,1,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=30.8% >=128=6.3%
Q4 trio+ashift-only 760x507 bgra8: mean=(23,66,50) center=(69,1,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=30.8% >=128=6.3%
Q5 trio+flip+crop 760x507 bgra8: mean=(0,0,0) center=(0,0,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=99.4% >=128=0.0%
Q6 trio+crop-only 760x507 bgra8: mean=(0,0,0) center=(0,0,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=99.4% >=128=0.0%
Q7 trio+flip-only 760x507 bgra8: mean=(23,66,50) center=(69,1,0) TL=(0,1,1) TR=(0,0,0) BL=(0,0,0) BR=(0,0,0) <16=30.8% >=128=6.3%
```
