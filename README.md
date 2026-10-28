# Geofence engine: RTL to GDSII in TSMC 0.13 µm

A self-directed implementation of the 2021 IC Design Contest preliminary problem (university cell-based track):
given six receivers and an object, sort the receivers into a convex hexagon by cross product and decide whether
the object lies inside. The design was taken from RTL through synthesis, place and route, and sign-off.

All 50 test patterns pass in RTL, gate-level and post-layout simulation. The layout is DRC clean and passes
black-box LVS.

## Results

Post-layout, TSMC 0.13 µm (CIC tsmc13 library), same ICC2 flow for every variant. Setup is checked at the slow
corner (1.08 V, 125 °C), hold at the slow and fast (1.32 V, −40 °C) corners. Energy per decision = average power
from PrimePower (switching activity from the post-layout SDF simulation) × simulated time / 50 objects. All
variants pass all 50 patterns in post-layout simulation and are DRC clean.

| Variant | Clock | Util. | Cell area (µm²) | Core (µm²) | Setup / hold slow / hold fast (ns) | Energy / decision (nJ) | LVS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Combinational multiplier | 30 ns | 60% | 11,744 | 19,737 | +13.19 / +0.32 / +0.09 | 0.657 | pass |
| Combinational + clock gating | 30 ns | 60% | 10,699 | 17,782 | +13.31 / +0.14 / +0.01 | 0.475 | pass |
| Serial shift-add multiplier | 30 ns | 60% | 10,380 | 17,050 | +13.29 / +0.29 / +0.08 | 3.470 | pass |
| Serial + clock gating | 30 ns | 60% | 9,251 | 15,012 | +12.94 / +0.12 / −0.00 | 1.523 | pass |
| Combinational, re-synthesized | 10 ns | 54% | 13,214 | 24,524 | −0.01 / +0.36 / +0.07 | 0.562 | pass |
| Combinational, re-synthesized | 8 ns | 45% | 13,737 | 30,316 | −0.02 / +0.49 / +0.14 | 0.584 | pass |
| Combinational multiplier | 30 ns | 89% | 11,751 | 13,155 | +13.17 / +0.32 / +0.09 | 0.661 | pass |

- The contest ranks designs by synthesized cell area at a fixed 30-ns clock. By that metric the serial multiplier
  with clock gating wins (−21% area), but it needs 10.5× the cycles and 2.3× the energy per decision of the
  combinational design. Clock gating helps both architectures (−28% and −56% energy) and also removes the enable
  muxes in front of the flip-flops; it tightens hold at the fast corner to about zero slack.
- The same netlist routes cleanly at 89% utilization, shrinking the core by 33% with no change in timing.
- Clock gating fails SDF gate-level simulation right after synthesis, because the gated clock arrives later than the
  ungated one. After clock-tree synthesis balances both, the gated designs pass post-layout simulation.
- The 8-ns and 10-ns runs explore Fmax (about 125 MHz at the slow corner).
- Black-box LVS compares cell ports by name, so a cell type whose Q or QN output is unused in every instance (the
  only EDFFXL in the 10-ns netlist, for example) has no matching layout port. The flow drops Q and QN from the
  port-list comparison; every net, including those driven by Q and QN, is still matched.

## Flow

| Step | Tool | Script |
| --- | --- | --- |
| Synthesis | Design Compiler | `dc_syn.tcl` |
| Floorplan, power ring and mesh, placement, clock tree, routing, fillers | IC Compiler II | `apr/01_init.tcl`, `apr/02_pnr.tcl`, `apr/03_out.tcl` |
| Post-layout simulation | VCS with the ICC2 SDF | `apr/run_all.sh` |
| Static timing and power | PrimeTime, PrimePower with the ICC2 SPEF | `apr/apr_sweep.sh` |
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
| `dc_syn.tcl`, `geofence.sdc`, `synopsys_dc.setup`, `vcs.cmd`, `ncvlog.f` | Synthesis and simulation setup, adapted from the contest kit |
| `sweep/` | Synthesis sweeps (effort, clock, clock gating, serial multiplier) and power analysis; results in `sweep/*summary.csv` |
| `apr/` | ICC2 place-and-route, post-layout simulation, PrimeTime / PrimePower and ICV sign-off |

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

The baseline RTL is my own. The serial-multiplier variant, the synthesis and power sweeps (`sweep/`) and the
back-end scripts (`apr/`) were developed with the help of an AI assistant (Claude).
