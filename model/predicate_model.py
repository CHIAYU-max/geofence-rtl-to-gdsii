"""Feasibility model for geofence algorithm / predicate-unit ideas. Not RTL."""
import math, random, statistics as st, sys

def orient(b, p, q):
    return (p[0]-b[0])*(q[1]-b[1]) - (q[0]-b[0])*(p[1]-b[1])

# ---- reference: brute force, independent of the methods under test
def hull_order(rs):
    pts = sorted(rs)
    def half(ps):
        h = []
        for p in ps:
            while len(h) >= 2 and orient(h[-2], h[-1], p) <= 0:
                h.pop()
            h.append(p)
        return h[:-1]
    return half(pts) + half(pts[::-1])

def reference(obj, rs):
    h = hull_order(rs)
    if len(h) < 3:
        return False
    return all(orient(obj, h[i], h[(i+1) % len(h)]) > 0 for i in range(len(h)))

# ---- predicate unit: sign of Ax*By - Bx*Ay, MSB-first, 13-bit accumulator
def msb_sign(base, p, q):
    """returns (sign, steps, max|D|). Terms are 0, Ax, -Bx, Ax-Bx; all |term| <= 1023."""
    ax, ay = p[0]-base[0], p[1]-base[1]
    bx, by = q[0]-base[0], q[1]-base[1]
    d, peak = 0, 0
    for k in range(10, -1, -1):
        ybit = (by >> k) & 1
        abit = (ay >> k) & 1
        t = (ax if ybit else 0) - (bx if abit else 0)
        if k == 10:
            t = -t
        d = 2*d + t
        peak = max(peak, abs(d))
        steps = 11 - k
        if abs(d) >= 1024:
            return (1 if d > 0 else -1), steps, peak
    return (d > 0) - (d < 0), 11, peak

class Cost:
    def __init__(s): s.pred = 0; s.steps = 0; s.peak = 0; s.table = []
    def o(s, b, p, q):
        s.pred += 1
        sg, n, pk = msb_sign(b, p, q)
        assert sg == ((orient(b, p, q) > 0) - (orient(b, p, q) < 0)), (b, p, q)
        s.steps += n; s.peak = max(s.peak, pk)
        return sg

# ---- M0: current design, 4 passes x 4 compares + 6 edges
def m0(obj, rs, c, early=False):
    r0, ring = rs[0], list(rs[1:])
    for _ in range(4):
        for i in range(4):
            if c.o(r0, ring[i], ring[i+1]) < 0:
                ring[i], ring[i+1] = ring[i+1], ring[i]
    # ring is now clockwise seen from r0 ... the RTL keeps the larger angle first
    fence = [r0] + ring
    ok = True
    for i in range(6):
        if c.o(obj, fence[i], fence[(i+1) % 6]) <= 0:
            ok = False
            if early: break
    return ok

# NOTE a/b: s>=0 rays are clockwise of obj, so a = nearest from cw side, b = nearest from ccw side
# ---- M1: sort-free fan selection around r0
def fan(obj, rs, c):
    r0, others = rs[0], rs[1:]
    left, right = [], []                # left: object is ccw of ray r0->ri
    pos = neg = False
    for r in others:
        s = c.o(obj, r0, r)             # orient(obj,r0,r) == orient(r0,r,obj)
        if s > 0: pos = True
        if s < 0: neg = True
        (left if s >= 0 else right).append(r)
    # early exit is worth more on hardware but the flags are only final after 5
    if not (pos and neg):
        return False
    a = left[0]                         # most clockwise ray of the s >= 0 set
    for r in left[1:]:
        if c.o(r0, a, r) > 0: a = r
    b = right[0]                        # most counter-clockwise ray of the s < 0 set
    for r in right[1:]:
        if c.o(r0, r, b) > 0: b = r
    return c.o(obj, a, b) > 0

# ---- M2: order-free pair test, base always obj
def pairs(obj, rs, c):
    n = len(rs)
    s = [[0]*n for _ in range(n)]
    for i in range(n):
        for j in range(i+1, n):
            s[i][j] = c.o(obj, rs[i], rs[j]); s[j][i] = -s[i][j]
    for i in range(n):
        o = [s[i][j] for j in range(n) if j != i]
        if all(v >= 0 for v in o) or all(v <= 0 for v in o):
            return False
    return True

