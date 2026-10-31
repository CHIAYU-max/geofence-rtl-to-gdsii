"""Cross products per decision against the receiver count, checked on random convex fences.

Bubble sort + edge check: (N-2)^2 + N, the shift-sort RTL. Fan selection: at most 2N-3.
usage: python ngon_scaling.py [cases per N]
"""
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / 'verif'))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_patterns as g                # noqa: E402
import predicate_model as m             # noqa: E402

cases = int(sys.argv[1]) if len(sys.argv) > 1 else 5000
rng = random.Random(1)
print('N   bubble  fan_max  fan_avg  msb_steps_avg  wrong')
for n in (6, 8, 12, 16, 24):
    pred, steps, wrong = 0, 0, 0
    for k in range(cases):
        rs = g.fence(rng, ('random', 'full', 'tiny', 'thin')[k % 4], n)
        o = g.object_for(rng, rs, ('inner', 'far', 'near', 'edge', 'corner')[(k // 4) % 5])
        c = m.Cost()
        wrong += m.fan(o, rs, c) != g.inside(o, rs)
        pred += c.pred
        steps += c.steps
    print(f'{n:<3d} {(n-2)**2+n:6d} {2*n-3:8d} {pred/cases:8.2f} {steps/cases:14.1f} {wrong:6d}')
