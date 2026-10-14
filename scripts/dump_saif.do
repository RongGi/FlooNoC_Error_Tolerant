set dut /tb_floo_nw_router_fi/i_dut_wrapper/i_dut
run 200ns                   ;# past reset and warm-up
power add -r $dut/*         ;# counting starts here
run -all
power report -all -bsaif saif/$env(SAIF_NAME).saif
quit -f