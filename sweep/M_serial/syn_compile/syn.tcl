read_file -format verilog {../src/geofence_serial.v ../src/geofence_ctrl_serial.v ../src/sort_serial.v }
current_design geofence
link
source -echo -verbose ../../../geofence.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
compile
write -format ddc     -hierarchy -output "geofence_syn.ddc"
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output geofence_syn.v
report_area > area.log
report_area -hierarchy -nosplit > area_hier.log
report_timing > timing.log
exit
