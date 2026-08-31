`include "common_cells/registers.svh"
`include "redundancy_cells/voters.svh"

`ifndef REDUNDANCY_CELLS_REGISTERS_SVH_
`define REDUNDANCY_CELLS_REGISTERS_SVH_

// Abridged Summary of available FF macros:
// `FF:      asynchronous active-low reset
// `FFL:     load-enable and asynchronous active-low reset


`ifdef VERILATOR
`define NO_SYNOPSYS_FF 1
`endif


// Flip-Flop with asynchronous active-low reset and TMR
// __q: Q output of FF
// __d: D input of FF
// __tmp: placeholder for TMR
// __fault_any: output error detected from TMR 
// __reset_value: value assigned upon reset
// (__clk: clock input)
// (__arst_n: asynchronous reset, active-low)
`define TMRFF(__q, __d, __fault_any, __reset_value, __clk = `REG_DFLT_CLK, __arst_n = `REG_DFLT_RST_N) \
  if ($bits(__q[0]) > 1) begin      \
    rel_ff_tmr #(                   \
      .DataWidth($bits(__q[0])),    \
      .VoterType(1),                \
      .MultiBit(1)                  \
    ) ff_tmr (                      \
      .clk_i(__clk),                \
      .rst_ni(__arst_n),            \
      .multi_i(__d),                \
      .multi_o(__q),                \
      .multi_reset_val_i(__reset_value),         \
      .single_i(),                  \
      .single_o(),                  \
      .single_reset_val_i(),        \
      .fault_detected_o(__fault_any)\
    );                              \
  end else begin                    \
    rel_ff_tmr #(                   \
      .DataWidth($bits(__q[0])),    \
      .VoterType(1),                \
      .MultiBit(0)                  \
    ) ff_tmr (                      \
      .clk_i(__clk),                \
      .rst_ni(__arst_n),            \
      .multi_i(),                   \
      .multi_o(),                   \
      .multi_reset_val_i(),         \
      .single_i(__d),               \
      .single_o(__q),               \
      .single_reset_val_i(__reset_value),        \
      .fault_detected_o(__fault_any)\
    );                              \
  end


// Flip-Flop with load-enable and asynchronous active-low reset (implicit clock and reset) and TMR
// __q: Q output of FF
// __d: D input of FF
// __tmp: placeholder for TMR
// __fault_any: output error detected from TMR 
// __load: load d value into FF
// __reset_value: value assigned upon reset
// (__clk: clock input)
// (__arst_n: asynchronous reset, active-low)
`define TMRFFL(__q, __d, __fault_any, __load, __reset_value, __clk = `REG_DFLT_CLK, __arst_n = `REG_DFLT_RST_N) \
  if ($bits(__q[0]) > 1) begin      \
    rel_ffl_tmr #(                  \
      .DataWidth($bits(__q[0])),    \
      .VoterType(1),                \
      .MultiBit(1)                  \
    ) ff_tmr (                      \
      .clk_i(__clk),                \
      .rst_ni(__arst_n),            \
      .multi_i(__d),                \
      .multi_o(__q),                \
      .multi_reset_val_i(__reset_value),         \
      .single_i(),                  \
      .single_o(),                  \
      .single_reset_val_i(),        \
      .load_i(__load),              \
      .fault_detected_o(__fault_any)\
    );                              \
  end else begin                    \
    rel_ffl_tmr #(                  \
      .DataWidth($bits(__q[0])),    \
      .VoterType(1),                \
      .MultiBit(0)                  \
    ) ff_tmr (                      \
      .clk_i(__clk),                \
      .rst_ni(__arst_n),            \
      .multi_i(),                   \
      .multi_o(),                   \
      .multi_reset_val_i(),         \
      .single_i(__d),               \
      .single_o(__q),               \
      .single_reset_val_i(__reset_value),        \
      .load_i(__load),              \
      .fault_detected_o(__fault_any)\
    );                              \
  end

 
`endif
