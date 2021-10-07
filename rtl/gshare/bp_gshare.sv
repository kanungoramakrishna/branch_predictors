import ibex_pkg::*;
module bp_gshare#(
  parameter int unsigned CTableSize = 1024,
  parameter int unsigned CounterLen = 2,
  parameter int unsigned GHRLen = 10)
  (
  input  logic clk_i,
  input  logic rst_ni,

  // Instruction from fetch stage
  input  logic [31:0] fetch_rdata_i,
  input  logic [31:0] fetch_pc_i,
  input  logic        fetch_valid_i,

  // Prediction for supplied instruction
  output logic        predict_branch_taken_o,
  output logic [31:0] predict_branch_pc_o,

  input  logic [31:0] ex_br_instr_addr_i,
  input  logic ex_br_taken_i,
  input  logic ex_br_valid_i
);

  logic signed [CounterLen-1:0] ctable [CTableSize-1:0];

  //immediates
  logic [31:0] imm_j_type;
  logic [31:0] imm_b_type;
  logic [31:0] imm_cj_type;
  logic [31:0] imm_cb_type;

  logic [31:0] branch_imm;
  logic [31:0] instr;

  logic instr_j;
  logic instr_b;
  logic instr_cj;
  logic instr_cb;

  logic [$clog2(CTableSize)-1:0] update_index;
  logic [$clog2(CTableSize)-1:0] pred_index;
  logic signed [CounterLen-1:0] counter_next;
  logic [GHRLen-1:0] GHR;


  // Provide short internal name for fetch_rdata_i due to reduce line wrapping
  assign instr = fetch_rdata_i;

  //Signals to break down confitions
  logic overflow_taken, overflow_not_taken, br_taken;



  // Uncompressed immediates
  assign imm_j_type = { {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0 };
  assign imm_b_type = { {19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0 };

  // Compressed immediates
  assign imm_cj_type = { {20{instr[12]}}, instr[12], instr[8], instr[10:9], instr[6], instr[7],
    instr[2], instr[11], instr[5:3], 1'b0 };

  assign imm_cb_type = { {23{instr[12]}}, instr[12], instr[6:5], instr[2], instr[11:10],
    instr[4:3], 1'b0};

  // Uncompressed branch/jump
  assign instr_b = opcode_e'(instr[6:0]) == OPCODE_BRANCH;
  assign instr_j = opcode_e'(instr[6:0]) == OPCODE_JAL;

  // Compressed branch/jump
  assign instr_cb = (instr[1:0] == 2'b01) & ((instr[15:13] == 3'b110) | (instr[15:13] == 3'b111));
  assign instr_cj = (instr[1:0] == 2'b01) & ((instr[15:13] == 3'b101) | (instr[15:13] == 3'b001));

  always_comb begin
    branch_imm = imm_b_type;

    unique case (1'b1)
      instr_j  : branch_imm = imm_j_type;
      instr_b  : branch_imm = imm_b_type;
      instr_cj : branch_imm = imm_cj_type;
      instr_cb : branch_imm = imm_cb_type;
      default : ;
    endcase
  end

  //Prediction logic
  assign pred_index = fetch_pc_i[GHRLen +1:2] ^ GHR;
  assign br_taken = ~ctable[pred_index][CounterLen-1];
  assign predict_branch_taken_o = fetch_valid_i & (instr_j | instr_cj | ( br_taken & (instr_b | instr_cb)));
  assign predict_branch_pc_o    = fetch_pc_i + branch_imm;


  //Update Logic
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      GHR <= '0;
      for(int i = 0; i<CTableSize; i++)
        ctable[i] <= 0;
    end
    else begin
      ctable[update_index] <= counter_next;
      if(ex_br_valid_i)
        GHR <= {GHR[GHRLen-2:0], ex_br_taken_i};
    end
  end

  always_comb begin
    update_index = ex_br_instr_addr_i[GHRLen+1:2] ^ GHR;
    counter_next = ctable[update_index];
    overflow_taken = &ctable[update_index][CounterLen-2:0] & ~ctable[update_index][CounterLen-1];
    overflow_not_taken = &(~(ctable[update_index][CounterLen-2:0])) & ctable[update_index][CounterLen-1];
    if(ex_br_valid_i) begin
      if(ex_br_taken_i)
        counter_next = overflow_taken? (ctable[update_index]) : (ctable[update_index] + 1);
      else
        counter_next = overflow_not_taken ? (ctable[update_index]) : (ctable[update_index] - 1);
    end
  end


endmodule
