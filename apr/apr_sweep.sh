#!/bin/bash
# 2026-10-27 post-layout PPA sweep: each synthesized netlist goes through the same ICC2 flow
# (01_init / 02_pnr / 03_out), then post-layout gate-level simulation with the ICC2 SDF,
# PrimeTime STA + PrimePower with the ICC2 SPEF (no StarRC: tsmc13 has no nxtgrd), ICV DRC and LVS.
# usage: bash apr_sweep.sh [name ...]   (run in ~/icc2021_geofence/apr; no names = all variants)
cd "$(dirname "$0")"
APR=$PWD
ROOT=$(cd .. && pwd)
LIB=/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5
export VERDI_HOME=/mnt/nfs/opt/EDA/synopsys/verdi/cur
OUT=$APR/sweep_summary.csv
[ -f $APR/tsmc13_CIC_nofat.tf ] || awk '/ContactCode.*_fat/{f=1} f&&/^}/{f=0;next} !f' $LIB/ICC2/tsmc13_CIC.tf > $APR/tsmc13_CIC_nofat.tf

# name arch clock_gating cycle_ns target_util netlist (relative to ~/icc2021_geofence)
VARIANTS="
comb_30      combinational no  30 0.6 sweep/A0_base/geofence_syn.v
comb_cg_30   combinational yes 30 0.6 sweep/CG_base_30ns/geofence_syn.v
serial_30    serial        no  30 0.6 sweep/M_serial/syn_compile/geofence_syn.v
serial_cg_30 serial        yes 30 0.6 sweep/CG_serial_30ns/geofence_syn.v
comb_10      combinational no  10 0.6 sweep/B_10ns/geofence_syn.v
comb_8       combinational no  8  0.6 sweep/B_8ns/geofence_syn.v
comb_30_u70  combinational no  30 0.7 sweep/A0_base/geofence_syn.v
comb_30_u80  combinational no  30 0.8 sweep/A0_base/geofence_syn.v
comb_30_u90  combinational no  30 0.9 sweep/A0_base/geofence_syn.v
"

# setup: slow corner (1.08 V, 125 C); hold: slow and fast (1.32 V, -40 C) corners, both in PrimeTime
[ -f $OUT ] || echo "name,arch,clock_gating,cycle_ns,target_util,cells,cell_area_um2,core_area_um2,util,setup_wns_ns,hold_slow_ns,hold_fast_ns,post_sim,sim_ns,power_mW,energy_per_obj_nJ,drc,lvs" > $OUT

