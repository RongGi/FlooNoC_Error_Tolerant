// Flipflop add on at the end for redundancy
module rel_ff_tmr #(
  parameter int unsigned DataWidth = 32,
  parameter int unsigned VoterType = 1, // 0: Classical_MV, 1: KP_MV, 2: BN_MV
  parameter int unsigned MultiBit = 1
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  logic [2:0][DataWidth-1:0] multi_i,
  output logic [2:0][DataWidth-1:0] multi_o,
  input  logic [DataWidth-1:0]      multi_reset_val_i,

  input  logic [2:0]                single_i,
  output logic [2:0]                single_o,
  input  logic                      single_reset_val_i,

  output logic                 fault_detected_o // Indicates any type of mismatch
);
  if (MultiBit) begin
    logic [2:0][DataWidth-1:0] fault_detected_mul;
    logic [2:0][DataWidth-1:0] multi_tmp;
    always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
        if (!rst_ni) begin
        multi_tmp <= ({3{multi_reset_val_i}});
        end else begin
        multi_tmp <= (multi_i);
        end
    end
    for (genvar i = 0; i < DataWidth; i++) begin : gen_bit_voters
      for (genvar j = 0; j < 3; j++) begin: tmr
          TMR_voter_fail #(
          .VoterType ( VoterType )
          ) i_voter_fail (
          .a_i              ( multi_tmp[0][i]            ),
          .b_i              ( multi_tmp[1][i]            ),
          .c_i              ( multi_tmp[2][i]            ),
          .majority_o       ( multi_o[j][i]     ),
          .fault_detected_o ( fault_detected_mul[j][i] )
          );
      end
    end
    assign fault_detected_o = |fault_detected_mul;

  //if tripicated signal is single bit
  end else begin
    logic [2:0] fault_detected;
    logic [2:0] single_tmp;
    always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
        if (!rst_ni) begin
        single_tmp <= ({3{single_reset_val_i}});
        end else begin
        single_tmp <= (single_i);
        end
    end
    for (genvar j = 0; j < 3; j++) begin: tmr
        TMR_voter_fail #(
        .VoterType ( VoterType )
        ) i_voter_fail (
        .a_i              ( single_tmp[0]            ),
        .b_i              ( single_tmp[1]            ),
        .c_i              ( single_tmp[2]            ),
        .majority_o       ( single_o[j]     ),
        .fault_detected_o ( fault_detected[j] )
        );
    end
    assign fault_detected_o = |fault_detected;
  end

endmodule

module rel_ffl_tmr #(
  parameter int unsigned DataWidth = 32,
  parameter int unsigned VoterType = 1, // 0: Classical_MV, 1: KP_MV, 2: BN_MV
  parameter int unsigned MultiBit = 1
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  
  input  logic [2:0][DataWidth-1:0] multi_i,
  output logic [2:0][DataWidth-1:0] multi_o,
  input  logic [DataWidth-1:0]      multi_reset_val_i,

  input  logic [2:0]                single_i,
  output logic [2:0]                single_o,
  input  logic                      single_reset_val_i,

  input  logic [2:0]           load_i,
  output logic                 fault_detected_o // Indicates any type of mismatch
);
  if (MultiBit) begin
    logic [2:0][DataWidth-1:0] fault_detected_mul;
    logic [2:0][DataWidth-1:0] multi_tmp;
    logic update;
    logic [2:0][DataWidth-1:0] d_in;

    assign update =  load_i || fault_detected_o;
    assign d_in =    load_i ? multi_i : multi_o;
    always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
      if (!rst_ni) begin
        multi_tmp <= ({3{multi_reset_val_i}});
      end else begin
        if (update) begin
          multi_tmp <= d_in;
        end
      end
    end
    for (genvar i = 0; i < DataWidth; i++) begin : gen_bit_voters
      for (genvar j = 0; j < 3; j++) begin: tmr
          TMR_voter_fail #(
          .VoterType ( VoterType )
          ) i_voter_fail (
          .a_i              ( multi_tmp[0][i]            ),
          .b_i              ( multi_tmp[1][i]            ),
          .c_i              ( multi_tmp[2][i]            ),
          .majority_o       ( multi_o[j][i]     ),
          .fault_detected_o ( fault_detected_mul[j][i] )
          );
      end
    end
    assign fault_detected_o = |fault_detected_mul;

  //if tripicated signal is single bit
  end else begin
    logic [2:0] fault_detected;
    logic [2:0] single_tmp;
    logic update;
    logic [2:0] d_in;

    assign update =  load_i || fault_detected_o;
    assign d_in =    load_i ? single_i : single_o;
    always_ff @(posedge (clk_i) or negedge (rst_ni)) begin
      if (!rst_ni) begin
        single_tmp <= ({3{single_reset_val_i}});
      end else begin
        if (update) begin
          single_tmp <= d_in;
        end
      end
    end
    for (genvar j = 0; j < 3; j++) begin: tmr
        TMR_voter_fail #(
        .VoterType ( VoterType )
        ) i_voter_fail (
        .a_i              ( single_tmp[0]            ),
        .b_i              ( single_tmp[1]            ),
        .c_i              ( single_tmp[2]            ),
        .majority_o       ( single_o[j]     ),
        .fault_detected_o ( fault_detected[j] )
        );
    end
    assign fault_detected_o = |fault_detected;
  end

endmodule