def gen_convex(rng, lim=1023, n=6):
    while True:
        cx, cy = rng.uniform(.3, .7)*lim, rng.uniform(.3, .7)*lim
        R = rng.uniform(.15, .5)*lim
        pts = set()
        for t in sorted(rng.uniform(0, 2*math.pi) for _ in range(n)):
            e = rng.uniform(.7, 1)
            pts.add((round(cx+R*e*math.cos(t)), round(cy+R*rng.uniform(.7,1)*math.sin(t))))
        pts = [p for p in pts if 0 <= p[0] <= lim and 0 <= p[1] <= lim]
        if len(pts) == n and len(hull_order(pts)) == n:
            rng.shuffle(pts)
            return pts

def gen_obj(rng, rs, lim=1023):
    if rng.random() < .5:               # roughly balanced inside / outside
        return (rng.randint(0, lim), rng.randint(0, lim))
    w = [rng.random() for _ in rs]; t = sum(w)
    return (round(sum(a*r[0] for a, r in zip(w, rs))/t), round(sum(a*r[1] for a, r in zip(w, rs))/t))

def load_real(path):
    tok = open(path).read().split()
    out, i = [], 0
    while i < len(tok):
        assert tok[i] == 'object'
        lab = int(tok[i+2]); v = list(map(int, tok[i+3:i+17])); i += 17
        out.append(((v[0], v[1]), [(v[k], v[k+1]) for k in range(2, 14, 2)], lab))
    return out

def run(name, cases):
    stats = {}
    meth = {'M0 bubble+check': lambda o, r, c: m0(o, r, c),
            'M0 + early exit': lambda o, r, c: m0(o, r, c, True),
            'M1 fan select':   fan,
            'M2 pair test':    pairs}
    print(f'\n== {name}: {len(cases)} cases, inside {sum(reference(o,r) for o,r,*_ in cases)}')
    for m, f in meth.items():
        preds, steps, peak, bad = [], [], 0, 0
        for o, r, *_ in cases:
            c = Cost(); ans = f(o, r, c)
            bad += ans != reference(o, r)
            preds.append(c.pred); steps.append(c.steps); peak = max(peak, c.peak)
        ss = sorted(steps)
        print(f'{m:18s} wrong {bad:5d} | predicates avg {st.mean(preds):5.2f} max {max(preds):2d} '
              f'| msb steps/pred {sum(steps)/sum(preds):5.2f} | total steps avg {st.mean(steps):6.1f} '
              f'p99 {ss[int(.99*len(ss))]:3d} max {max(steps):3d} | peak|D| {peak}')

if __name__ == '__main__':
    if len(sys.argv) > 1:                # optional: the contest univ.data, not redistributed
        real = load_real(sys.argv[1])
        print('label mismatches:', sum(int(reference(o, r)) != l for o, r, l in real))
        run('official 50', [(o, r) for o, r, l in real])
    rng = random.Random(1)
    big = []
    for _ in range(30000):
        r = gen_convex(rng); big.append((gen_obj(rng, r), r))
    run('random full-range', big)
    # small grid: forces collinear objects and zero cross products
    small = []
    while len(small) < 30000:
        r = gen_convex(rng, lim=14); small.append(((rng.randint(0, 14), rng.randint(0, 14)), r))
    run('small grid (degenerate)', small)
    # exhaustive-ish check of the 13-bit claim on extreme triples
    peak = 0
    for _ in range(300000):
        pts = [(rng.choice((0, 1, 511, 512, 1022, 1023, rng.randint(0, 1023))),
                rng.choice((0, 1, 511, 512, 1022, 1023, rng.randint(0, 1023)))) for _ in range(3)]
        sg, n, pk = msb_sign(*pts)
        o = orient(*pts); assert sg == (o > 0) - (o < 0), pts
        peak = max(peak, pk)
    print('msb unit: 300k extreme triples exact, peak |D| =', peak, 'needs signed bits', 1+math.ceil(math.log2(peak+1)))
