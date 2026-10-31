#!/bin/bash
# Open regression: RTL (baseline, serial), a mutant that must fail, post-layout netlists.
# usage: bash run_verif.sh [cases] [post-layout dir, default ../apr/variants]
# run on the server with VCS; no contest files are used
cd "$(dirname "$0")"
V=$PWD
ROOT=$(cd .. && pwd)
CASES=${1:-20000}
VARS=${2:-$ROOT/apr/variants}
LIB=/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5
mkdir -p out
python3 gen_patterns.py $CASES 2026 > out/patterns.txt

sim() {  # name, then VCS arguments
    local name=$1; shift
    local d=$V/out/$name
    rm -rf $d && mkdir -p $d && cd $d
    vcs -full64 -sverilog -q -l vcs.log "$@" > /dev/null 2>&1
    ./simv +PAT=$V/out/patterns.txt ${MAXCASE:++MAXCASE=$MAXCASE} -l sim.log > /dev/null 2>&1
    printf '%-18s %s\n' "$name" "$(grep -E '^cases' sim.log) $(grep -E '^(ALL PASS|FAILED)' sim.log)"
    grep -m3 '^ERROR' sim.log
    rm -rf simv simv.daidir csrc ucli.key
    cd $V
}

sim rtl_base   $V/tb_geofence.sv $ROOT/geofence_new.v $ROOT/geofence_ctrl.v $ROOT/sort_new.v
sim rtl_serial $V/tb_geofence.sv $ROOT/sweep/M_serial/src/*.v
sim rtl_dual   $V/tb_geofence.sv $ROOT/sweep/M_dual/src/*.v
sim rtl_ngon6  $V/tb_geofence.sv $ROOT/sweep/N_gon/src/geofence_ngon.v

# a wrong design has to fail, otherwise the regression proves nothing
sed 's/assign ccw = (prod_q > prod);/assign ccw = (prod_q >= prod);/' $ROOT/sort_new.v > out/sort_mutant.v
sim mutant_ge  $V/tb_geofence.sv $ROOT/geofence_new.v $ROOT/geofence_ctrl.v $V/out/sort_mutant.v

# post-layout: a subset is enough, the netlist is timing annotated
export MAXCASE=${POST_CASES:-2000}
for v in comb_30 comb_cg_30 serial_cg_30 dual_30 dual_cg_30; do
    [ -f $VARS/$v/out/geofence_apr.v ] || continue
    sim post_$v +define+SDF +define+SDFFILE=\"$VARS/$v/out/geofence_apr.sdf\" +maxdelays +neg_tchk \
        $V/tb_geofence.sv $VARS/$v/out/geofence_apr.v -v $LIB/Verilog/tsmc13_neg.v
done
