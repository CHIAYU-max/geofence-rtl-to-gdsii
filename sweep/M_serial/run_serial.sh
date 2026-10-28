#!/bin/bash
# 2026-10-26 序列式乘法器實驗: RTL 模擬 → 合成(compile 與 compile_ultra)→ gate-level 模擬,全部 30 ns
cd ~/icc2021_geofence/sweep/M_serial
export VERDI_HOME=/mnt/nfs/opt/EDA/synopsys/verdi/cur
LIB=/mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5
SRC="src/geofence_serial.v src/geofence_ctrl_serial.v src/sort_serial.v"
sed -i 's/\r$//' src/*.v

echo "== RTL"
mkdir -p rtl && cd rtl && ln -sf ../../../univ.data .
vcs -R -full64 -sverilog -debug_access+all -kdb +vcs+fsdbon ../../../tb.sv $(for f in $SRC; do echo ../$f; done) -l vcs_rtl.log > /dev/null 2>&1
grep -E "ALL PASS|Pass = |Error-" vcs_rtl.log | head -5; grep "finish at" vcs_rtl.log
rm -rf simv simv.daidir csrc *.fsdb
cd ..

for v in compile ultra; do
    echo "== $v"
    mkdir -p syn_$v && cd syn_$v
    sed "s#/cad/CBDK/CBDK_IC_Contest_v2.1#$LIB#" ../../../synopsys_dc.setup > .synopsys_dc.setup
    ln -sf ../../../univ.data .
    if [ $v = compile ]; then cmd="compile"; else cmd="set_max_area 0; compile_ultra"; fi
    cat > syn.tcl <<EOF
read_file -format verilog {$(for f in $SRC; do printf "../%s " $f; done)}
current_design geofence
link
source -echo -verbose ../../../geofence.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
$cmd
write -format ddc     -hierarchy -output "geofence_syn.ddc"
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output geofence_syn.v
report_area > area.log
report_area -hierarchy -nosplit > area_hier.log
report_timing > timing.log
exit
EOF
    dc_shell -f syn.tcl > dc.log 2>&1
    grep -E "Total cell area|^Noncombinational area" area.log
    grep "slack (" timing.log
    vcs -R -full64 -sverilog -debug_access+all -kdb +vcs+fsdbon +define+SDF +maxdelays +neg_tchk \
        ../../../tb.sv geofence_syn.v -v $LIB/Verilog/tsmc13_neg.v -l vcs_gate.log > /dev/null 2>&1
    grep -E "ALL PASS|Pass = " vcs_gate.log | head -2
    rm -rf simv simv.daidir csrc *.fsdb
    cd ..
done
echo SERIAL_DONE
