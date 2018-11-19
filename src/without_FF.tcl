
#Assemble the design source files

read_vhdl ./design3_without_FF.vhd

set outputDir ./design3_without_FF
file mkdir $outputDir

synth_design -top design3_without_FF -part xc7z020clg400-1
write_checkpoint -force $outputDir/post_synth
report_utilization -file $outputDir/post_syth_util.rpt
report_timing -sort_by group -max_paths 5 -path_type summary -file $outputDir/post_synth_timing.rpt

opt_design
power_opt_design

place_design
write_checkpoint -force $outputDir/post_place
phys_opt_design

route-design
write_checkpoint -force $outputDir/post_route

report_timing -summary -file $outputDir/post_route_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file $outputDir/post-route_timing.rpt

report_utilization -file$outputDir/post_route_util.rpt
report_drc -file $outputDir/cpu_imp_netlist.v
write_xdc -no-fixed_only -force $outputDir/cpu_imp.xdc 

#Generating Bit stream
#write_bitstream -file $outputDir/design.bit

