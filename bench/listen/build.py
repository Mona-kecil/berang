"""Build listen/index.html with every clip inlined, so it plays and seeks anywhere."""
import base64
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
summary = json.load(open(f"{HERE}/../results/summary.json"))
NAMES = {
    "phonon": "Phonon 31m", "pocket_18m": "Pocket 18M", "pocket": "Pocket 100M", "piper_med": "Piper medium",
    "kitten2_nano": "Kitten 2 nano", "kitten08_mini": "Kitten 0.8 mini", "kokoro_int8": "Kokoro 8-bit",
    "kokoro": "Kokoro", "kitten2_mini": "Kitten 2 mini", "piper_high": "Piper high", "moss_nano": "MOSS Nano",
    "say": "macOS Samantha",
    "pocket_you": "Pocket 100M · your voice", "pocket_18m_you": "Pocket 18M · your voice",
}
CLONE_DIRS = {"pocket_you": "pocket", "pocket_18m_you": "pocket_18m"}

corpus = json.load(open(f"{HERE}/../corpus.json"))
texts = {x["id"]: " ".join(x["sentences"]) for x in corpus["passages"]}
texts["hard_clean"] = texts["hard"]
cards = []
FIRST = ["pocket_you", "pocket_18m_you", "phonon", "kitten2_nano", "pocket_18m", "pocket"]
for m, name in sorted(NAMES.items(), key=lambda kv: FIRST.index(kv[0]) if kv[0] in FIRST else len(FIRST)):
    s = summary.get(m)
    if m in CLONE_DIRS:
        if not os.path.exists(f"{HERE}/../clone/{CLONE_DIRS[m]}/metrics.json"):
            continue
        cm = json.load(open(f"{HERE}/../clone/{CLONE_DIRS[m]}/metrics.json"))["para"]
        s = {"first_audio_short_s": {"median": cm["first_audio_s"]}, "rtf_long": {"median": cm["rtf"]}}
    if not s:
        continue
    srcs = {p: "data:audio/mp4;base64," + base64.b64encode(open(f"{HERE}/{m}_{p}.m4a", "rb").read()).decode()
            for p in ("para", "hard", "hard_clean")}
    first = s["first_audio_short_s"]["median"]
    cards.append(f"""<div class="row"><div class="name">{name}</div>
<div class="stat">{first:.2f}s · {s['rtf_long']['median']:.2f}×</div>
<audio controls preload="metadata" data-model="{m}" data-para="{srcs['para']}" data-hard="{srcs['hard']}" data-hard_clean="{srcs['hard_clean']}"></audio></div>""")

html = """<!doctype html><meta charset="utf-8"><style>
body{margin:0;font-family:var(--font-sans,system-ui)}
.bar{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px;align-items:center}
.group{display:flex;gap:4px}
button{font:inherit;font-size:13px;padding:6px 10px;border-radius:var(--radius,8px);border:1px solid var(--border,#444);
 background:transparent;color:var(--foreground,#eee);cursor:pointer}
button[aria-pressed=true]{background:var(--primary,#4af);color:var(--primary-foreground,#000);border-color:transparent}
.row{display:grid;grid-template-columns:150px 110px 1fr;gap:10px;align-items:center;padding:6px 0;border-top:1px solid var(--border,#333)}
.name{font-weight:600}.stat{color:var(--muted-foreground,#999);font-size:13px;font-variant-numeric:tabular-nums}
audio{width:100%;height:36px}
.text span{border-radius:4px;transition:background .08s}.text span.on{background:var(--primary,#4af);color:var(--primary-foreground,#000)}
.text{padding:12px 16px;border-radius:var(--radius,8px);background:var(--card,#1a1a1a);line-height:1.6;font-size:15px;margin-bottom:12px}
@media(max-width:520px){.row{grid-template-columns:1fr auto}.row audio{grid-column:1/-1}}
</style>
<div class="bar"><div class="group" id="clip"><button aria-pressed="true" data-v="para">Paragraph</button><button aria-pressed="false" data-v="hard">Hard text</button><button aria-pressed="false" data-v="hard_clean">Hard text, cleaned</button></div>
<div class="group" id="speed"><button aria-pressed="true" data-v="1">1×</button><button aria-pressed="false" data-v="1.5">1.5×</button><button aria-pressed="false" data-v="2">2×</button><button aria-pressed="false" data-v="3">3×</button></div></div>
<p class="text" id="text" data-para="__PARA__" data-hard="__HARD__" data-hard_clean="__HARD__"></p>
<div class="row" style="border-top:0"><div class="stat">model</div><div class="stat">first audio · speed</div><div></div></div>
""" + "\n".join(cards) + """
<script>
const audios=[...document.querySelectorAll('audio')];let rate=1;audios.forEach(a=>a.src=a.dataset.para);const text=document.getElementById('text');const T=__TIMINGS__;let clip='para',spans=[];
function render(){text.innerHTML='';spans=text.dataset[clip].split(' ').map((w,i)=>{if(i)text.append(' ');const s=document.createElement('span');s.textContent=w;text.append(s);return s})}
render();let cur=-1;
function tick(a){const t=(T[a.dataset.model]||{})[clip]||[];const x=a.currentTime;let i=t.findIndex(([s,e])=>x<e);if(i>=0&&x<t[i][0]-0.15)i=-1;
 if(i!==cur){spans[cur]?.classList.remove('on');spans[i]?.classList.add('on');cur=i}if(!a.paused)requestAnimationFrame(()=>tick(a))}
audios.forEach(a=>{a.addEventListener('play',()=>requestAnimationFrame(()=>tick(a)));a.addEventListener('seeked',()=>tick(a));a.addEventListener('ended',()=>{spans[cur]?.classList.remove('on');cur=-1})});
audios.forEach(a=>{a.preservesPitch=true;a.addEventListener('play',()=>{audios.forEach(o=>o!==a&&o.pause());a.playbackRate=rate})});
function group(id,fn){const g=document.getElementById(id);g.addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;
 g.querySelectorAll('button').forEach(x=>x.setAttribute('aria-pressed',x===b));fn(b.dataset.v)})}
group('clip',v=>{clip=v;cur=-1;render();audios.forEach(a=>{a.pause();a.src=a.dataset[v];a.playbackRate=rate})});
group('speed',v=>{rate=+v;audios.forEach(a=>a.playbackRate=rate)});
</script>"""
import html as h
html = html.replace("__TIMINGS__", open(f"{HERE}/timings.json").read()).replace("__PARA__", h.escape(texts["para"])).replace("__HARD__", h.escape(texts["hard"]))
open(f"{HERE}/index.html", "w").write(html)
print(len(html))