run() {
    local name=$1 arch=$2 cg=$3 cycle=$4 tutil=$5 netlist=$ROOT/$6
    local d=$APR/variants/$name
    rm -rf $d && mkdir -p $d/rpt && cd $d
    cp $APR/01_init.tcl $APR/02_pnr.tcl $APR/03_out.tcl .
    ln -sf $APR/tsmc13_CIC_nofat.tf .
    sed -e "s#^set NETLIST .*#set NETLIST $netlist#" -e "s#^set UTIL .*#set UTIL    $tutil#" $APR/common.tcl > common.tcl
    sed -e "s/^set cycle .*/set cycle $cycle/" $APR/apr.sdc > apr.sdc
    for s in 01_init 02_pnr 03_out; do
        timeout 3600 icc2_shell -f $s.tcl -output_log_file $s.log < /dev/null > /dev/null 2>&1
        if ! grep -q "STAGE: ${s#*_} done" $s.log; then
            echo "$name,$arch,$cg,$cycle,$tutil,,,,,,,,ICC2_FAIL_$s,,,,," >> $OUT; cd $APR; return
        fi
    done

    # post-layout gate-level simulation (testbench clock changed to this cycle), FSDB for PrimePower
    mkdir -p sim && cd sim
    sed "s/^\`define CYCLE .*/\`define CYCLE      $cycle/" $ROOT/tb.sv > tb.sv
    ln -sf ../out/geofence_apr.sdf geofence_syn.sdf
    ln -sf $ROOT/univ.data univ.data
    vcs -R -full64 -sverilog -debug_access+all -kdb +vcs+fsdbon +define+SDF +maxdelays +neg_tchk \
        tb.sv ../out/geofence_apr.v -v $LIB/Verilog/tsmc13_neg.v -l vcs_post.log > /dev/null 2>&1
    local sim=FAIL; grep -q "ALL PASS" vcs_post.log && sim=PASS
    local tps=$(grep -oE "finish at simulation time +[0-9]+" vcs_post.log | grep -oE "[0-9]+$")
    local sim_ns=$(awk -v t=$tps 'BEGIN{printf "%.1f", t/1000}')
    local fsdb=geofence.fsdb
    [ -f novas.fsdb ] && [ $(stat -c %s novas.fsdb) -gt $(stat -c %s geofence.fsdb 2>/dev/null || echo 0) ] && fsdb=novas.fsdb
    cd ..

    # PrimeTime: post-route STA and averaged power with the ICC2 SPEF
    # ICC2 writes one SPEF per corner, named by temperature: slow 125 C, fast -40 C
    local spef=$(ls out/*_125.spef | head -1)
    local spef_fast=$(ls out/*_-40.spef | head -1)
    cat > pt_fast.tcl <<EOF
set search_path ". $LIB/SynopsysDC/db"
set link_library "* fast.db"
read_verilog out/geofence_apr.v
current_design geofence
link
create_clock -name clk -period $cycle [get_ports clk]
set_clock_uncertainty 0.1 [all_clocks]
set_propagated_clock [all_clocks]
set_input_delay 0 -clock clk -clock_fall [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0 -clock clk -clock_fall [all_outputs]
set_load 1 [all_outputs]
read_parasitics -format spef $spef_fast
report_timing -delay_type min -max_paths 3 -slack_lesser_than 1000 > rpt/pt_fast_timing_min.rpt
exit
EOF
    timeout 900 pt_shell -f pt_fast.tcl < /dev/null > pt_fast.log 2>&1
    local hold_fast=$(awk '/slack \(/{print $NF; exit}' rpt/pt_fast_timing_min.rpt)
    cat > pt.tcl <<EOF
set search_path ". $LIB/SynopsysDC/db"
set link_library "* slow.db"
set power_enable_analysis true
set power_analysis_mode averaged
read_verilog out/geofence_apr.v
current_design geofence
link
create_clock -name clk -period $cycle [get_ports clk]
set_clock_uncertainty 0.1 [all_clocks]
set_propagated_clock [all_clocks]
set_input_delay 0 -clock clk -clock_fall [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0 -clock clk -clock_fall [all_outputs]
set_load 1 [all_outputs]
read_parasitics -format spef $spef
report_annotated_parasitics > rpt/pt_annotated.rpt
report_timing -delay_type max -max_paths 3 -slack_lesser_than 1000 > rpt/pt_timing_max.rpt
report_timing -delay_type min -max_paths 3 -slack_lesser_than 1000 > rpt/pt_timing_min.rpt
read_fsdb -strip_path testfixture/u_geofence sim/$fsdb
update_power
report_switching_activity > rpt/pt_activity.rpt
report_power > rpt/pt_power.rpt
exit
EOF
    timeout 1800 pt_shell -f pt.tcl < /dev/null > pt.log 2>&1
    local setup=$(awk '/slack \(/{print $NF; exit}' rpt/pt_timing_max.rpt)
    local hold=$(awk '/slack \(/{print $NF; exit}' rpt/pt_timing_min.rpt)
    local p_w=$(awk '/^ *Total Power *=/{print $4; exit}' rpt/pt_power.rpt)
    local unit=$(awk '/^ *Total Power *=/{print $5; exit}' rpt/pt_power.rpt)
    local p_mw=$(awk -v p=$p_w -v u=$unit 'BEGIN{m=(u=="W")?1000:(u=="mW")?1:(u=="uW")?0.001:1000; printf "%.4f", p*m}')
    local e_nj=$(awk -v p=$p_mw -v t=$sim_ns 'BEGIN{printf "%.3f", p*1e-3*t*1e-9/50*1e9}')

    # ICV DRC and black-box LVS
    mkdir -p drc lvs
    cp $LIB/icv/drc/ICV13S_8M.drc.rs drc/
    cp $LIB/icv/lvs/* lvs/
    (cd drc && icv -i ../out/geofence.gds -c geofence -host_init 4 ICV13S_8M.drc.rs > icv_drc.out 2>&1)
    (cd lvs && icv_nettran -outType SPICE -verilog ../out/geofence_apr_pg.v -outName verilog2spice.sp > nettran.out 2>&1 &&
        icv -vue -i ../out/geofence.gds -c geofence -s verilog2spice.sp -stc geofence -sf SPICE -host_init 4 ICV_LVS.rs > icv_lvs.out 2>&1)
    local drc=$(grep -oE "RESULTS: [A-Z ]+" drc/geofence.RESULTS | head -1 | awk '{print $2$3}')
    local lvs=$(grep -oE "LVS Compare Results: [A-Z]+" lvs/geofence.RESULTS | awk '{print $NF}')

    local cells=$(awk '/Leaf Cell Count/{print $NF; exit}' rpt/final_qor.rpt)
    local area=$(awk '/Cell Area \(netlist\):/{print $NF; exit}' rpt/final_qor.rpt)
    local core=$(awk '/^Total Area:/{print $NF; exit}' rpt/utilization.rpt)
    local util=$(awk '/Utilization Ratio/{print $NF; exit}' rpt/utilization.rpt)
    rm -rf sim/simv sim/simv.daidir sim/csrc sim/verdiLog sim/ucli.key
    echo "$name,$arch,$cg,$cycle,$tutil,$cells,$area,$core,$util,$setup,$hold,$hold_fast,$sim,$sim_ns,$p_mw,$e_nj,$drc,$lvs" >> $OUT
    cd $APR
}

echo "$VARIANTS" | while read name arch cg cycle tutil netlist; do
    [ -z "$name" ] && continue
    if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$name"; then continue; fi
    echo "$(date '+%F %T') $name start"
    run $name $arch $cg $cycle $tutil $netlist
    echo "$(date '+%F %T') $name done"
done
echo "SWEEP_DONE $(date '+%F %T')"
