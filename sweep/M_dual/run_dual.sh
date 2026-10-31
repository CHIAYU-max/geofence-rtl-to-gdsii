#!/bin/bash
# 2026-10-31 two-multiplier experiment: synthesis at 30, 10 and 8 ns plus clock gating at 30 ns,
# gate-level simulation with the contest testbench.
# Layout afterwards: apr/apr_sweep.sh dual_30 dual_cg_30 dual_10 dual_8
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
export VERDI_HOME=/mnt/nfs/opt/EDA/synopsys/verdi/cur
LIB=/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5
SRC="$PWD/src/geofence_dual.v $PWD/src/geofence_ctrl_dual.v $PWD/src/sort_dual.v"
CG_STYLE="set_clock_gating_style -sequential_cell latch -positive_edge_logic {integrated} -control_point before -minimum_bitwidth 4"

run() {  # name cycle gated
    local name=$1 cycle=$2 style="" cmd=compile
    [ "$3" = yes ] && style=$CG_STYLE && cmd="compile -gate_clock"
    mkdir -p syn_$name && cd syn_$name
    sed "s#/cad/CBDK/CBDK_IC_Contest_v2.1#$LIB#" $ROOT/synopsys_dc.setup > .synopsys_dc.setup
    sed "s/^set cycle .*/set cycle $cycle/" $ROOT/geofence.sdc > geofence.sdc
    sed "s/^.define CYCLE .*/\`define CYCLE      $cycle/" $ROOT/tb.sv > tb.sv
    ln -sf $ROOT/univ.data .
    cat > syn.tcl <<T
read_file -format verilog {$SRC}
current_design geofence
link
source -echo -verbose geofence.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
$style
$cmd
write -format ddc     -hierarchy -output "geofence_syn.ddc"
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output geofence_syn.v
report_area > area.log
report_area -hierarchy -nosplit > area_hier.log
report_timing > timing.log
exit
T
    dc_shell -f syn.tcl < /dev/null > dc.log 2>&1
    vcs -R -full64 -sverilog -debug_access+all -kdb +vcs+fsdbon +define+SDF +maxdelays +neg_tchk \
        tb.sv geofence_syn.v -v $LIB/Verilog/tsmc13_neg.v -l vcs_gate.log > /dev/null 2>&1
    echo "$name area $(awk '/Total cell area/{print $NF}' area.log) slack $(awk '/slack \(/{print $3; exit}' timing.log) gate_pass $(grep -c 'ALL PASS' vcs_gate.log)"
    rm -rf simv simv.daidir csrc *.fsdb
    cd ..
}

run 30 30 no
run cg_30 30 yes
run 10 10 no
run 8 8 no
echo DUAL_DONE
