# Geofence engine: RTL to GDSII in TSMC 0.13 µm

A self-directed implementation of the 2021 IC Design Contest preliminary problem (university cell-based track):
given six receivers and an object, sort the receivers into a convex hexagon by cross product and decide whether
the object lies inside. The design was taken from RTL through synthesis, place and route, and sign-off.

All 50 test patterns pass in RTL, gate-level and post-layout simulation. The layout is DRC clean and passes
black-box LVS.

## Results

Post-layout, TSMC 0.13 µm (CIC tsmc13 library), same ICC2 flow for every variant. Setup is checked at the slow
corner (1.08 V, 125 °C), hold at the slow and fast (1.32 V, −40 °C) corners. Energy per decision = average power
from PrimePower (switching activity from the post-layout SDF simulation) × simulated time / 50 objects, at the
slow corner and at the typical corner (1.2 V, 25 °C, same activity, slow-corner SPEF). All variants pass all 50
patterns in post-layout simulation and are DRC clean.

| Variant | Clock | Util. | Cell area (µm²) | Core (µm²) | Setup / hold slow / hold fast (ns) | Energy / decision, slow (nJ) | Energy / decision, typical (nJ) | LVS |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Combinational multiplier | 30 ns | 60% | 11,744 | 19,737 | +13.19 / +0.32 / +0.09 | 0.657 | 0.821 | pass |
| Combinational + clock gating | 30 ns | 60% | 10,933 | 17,782 | +13.41 / +0.25 / +0.05 | 0.479 | 0.597 | pass |
| Serial shift-add multiplier | 30 ns | 60% | 10,383 | 17,050 | +13.29 / +0.31 / +0.09 | 3.480 | 4.215 | pass |
| Serial + clock gating | 30 ns | 60% | 9,361 | 15,012 | +12.94 / +0.25 / +0.05 | 1.523 | 1.798 | pass |
| Combinational, re-synthesized | 10 ns | 54% | 13,218 | 24,524 | −0.00 / +0.35 / +0.06 | 0.559 | 0.706 | pass |
| Combinational, re-synthesized | 8 ns | 45% | 13,737 | 30,316 | −0.02 / +0.49 / +0.14 | 0.584 | 0.739 | pass |
| Combinational multiplier | 30 ns | 89% | 11,758 | 13,155 | +12.70 / +0.30 / +0.09 | 0.664 | 0.830 | pass |
| Two multipliers | 30 ns | 60% | 15,219 | 25,473 | +12.24 / +0.31 / +0.09 | 0.444 | 0.555 | pass |
| Two multipliers + clock gating | 30 ns | 61% | 14,126 | 23,314 | +12.72 / +0.26 / +0.06 | 0.390 | 0.488 | pass |
| Two multipliers, re-synthesized | 10 ns | 50% | 17,093 | 34,118 | −0.01 / +0.41 / +0.13 | 0.410 | 0.522 | pass |
| Two multipliers, re-synthesized | 8 ns | 40% | 17,794 | 44,312 | −0.02 / +0.49 / +0.15 | 0.410 | 0.521 | pass |

- The contest ranks designs by synthesized cell area at a fixed 30-ns clock. By that metric the serial multiplier
  with clock gating wins (−20% area), but it needs 10.5× the cycles and 2.3× the energy per decision of the
  combinational design. Clock gating helps both architectures (−27% and −56% energy) and also removes the enable
  muxes in front of the flip-flops. Its gated clock paths need hold buffers: 2% more cell area in exchange for
  +0.05 ns hold at the fast corner.
- Two multipliers finish a cross product per cycle, so a decision takes 34 cycles instead of 60. That design is 30%
  larger but spends 32% less energy per decision, and with clock gating 41% less than the baseline. The lowest-energy
  design is the one the contest area metric ranks last.
- ICC2 hold fixing uses 0.15 ns of hold uncertainty in both scenarios and PrimeTime signs off with 0.1 ns, which
  leaves the 0.05 ns margin. Before this the fast scenario had no uncertainty, so sign-off landed on zero slack.
- In the combinational design 34% of the power is in the clock network and 32% in the multiplier
  (`rpt/pt_power_hier.rpt` from `apr_sweep.sh`).
- The same netlist routes cleanly at 89% utilization, shrinking the core by 33% for 0.5 ns of setup slack.
- Clock gating fails SDF gate-level simulation right after synthesis, because the gated clock arrives later than the
  ungated one. After clock-tree synthesis balances both, the gated designs pass post-layout simulation.
- The 8-ns and 10-ns runs explore Fmax (about 125 MHz at the slow corner); they miss setup by up to 0.02 ns.
- Black-box LVS compares cell ports by name, so a cell type whose Q or QN output is unused in every instance (the
  only EDFFXL in the 10-ns netlist, for example) has no matching layout port. The flow drops Q and QN from the
  port-list comparison; every net, including those driven by Q and QN, is still matched.

## Scaling to N receivers

`sweep/N_gon/` generalizes the baseline shift-sort design to N receivers. Results are at synthesis level (30 ns, SDF
gate-level activity from the open patterns, slow corner), so they are not comparable with the post-layout table.
The modeled fan selection is from `model/ngon_scaling.py`; it has no RTL.

