# Geofence engine: RTL to GDSII in TSMC 0.13 µm

A self-directed implementation of the 2021 IC Design Contest preliminary problem (university cell-based track):
given six receivers and an object, sort the receivers into a convex hexagon by cross product and decide whether
the object lies inside. The design was taken from RTL through synthesis, place and route, and sign-off.

All 50 test patterns pass in RTL, gate-level and post-layout simulation. The layout is DRC clean and passes
black-box LVS.

## Results

Post-layout, slow corner (1.08 V, 125 °C), TSMC 0.13 µm (CIC tsmc13 library), same ICC2 flow for every variant.
Energy per decision = average power from PrimePower (switching activity from the post-layout SDF simulation)
× simulated time / 50 objects.

| Variant | Clock | Cell area (µm²) | Setup / hold slack (ns) | Post-layout sim | Energy / decision (nJ) | DRC | LVS |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Combinational multiplier | 30 ns | 11,739 | +13.08 / +0.30 | 50/50 | 0.695 | clean | pass |
| Combinational + clock gating | 30 ns | 10,714 | +13.07 / +0.13 | 50/50 | 0.527 | clean | pass |
| Serial shift-add multiplier | 30 ns | 10,375 | +13.29 / +0.31 | 50/50 | 3.457 | clean | pass |
| Serial + clock gating | 30 ns | 9,210 | +13.12 / +0.24 | 50/50 | 1.439 | clean | pass |
| Combinational, re-synthesized | 10 ns | 13,202 | −0.02 / +0.42 | 50/50 | 0.600 | clean | see note |
| Combinational, re-synthesized | 8 ns | 13,584 | −0.00 / +0.50 | 50/50 | 0.533 | clean | see note |

- The contest ranks designs by synthesized cell area at a fixed 30-ns clock. By that metric the serial multiplier
  with clock gating wins (−22% area), but it needs 10.5× the cycles and about twice the energy per decision of the
  combinational design. Clock gating helps both architectures (−24% and −58% energy) and also removes the enable
  muxes in front of the flip-flops.
- Clock gating fails SDF gate-level simulation right after synthesis, because the gated clock arrives later than the
  ungated one. After clock-tree synthesis balances both, the gated designs pass post-layout simulation.
- The 8-ns and 10-ns runs explore Fmax (about 125 MHz at the slow corner). Their LVS matches every instance, net and
  port, but IC Validator reports one black-box port mismatch on a single flip-flop; this is still open.

## Flow

| Step | Tool | Script |
| --- | --- | --- |
| Synthesis | Design Compiler | `dc_syn.tcl` |
| Floorplan, power ring and mesh, placement, clock tree, routing, fillers | IC Compiler II | `apr/01_init.tcl`, `apr/02_pnr.tcl`, `apr/03_out.tcl` |
| Post-layout simulation | VCS with the ICC2 SDF | `apr/run_all.sh` |
| Static timing and power | PrimeTime, PrimePower with the ICC2 SPEF | `apr/apr_sweep.sh` |
| DRC, LVS | IC Validator | `apr/run_all.sh` |

`apr/run_all.sh` runs one design end to end; `apr/apr_sweep.sh` runs every variant and writes `sweep_summary.csv`.
Both expect the CIC library at `/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5`.

Notes on the back end:

- Parasitics come from ICC2 with TLU+; the library ships no StarRC tech file.
- The GDS contains only phantom cell frames, so LVS treats standard cells as black boxes.
- Problems fixed along the way: METAL5 power stripes that blocked rail vias, bar vias that break VIA5.W.1 (the flow
  generates a tech file without them), missing port labels, nets that differ only in letter case, and an ICC2
  corner that silently used the 1.32-V fast library until it was bound to the slow PVT.

The baseline RTL is my own. The serial-multiplier variant, the synthesis sweeps and the back-end scripts were
developed with the help of an AI assistant (Claude).
