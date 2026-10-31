#!/bin/bash
# Equivalence checks of the RTL against the synthesized and the post-layout netlists.
# usage: bash run_fm.sh [post-layout dir, default ../apr/variants]
cd "$(dirname "$0")"
F=$PWD
ROOT=$(cd .. && pwd)
VARS=${1:-$ROOT/apr/variants}
export DW_ROOT=$(dirname $(dirname $(command -v dc_shell)))
BASE="$ROOT/geofence_new.v $ROOT/geofence_ctrl.v $ROOT/sort_new.v"
SERIAL="$ROOT/sweep/M_serial/src/geofence_serial.v $ROOT/sweep/M_serial/src/geofence_ctrl_serial.v $ROOT/sweep/M_serial/src/sort_serial.v"

check() {  # name rtl_files netlist svf cg
    local d=$F/out/$1
    rm -rf $d && mkdir -p $d && cd $d
    RTL_FILES="$2" GATE_NETLIST="$3" SVF="$4" CG=$5 timeout 1800 fm_shell -f $F/fm.tcl < /dev/null > fm.log 2>&1
    printf '%-20s %s\n' "$1" "$(grep -m1 '^FORMAL_RESULT' fm.log || echo NO_RESULT)"
    cd $F
}

check syn_comb    "$BASE"   $ROOT/sweep/A0_base/geofence_syn.v        $ROOT/sweep/A0_base/default.svf 0
check syn_comb_cg "$BASE"   $ROOT/sweep/CG_base_30ns/geofence_syn.v   $ROOT/sweep/CG_base_30ns/default.svf 1
check syn_serial  "$SERIAL" $ROOT/sweep/M_serial/syn_compile/geofence_syn.v $ROOT/sweep/M_serial/syn_compile/default.svf 0
check apr_comb    "$BASE"   $VARS/comb_30/out/geofence_apr.v          $ROOT/sweep/A0_base/default.svf 0
check apr_comb_cg "$BASE"   $VARS/comb_cg_30/out/geofence_apr.v       $ROOT/sweep/CG_base_30ns/default.svf 1