| Receivers | Cell area (µm²) | Cycles / decision | Energy / decision (nJ) | Cross products, RTL | Cross products, fan selection (model, max) |
| --- | --- | --- | --- | --- | --- |
| 6 | 12,160 | 60 | 0.514 | 22 | 9 |
| 8 | 13,888 | 110 | 1.300 | 44 | 13 |
| 12 | 16,614 | 258 | 3.907 | 112 | 21 |
| 16 | 19,542 | 470 | 8.416 | 212 | 29 |
| 24 | 25,814 | 1,086 | 23.728 | 508 | 45 |

Going from 6 to 24 receivers multiplies area by 2.1 but energy by 46, because bubble sort grows as N². All sizes pass
2,000 random patterns in RTL and 200 in gate-level simulation.

## Verification

These run without any contest files.

| Check | Result | Script |
| --- | --- | --- |
| Random regression: 20 fence and object classes, including extreme, tiny and thin fences and objects on the fence; expected values from an independent convex-hull model | 20,000 cases pass in RTL (combinational, serial, two multipliers, N-gon at N = 6), 2,000 in post-layout simulation (five netlists) | `verif/run_verif.sh` |
| Mutation check: `>` changed to `>=` in the cross-product comparison | Caught, 4,534 wrong results | `verif/run_verif.sh` |
| Equivalence, Formality | RTL matches the synthesized netlists (combinational, clock gated, serial) and the post-layout netlists (combinational, clock gated) | `formal/run_fm.sh` |

`model/predicate_model.py` is a cycle-count model for sort-free fence algorithms and an MSB-first cross-product
sign unit. It is an architecture study; those designs are not in the RTL.

## Flow

| Step | Tool | Script |
| --- | --- | --- |
| Synthesis | Design Compiler | `dc_syn.tcl` |
| Floorplan, power ring and mesh, placement, clock tree, routing, fillers | IC Compiler II | `apr/01_init.tcl`, `apr/02_pnr.tcl`, `apr/03_out.tcl` |
| Post-layout simulation | VCS with the ICC2 SDF | `apr/run_all.sh` |
| Static timing and power | PrimeTime, PrimePower with the ICC2 SPEF | `apr/apr_sweep.sh` |
| Equivalence checking | Formality | `formal/run_fm.sh` |
| DRC, LVS | IC Validator | `apr/run_all.sh` |

`apr/run_all.sh` runs one design end to end; `apr/apr_sweep.sh` runs every variant and writes `sweep_summary.csv`.
Both expect the CIC library at `/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5`. Synthesized netlists are not committed:
run the synthesis in `sweep/` (`ppa.sh`, `cg.sh`, `M_serial/run_serial.sh`, or `dc_shell -f syn.tcl` in a
variant's folder) before `apr_sweep.sh`.

## Repository layout

| Path | Contents |
| --- | --- |
| `geofence_new.v`, `geofence_ctrl.v`, `sort_new.v` | Baseline design: one shared 11×11 multiplier, receivers sorted by shifting |
| `sweep/M_serial/src/` | Serial shift-add multiplier variant |
| `sweep/M_dual/` | Two-multiplier variant, one cross product per cycle |
| `sweep/N_gon/` | Baseline design generalized to N receivers, results in `ngon_summary.csv` |
| `dc_syn.tcl`, `geofence.sdc`, `synopsys_dc.setup`, `vcs.cmd`, `ncvlog.f` | Synthesis and simulation setup, adapted from the contest kit |
| `sweep/` | Synthesis sweeps (effort, clock, clock gating, serial multiplier) and power analysis; results in `sweep/*summary.csv` |
| `apr/` | ICC2 place-and-route, post-layout simulation, PrimeTime / PrimePower and ICV sign-off; results in `apr/sweep_summary.csv` |
| `verif/`, `formal/`, `model/` | Open regression, equivalence checks and architecture model |

Some script comments are in Chinese.

## Contest files

The problem statement, testbench (`tb.sv`) and test patterns (`univ.data`) belong to the contest organizer and are
not included. Download the 2021 university cell-based preliminary problem from the IC Design Contest site and put
`tb.sv` and `univ.data` in the repository root before running the scripts. The TSMC 0.13 µm library and technology
files are under NDA and are not included either.

Notes on the back end:

- Parasitics come from ICC2 with TLU+; the library ships no StarRC tech file.
- The GDS contains only phantom cell frames, so LVS treats standard cells as black boxes.
- Problems fixed along the way: METAL5 power stripes that blocked rail vias, bar vias that break VIA5.W.1 (the flow
  generates a tech file without them), missing port labels, nets that differ only in letter case, an ICC2
  corner that silently used the 1.32-V fast library until it was bound to the slow PVT, and unused Q / QN outputs
  in black-box LVS.

## Credits

The baseline RTL is my own. The serial, two-multiplier and N-receiver variants, the synthesis and power sweeps (`sweep/`), the
back-end scripts (`apr/`) and the verification and model code (`verif/`, `formal/`, `model/`) were developed with the help of an AI assistant (Claude).
