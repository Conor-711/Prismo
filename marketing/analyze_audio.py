import sys, array, math
data = sys.stdin.buffer.read()
sr = 11025
a = array.array('h'); a.frombytes(data[:len(data)-(len(data)%2)])
n = len(a); dur = n/sr
hop = int(sr*0.01); win = int(sr*0.025); fps = sr/hop
env = []
for i in range(0, n-win, hop):
    acc = 0; c = 0
    for j in range(i, i+win, 5):
        v = a[j]; acc += v*v; c += 1
    env.append(math.sqrt(acc/c))
mx = max(env) or 1.0
envn = [e/mx for e in env]
print("DURATION %.2fs  env_fps=%.1f" % (dur, fps))
print("=== per-1s energy map ===")
secs = int(dur)
for s in range(min(secs, 70)):
    seg = envn[int(s*fps):int((s+1)*fps)]
    m = sum(seg)/len(seg) if seg else 0
    print("%3ds |%-42s| %.2f" % (s, "#"*int(m*42), m))
# onset strength
onset = [max(0.0, envn[i]-envn[i-1]) for i in range(1, len(envn))]
# best sustained energy rise ("drop") scanning whole track, 2s pre vs 2s post
w = int(2*fps); best = (-9, 0)
for i in range(w, len(envn)-w):
    d = sum(envn[i+1:i+1+w])/w - sum(envn[i-w:i])/w
    if d > best[0]: best = (d, i/fps)
print("\nBIGGEST energy lift (drop/chorus) ~ %.2fs  (delta %.2f)" % (best[1], best[0]))
# top onset peaks in first 45s (candidate hits)
seg_end = min(len(onset), int(45*fps))
o = onset[:seg_end]
thr = sorted(o)[int(len(o)*0.98)]
peaks = []
for i in range(2, len(o)-2):
    if o[i] > thr and o[i] >= o[i-1] and o[i] > o[i+1]:
        t = i/fps
        if not peaks or t-peaks[-1] > 0.16: peaks.append(t)
print("TOP onsets 0-45s (s): " + ", ".join("%.2f" % p for p in peaks[:48]))
# tempo via autocorrelation of onset (first 45s)
mean = sum(o)/len(o); oo = [x-mean for x in o]
bt = (0, 0)
for bpm in range(72, 161):
    lag = int(round(fps*60.0/bpm))
    if 1 <= lag < len(oo):
        c = sum(oo[i]*oo[i+lag] for i in range(0, len(oo)-lag, 2))
        if c > bt[0]: bt = (c, bpm)
print("Estimated BPM ~ %d  (1 beat = %.3fs, 1 bar = %.3fs)" % (bt[1], 60.0/bt[1], 4*60.0/bt[1]))
