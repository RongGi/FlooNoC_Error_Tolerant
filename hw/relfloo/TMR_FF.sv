// Flipflop add on at the end for redundancy
module rel_ff_tmr #(
  parameter type data_t = logic,
  parameter int unsigned VoterType = 1 // 0: Classical_MV, 1: KP_MV, 2: BN_MV
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  data_t [2:0]               data_i,
  output data_t [2:0]               data_o,
  input  data_t                     reset_val_i,

  output logic                 fault_detected_o // Indicates any type of mismatch
);
  //indexing proofing
  typedef logic [$bits(data_t)-1:0] data_vec_t;

  data_vec_t [2:0] FF_q;
  data_vec_t [2:0] data_in, data_out;
  data_vec_t [2:0] fault_detected;
  data_vec_t reset_val_in;


  //io_assignment
  assign data_in = data_i;
  assign data_o = data_out;
  assign reset_val_in = reset_val_i;

  //Triplicated FlipFlop
  for (genvar j = 0; j < 3; j++) begin : gen_tmr_FF
    for (genvar i = 0; i < $bits(data_t); i++) begin : gen_bit_FF
      always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
        if (!rst_ni) begin
        FF_q[j][i] <= reset_val_in[i];
        end else begin
        FF_q[j][i] <= data_in[j][i];
        end
      end
    end
  end

  //after register TMR voting
  for (genvar j = 0; j < 3; j++) begin: tmr
    for (genvar i = 0; i < $bits(data_t); i++) begin : gen_bit_voters
        TMR_voter_fail #(
        .VoterType ( VoterType )
        ) i_voter_fail (
        .a_i              ( FF_q[0][i]            ),
        .b_i              ( FF_q[1][i]            ),
        .c_i              ( FF_q[2][i]            ),
        .majority_o       ( data_out[j][i]     ),
        .fault_detected_o ( fault_detected[j][i] )
        );
    end
  end

  assign fault_detected_o = |fault_detected;

endmodule

module rel_ffl_tmr #(
  parameter type data_t = logic,
  parameter int unsigned VoterType = 1 // 0: Classical_MV, 1: KP_MV, 2: BN_MV
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  data_t [2:0]               data_i,
  output data_t [2:0]               data_o,
  input  data_t                     reset_val_i,

  input logic [2:0]                 load_i,

  output logic                 fault_detected_o // Indicates any type of mismatch
);
  //indexing proofing
  typedef logic [$bits(data_t)-1:0] data_vec_t;

  data_vec_t [2:0] FF_q, FF_d;
  data_vec_t [2:0] data_in, data_out;
  data_vec_t [2:0] fault_detected;
  data_vec_t reset_val_in;
  data_vec_t [2:0] update;

  //io_assignment
  assign data_in = data_i;
  assign data_o = data_out;
  assign reset_val_in = reset_val_i;

  for (genvar j = 0; j < 3; j++) begin : gen_TMR_FF
    for (genvar i = 0; i < $bits(data_t); i++) begin : gen_bit_FF
      //generate load signal and input data
      assign update[j][i] = load_i[j] || fault_detected[j][i];
      assign FF_d[j][i]   = load_i[j] ? data_in[j][i] : data_out[j][i];

      always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
        if (!rst_ni) begin
          FF_q[j][i] <= reset_val_in[i];
        end else begin
          if (update[j][i]) begin
            FF_q[j][i] <= FF_d[j][i];
          end
        end
      end
    end
  end

  //after register TMR voting
  for (genvar j = 0; j < 3; j++) begin: tmr
    for (genvar i = 0; i < $bits(data_t); i++) begin : gen_bit_voters
        TMR_voter_fail #(
        .VoterType ( VoterType )
        ) i_voter_fail (
        .a_i              ( FF_q[0][i]            ),
        .b_i              ( FF_q[1][i]            ),
        .c_i              ( FF_q[2][i]            ),
        .majority_o       ( data_out[j][i]     ),
        .fault_detected_o ( fault_detected[j][i] )
        );
    end
  end

  assign fault_detected_o = |fault_detected;

endmodule