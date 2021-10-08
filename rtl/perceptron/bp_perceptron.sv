import ibex_pkg::*;
module bp_perceptron#(
  parameter int unsigned PTableSize = 1024,
  parameter int unsigned PWeightLen = 9,
  parameter int unsigned GHRLen = 12)
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

  logic signed [PWeightLen-1:0] ptable_w [PTableSize-1:0] [GHRLen-1:0]; 
  logic signed [PWeightLen-1:0] ptable_b [PTableSize-1:0];

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

  logic [$clog2(PTableSize)-1:0] update_index;
  logic [$clog2(PTableSize)-1:0] pred_index;
  logic [GHRLen-1:0] GHR;


  // Provide short internal name for fetch_rdata_i due to reduce line wrapping
  assign instr = fetch_rdata_i;

  //Signals to break down confitions
  logic overflow_taken, overflow_not_taken;
  logic signed [PWeightLen*2-3:0] br_taken;
  logic signed [PWeightLen*2-3:0] yout [1:0];
  logic signed [PWeightLen*2-3:0] yout_mag,yout_mag2;
  logic signed [PWeightLen*2-3:0] theta;


  // assign theta = $ceil(1.93*GHRLen + 14);
  // assign theta = 'd38;
  assign theta = 'd30;
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
  assign pred_index = fetch_pc_i[$clog2(PTableSize)+1:2];
  assign predict_branch_taken_o = fetch_valid_i & (instr_j | instr_cj | ( ~(br_taken[PWeightLen*2-3]) & (instr_b | instr_cb)));
  assign predict_branch_pc_o    = fetch_pc_i + branch_imm;

  always_comb begin
    br_taken = ptable_b[pred_index];
    for(int j=0; j<GHRLen; j++) begin
      br_taken += GHR[j] ? ptable_w[pred_index][j] : ((~ptable_w[pred_index][j])+1) ;
    end
    yout_mag2 = ptable_b[update_index];
    for(int j=0; j<GHRLen; j++) begin
      yout_mag2 += GHR[j] ? ptable_w[update_index][j] : ((~ptable_w[update_index][j])+1) ;
    end
  end

  //Shift register to store the value of yout
  always_ff @(posedge clk_i) begin
    if(!rst_ni) begin
      yout[0] <= '0;
      yout[1] <= '0;
    end
    else begin
      yout[0] <= br_taken;
      yout[1] <= yout[0];
    end
  end
  assign yout_mag = yout_mag2[PWeightLen*2-3] ? ((~yout_mag2)+1) : yout_mag2;

  //Update Logic
  assign update_index = ex_br_instr_addr_i[$clog2(PTableSize)+1:2];
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      GHR <= '0;
      for(int i = 0; i<PTableSize; i++) begin
        ptable_b[i] <= '0;
        for(int k = 0; k<GHRLen; k++)
          ptable_w[i][k] <= '0;
      end
    end
    else begin
      if(ex_br_valid_i) begin
        GHR <= {GHR[GHRLen-2:0], ex_br_taken_i};
        if(~ex_br_taken_i != yout_mag2[PWeightLen*2-3] || yout_mag<theta) begin
        // if(1) begin
          overflow_taken = &ptable_b[update_index][PWeightLen-2:0] & ~ptable_b[update_index][PWeightLen-1];
          overflow_not_taken = &(~(ptable_b[update_index][PWeightLen-2:0])) & ptable_b[update_index][PWeightLen-1];
          ptable_b[update_index] <= ex_br_taken_i ? (overflow_taken ? ptable_b[update_index] : ptable_b[update_index] + 1) : (overflow_not_taken ? ptable_b[update_index] : ptable_b[update_index] - 1);
          for(int m=0; m<GHRLen; m++) begin
            overflow_taken = &ptable_w[update_index][m][PWeightLen-2:0] & ~ptable_w[update_index][m][PWeightLen-1];
            overflow_not_taken = &(~(ptable_w[update_index][m][PWeightLen-2:0])) & ptable_w[update_index][m][PWeightLen-1];
            ptable_w[update_index][m] <= (ex_br_taken_i == GHR[m]) ? (overflow_taken ? ptable_w[update_index][m] : ptable_w[update_index][m] + 1) : (overflow_not_taken ? ptable_w[update_index][m] : ptable_w[update_index][m] - 1);
          end
        end
      end
    end
  end



endmodule
