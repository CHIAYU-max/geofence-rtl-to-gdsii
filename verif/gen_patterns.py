#!/usr/bin/env python3
"""Generate open test patterns for the geofence engine, no contest files needed.

Each line: object x y, the receivers' x y, expected is_inside, category (all decimal).
The expected value comes from a monotone-chain convex hull, which shares nothing
with the sort-by-angle method in the RTL. An object on the fence counts as outside.

usage: gen_patterns.py <cases> <seed> [receivers, default 6] > patterns.txt
"""
import math
import random
import sys

LIM = 1023


def orient(b, p, q):
    return (p[0]-b[0])*(q[1]-b[1]) - (q[0]-b[0])*(p[1]-b[1])


def hull(pts):
    s = sorted(pts)

    def half(ps):
        h = []
        for p in ps:
            while len(h) >= 2 and orient(h[-2], h[-1], p) <= 0:
                h.pop()
            h.append(p)
        return h[:-1]
    return half(s) + half(s[::-1])


def inside(obj, rs):
    h = hull(rs)
    return all(orient(obj, h[i], h[(i+1) % len(h)]) > 0 for i in range(len(h)))


def strict_fence(pts, n):
    return len(set(pts)) == n and len(hull(pts)) == n


def ellipse(rng, n, cx, cy, ra, rb, tilt=0.0):
    pts = []
    for k in range(n):
        # past six points: one per sector, or nearly every draw fails the convexity test
        t = rng.uniform(0, 2*math.pi) if n == 6 else 2*math.pi*(k + rng.uniform(.2, .8))/n
        x, y = ra*math.cos(t), rb*math.sin(t)
        pts.append((round(cx + x*math.cos(tilt) - y*math.sin(tilt)),
                    round(cy + x*math.sin(tilt) + y*math.cos(tilt))))
    return pts


def fence(rng, kind, n=6):
    while True:
        if kind == 'random':
            ra, rb = rng.uniform(40, 500), rng.uniform(40, 500)
            pts = ellipse(rng, n, rng.uniform(ra, LIM-ra), rng.uniform(rb, LIM-rb), ra, rb)
        elif kind == 'full':            # spans the whole coordinate range
            pts = ellipse(rng, n, 511.5, 511.5, 511.5, 511.5)
        elif kind == 'tiny':            # short vectors, every multiplier bit matters
            r = 16 if n == 6 else 8*n
            pts = ellipse(rng, n, rng.randint(r+4, LIM-r-4), rng.randint(r+4, LIM-r-4), r, r)
        else:                           # thin and tilted, angles nearly equal from one vertex
            pts = ellipse(rng, n, 511.5, 511.5, 500, rng.uniform(8, 40) if n == 6 else rng.uniform(40, 120), rng.uniform(0, math.pi))
        if all(0 <= c <= LIM for p in pts for c in p) and strict_fence(pts, n):
            rng.shuffle(pts)
            return pts


def edge_point(rng, rs):
    """A lattice point exactly on a fence edge, or a vertex if the edge has none."""
    h = hull(rs)
    i = rng.randrange(len(h))
    a, b = h[i], h[(i+1) % len(h)]
    g = math.gcd(abs(b[0]-a[0]), abs(b[1]-a[1]))
    k = rng.randint(0, g-1)
    return (a[0] + (b[0]-a[0])//g*k, a[1] + (b[1]-a[1])//g*k)


def object_for(rng, rs, kind):
    if kind == 'edge':
        return edge_point(rng, rs)
    if kind == 'far':
        return (rng.randint(0, LIM), rng.randint(0, LIM))
    if kind == 'corner':
        return (rng.choice((0, LIM)), rng.choice((0, LIM)))
    # interior mix, or just past an edge to reach both sides of the boundary
    w = [rng.random()**2 for _ in rs]
    t = sum(w)
    p = (sum(a*r[0] for a, r in zip(w, rs))/t, sum(a*r[1] for a, r in zip(w, rs))/t)
    if kind == 'near':
        e = edge_point(rng, rs)
        return (max(0, min(LIM, e[0]+rng.randint(-1, 1))), max(0, min(LIM, e[1]+rng.randint(-1, 1))))
    return (round(p[0]), round(p[1]))


def main():
    cases, rng = int(sys.argv[1]), random.Random(int(sys.argv[2]))
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    fences = ('random', 'full', 'tiny', 'thin')
    objects = ('inner', 'far', 'near', 'edge', 'corner')
    for k in range(cases):
        fk = fences[k % 4]
        ok = objects[(k // 4) % 5]
        rs = fence(rng, fk, n)
        o = object_for(rng, rs, ok)
        flat = [c for p in [o] + rs for c in p]
        print(*flat, int(inside(o, rs)), f'{fk}_{ok}')


if __name__ == '__main__':
    main()
