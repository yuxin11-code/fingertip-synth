# Single current build entry. Source, clocks, pins and synthesis mode stay unchanged.
cd [file dirname [file normalize [info script]]]
open_project audio.gprj
set_option -top_module top
set_option -output_base_name spectrum_65_1k
set_option -include_path [file join [pwd] src migration]
set_option -timing_driven 1
run syn
run pnr
exit
