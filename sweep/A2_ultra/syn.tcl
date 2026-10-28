read_file -format verilog {../../geofence_new.v ../../geofence_ctrl.v ../../sort_new.v}
current_design geofence
link
source -echo -verbose geofence.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
set_max_area 0; compile_ultra
write -format ddc     -hierarchy -output "geofence_syn.ddc"
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output geofence_syn.v
report_area > area.log
report_timing > timing.log
report_qor   >  geofence_syn.qor
exit
