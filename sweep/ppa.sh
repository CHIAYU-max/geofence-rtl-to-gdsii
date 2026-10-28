#!/bin/bash
# 2026-10-26 合成後 PPA 比較(原檔不動,全部在 sweep/ 下):
#   架構 {組合式乘法器 (geofence_new.v ...), 序列式乘法器 (sweep/M_serial/src)} × 時脈 {30 ns, 10 ns},都用 compile
#   每組: (需要時)DC 合成 → gate-level 模擬(SDF + FSDB 切換活動)→ PrimeTime 平均功耗(slow.db)
#   能量 / 判斷 = 平均功耗 × 模擬總時間 / 50 筆
# usage: bash sweep/ppa.sh   (在 ~/icc2021_geofence 下執行)
cd ~/icc2021_geofence
export VERDI_HOME=/mnt/nfs/opt/EDA/synopsys/verdi/cur
LIB=/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5
ROOT=$PWD
OUT=sweep/ppa_summary.csv
echo "name,arch,cycle_ns,area_um2,slack_ns,sim_ns,cycles,gate_sim,power_mW,energy_per_obj_nJ,annotated" > $OUT

BASE_SRC="$ROOT/geofence_new.v $ROOT/geofence_ctrl.v $ROOT/sort_new.v"
SERIAL_SRC="$ROOT/sweep/M_serial/src/geofence_serial.v $ROOT/sweep/M_serial/src/geofence_ctrl_serial.v $ROOT/sweep/M_serial/src/sort_serial.v"

# 準備一個目錄: setup / sdc / tb 改成指定週期,沒有 netlist 才合成
prepare() {
    local d=$1 cycle=$2 src=$3
    mkdir -p $d && cd $d
    sed "s#/cad/CBDK/CBDK_IC_Contest_v2.1#$LIB#" $ROOT/synopsys_dc.setup > .synopsys_dc.setup
    sed "s/^set cycle .*/set cycle $cycle/" $ROOT/geofence.sdc > geofence.sdc
    sed "s/^\`define CYCLE .*/\`define CYCLE      $cycle/" $ROOT/tb.sv > tb.sv
    ln -sf $ROOT/univ.data .
    if [ ! -f geofence_syn.v ]; then
        cat > syn.tcl <<EOF
read_file -format verilog {$src}
current_design geofence
link
source -echo -verbose geofence.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
compile
write -format ddc     -hierarchy -output "geofence_syn.ddc"
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output geofence_syn.v
report_area > area.log
report_timing > timing.log
exit
EOF
        dc_shell -f syn.tcl > dc.log 2>&1
    fi
    cd $ROOT
}

run() {
    local name=$1 arch=$2 d=$3 cycle=$4 src=$5
    prepare $d $cycle "$src"
    cd $d
    # SUMMARY_ONLY=1: 不重跑模擬與 PrimeTime,只從現有的 vcs_ppa.log / power.rpt 重算總表
    if [ -z "$SUMMARY_ONLY" ]; then
    # gate-level 模擬,保留 FSDB 給 PrimeTime
    vcs -R -full64 -sverilog -debug_access+all -kdb +vcs+fsdbon +define+SDF +maxdelays +neg_tchk \
        tb.sv geofence_syn.v -v $LIB/Verilog/tsmc13_neg.v -l vcs_ppa.log > /dev/null 2>&1
    fi
    local sim=FAIL; grep -q "ALL PASS" vcs_ppa.log && sim=PASS
    # VCS 印出的 finish 時間單位是 ps(log 的 "Time: ... ps")
    local tps=$(grep -oE "finish at simulation time +[0-9]+" vcs_ppa.log | grep -oE "[0-9]+$")
    local sim_ns=$(awk -v t=$tps 'BEGIN{printf "%.1f", t/1000}')
    local cycles=$(awk -v t=$sim_ns -v c=$cycle 'BEGIN{printf "%d", t/c}')
    if [ -z "$SUMMARY_ONLY" ]; then
    # +vcs+fsdbon 時實際的波形在 novas.fsdb,testbench 的 geofence.fsdb 可能是空的: 取比較大的那個
    local fsdb=geofence.fsdb
    [ -f novas.fsdb ] && [ $(stat -c %s novas.fsdb) -gt $(stat -c %s geofence.fsdb 2>/dev/null || echo 0) ] && fsdb=novas.fsdb
    # DC 用的 geofence.sdc 有 PrimeTime 不支援的指令(set_fix_hold 等);平均功耗只需要時脈
    cat > pt_power.tcl <<EOF
set search_path ". $LIB/SynopsysDC/db"
set link_library "* slow.db"
set power_enable_analysis true
set power_analysis_mode averaged
read_verilog ./geofence_syn.v
current_design geofence
link
create_clock -name clk -period $cycle [get_ports clk]
read_sdf ./geofence_syn.sdf
read_fsdb -strip_path testfixture/u_geofence $fsdb
update_power
report_switching_activity > activity.rpt
report_power > power.rpt
report_power -hierarchy > power_hier.rpt
exit
EOF
    # stdin 接 /dev/null: 腳本出錯時 pt_shell 直接結束,不會停在互動提示字元
    timeout 900 pt_shell -f pt_power.tcl < /dev/null > pt.log 2>&1
    fi
    # report_power 的 Total Power 單位依 library(通常 W),轉成 mW
    local p_w=$(awk '/^ *Total Power *=/{print $4; u=$5} END{}' power.rpt | head -1)
    local unit=$(awk '/^ *Total Power *=/{print $5}' power.rpt | head -1)
    local p_mw=$(awk -v p=$p_w -v u=$unit 'BEGIN{m=(u=="W")?1000:(u=="mW")?1:(u=="uW")?0.001:1000; printf "%.4f", p*m}')
    local e_nj=$(awk -v p=$p_mw -v t=$sim_ns 'BEGIN{printf "%.3f", p*1e-3*t*1e-9/50*1e9}')
    local ann=$(grep -oE "[0-9.]+%" activity.rpt | head -1)
    local area=$(awk '/Total cell area/{print $4}' area.log 2>/dev/null)
    local slack=$(awk '/slack \(/{print $NF}' timing.log | head -1)
    rm -rf simv simv.daidir csrc verdiLog novas* ucli.key geofence.fsdb
    cd $ROOT
    echo "$name,$arch,$cycle,$area,$slack,$sim_ns,$cycles,$sim,$p_mw,$e_nj,$ann" | tee -a $OUT
}

run base_30ns   combinational sweep/A0_base               30 "$BASE_SRC"
run base_10ns   combinational sweep/B_10ns                10 "$BASE_SRC"
run serial_30ns serial        sweep/M_serial/syn_compile  30 "$SERIAL_SRC"
run serial_10ns serial        sweep/M_serial/syn_10ns     10 "$SERIAL_SRC"
echo "PPA_DONE $(date '+%F %T')"
