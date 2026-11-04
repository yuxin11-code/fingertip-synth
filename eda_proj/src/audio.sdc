# Tang Mega 138K dual-panel timing constraints.
# The 52.5 MHz oscillator is the only primary clock.  The PLL and CLKDIV
# outputs are generated clocks and remain related to clk_sys.
create_clock -name clk_sys -period 19.047619 -waveform {0 9.523810} [get_nets {g_dual.clk_sys}]
create_generated_clock -name clk_6m -source [get_nets {g_dual.clk_sys}] -multiply_by 31 -divide_by 256 [get_pins {g_dual.pll/PLL_inst/CLKOUT0}]
create_generated_clock -name clk_aud -source [get_pins {g_dual.pll/PLL_inst/CLKOUT0}] -divide_by 4 [get_pins {g_dual.div4/clkdiv_inst/CLKOUT}]

# External serial/I2C/touch inputs are asynchronous to clk_sys.  Only the
# first synchronizer stage is exempted; all logic after that stage remains
# timed normally.  These names are the source-level synchronizer registers.
set_false_path -from [get_ports {UART_RX TTP229_SDO TTP_R_SDO KNOB_SCL KNOB_SDA PAJ_SCL PAJ_SDA K_LEFT K_RIGHT K_AUX3 K_AUX4 TEST_MODE_KEY OCT_A OCT_B OCT_SW_N KEY1 KEY2 ENC_A ENC_B ENC_C PITCH_UP_KEY PITCH_DOWN_KEY rst}]

# The generated audio clock is related, not asynchronous.  The CDC mailbox
# and audio bridge are timed as real paths; no same-domain path is masked.
report_timing -setup -max_paths 100
report_timing -hold -max_paths 100
report_timing -setup -mod_ins {g_dual.instrument/g_additive.voices g_dual.instrument/audio} -max_paths 20
