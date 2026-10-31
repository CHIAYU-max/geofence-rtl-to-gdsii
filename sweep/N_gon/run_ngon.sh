#!/bin/bash
# 2026-10-31 N-gon scaling: for each receiver count, open regression in RTL, synthesis at 30 ns,
# gate-level simulation with SDF, PrimePower energy per decision. Synthesis level, no layout.
# usage: bash run_ngon.sh [gate-level cases, default 200]
cd "$(dirname "$0")"
H=$PWD
ROOT=$(cd ../.. && pwd)
export VERDI_HOME=/mnt/nfs/opt/EDA/synopsys/verdi/cur
LIB=/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5
CASES=${1:-200}
OUT=$H/ngon_summary.csv
echo "receivers,area_um2,noncomb_um2,slack_ns,cycles_per_decision,rtl,gate_sim,power_mW,energy_per_obj_nJ" > $OUT
for n in 6 8 12 16 24; do
    d=$H/N$n; rm -rf $d; mkdir -p $d; cd $d
    python3 $ROOT/verif/gen_patterns.py 2000 2026 $n > patterns.txt
    vcs -full64 -sverilog -q +define+RECV=$n -l vcs_rtl.log $ROOT/verif/tb_geofence.sv $H/src/geofence_ngon.v > /dev/null 2>&1
    ./simv +PAT=patterns.txt -l rtl.log > /dev/null 2>&1
    rtl=FAIL; grep -q '^ALL PASS' rtl.log && rtl=PASS
    cycles=$(awk '/^cases/{print $7; exit}' rtl.log)
    sed "s#/cad/CBDK/CBDK_IC_Contest_v2.1#$LIB#" $ROOT/synopsys_dc.setup > .synopsys_dc.setup
    cat > syn.tcl <<T
analyze -format verilog -define RECV=$n {$H/src/geofence_ngon.v}
elaborate geofence
current_design geofence
link
source -echo -verbose $ROOT/geofence.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
compile
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output geofence_syn.v
report_area > area.log
report_timing > timing.log
exit
T
    dc_shell -f syn.tcl < /dev/null > dc.log 2>&1
    head -$CASES patterns.txt > gate.txt
    vcs -full64 -sverilog -q -debug_access+all -kdb +vcs+fsdbon +define+RECV=$n +define+SDF +define+FSDB +maxdelays +neg_tchk \
        -l vcs_gate.log $ROOT/verif/tb_geofence.sv geofence_syn.v -v $LIB/Verilog/tsmc13_neg.v > /dev/null 2>&1
    ./simv +PAT=gate.txt -l gate.log > /dev/null 2>&1
    gate=FAIL; grep -q '^ALL PASS' gate.log && gate=PASS
    gate_cycles=$(awk '/^cases/{print $7; exit}' gate.log)
    cat > pt.tcl <<T
set search_path ". $LIB/SynopsysDC/db"
set link_library "* slow.db"
set power_enable_analysis true
set power_analysis_mode averaged
read_verilog geofence_syn.v
current_design geofence
link
create_clock -name clk -period 30 [get_ports clk]
read_sdf geofence_syn.sdf
read_fsdb -strip_path tb_geofence/u_geofence novas.fsdb
update_power
report_power > power.rpt
report_power -hierarchy > power_hier.rpt
exit
T
    timeout 1200 pt_shell -f pt.tcl < /dev/null > pt.log 2>&1
    p=$(awk '/^ *Total Power *=/{print $4; exit}' power.rpt); u=$(awk '/^ *Total Power *=/{print $5; exit}' power.rpt)
    mw=$(awk -v p=$p -v u=$u 'BEGIN{m=(u=="W")?1000:(u=="mW")?1:(u=="uW")?0.001:1000; printf "%.4f", p*m}')
    # energy per decision = average power x one decision's time; reset is a few cycles of thousands
    e=$(awk -v m=$mw -v c=$gate_cycles 'BEGIN{printf "%.3f", m*1e-3*c*30e-9*1e9}')
    area=$(awk '/Total cell area/{print $NF}' area.log); nc=$(awk '/Noncombinational area/{print $NF}' area.log)
    slack=$(awk '/slack \(/{print $3; exit}' timing.log)
    echo "$n,$area,$nc,$slack,$cycles,$rtl,$gate,$mw,$e" >> $OUT
    tail -1 $OUT
    rm -rf simv simv.daidir csrc novas.fsdb
    cd $H
done
echo NGON_DONE
