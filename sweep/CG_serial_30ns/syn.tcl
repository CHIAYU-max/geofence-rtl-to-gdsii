read_file -format verilog {../../sweep/M_serial/src/geofence_serial.v ../../sweep/M_serial/src/geofence_ctrl_serial.v ../../sweep/M_serial/src/sort_serial.v}
current_design geofence
link
source -echo -verbose geofence.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
set_clock_gating_style -sequential_cell latch -positive_edge_logic {integrated} -control_point before -minimum_bitwidth 4
compile -gate_clock
report_clock_gating > cg.rpt
write -format ddc     -hierarchy -output "geofence_syn.ddc"
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output geofence_syn.v
report_area > area.log
report_timing > timing.log
exit
