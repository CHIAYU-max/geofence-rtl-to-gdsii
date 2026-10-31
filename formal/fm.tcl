# Formality: RTL against a gate-level netlist. Set by run_fm.sh:
# RTL_FILES, GATE_NETLIST, SVF ("" = none), CG (1 = clock gated netlist)
set LIB /mnt/nfs/opt/PROCESS/CBDK_IC_Contest_v2.5/SynopsysDC/db
set hdlin_dwroot $env(DW_ROOT)
set synopsys_auto_setup true
if {$env(CG) == 1} { set verification_clock_gate_hold_mode COLLAPSE_ALL_CG_CELLS }
if {$env(SVF) != ""} { set_svf $env(SVF) }

read_db -technology_library $LIB/slow.db
read_verilog -container r -libname WORK -05 $env(RTL_FILES)
set_top r:/WORK/geofence
read_verilog -container i -libname WORK -05 $env(GATE_NETLIST)
set_top i:/WORK/geofence

match
set ok [verify]
report_unmatched_points -status unread > unmatched.rpt
report_failing_points > failing.rpt
puts "FORMAL_RESULT [expr {$ok ? "PASS" : "FAIL"}]"
exit
