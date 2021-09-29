// ECE511 MP2 Fall 2021
// Branch predictor testbench with example code snippets.
// Note that these are only example code for your reference, not a full testbench.
// You should write your own testbench.

`define SIM_VERBOSE

// Example of a parametrizable class
virtual class tbutilclass #(
  parameter IdxLen = 8
  );
  // Hash PC by taking the lowest TableIdxLen bits except last 2 bits
  static function hashIdx(input logic [31:0] addr);
    assert(IdxLen < 30);
    return addr[IdxLen+1:2];
  endfunction
endclass

`resetall
`timescale 1ns/10ps
module bp_example_tb ;

// Length of the branch trace used
parameter TraceLen = 50000;

// Instantiate the design under test
// *****************************************************************************
// Clock and reset
logic clk;
logic rst;

// Instantiate interface
bp_interface bp_itf();

bp_perceptron #(
) bp (
  .clk_i (clk ),
  .rst_ni(~rst),
  // Since we have an interface, we can normally just pass the interface
  // however, to keep the top level port naming consistent, we will match
  // the ports by name instead.
  // Instruction from fetch stage
  .fetch_rdata_i         (bp_itf.instr   ),
  .fetch_pc_i            (bp_itf.pc      ),
  .fetch_valid_i         (bp_itf.valid   ),
  // Prediction for supplied instruction
  .predict_branch_taken_o(bp_itf.taken   ),
  .predict_branch_pc_o   (bp_itf.target  ),
  // Prediction outcome after execution
  // (unused in this static predictor)
  .ex_br_instr_addr_i    (bp_itf.ex_pc   ),
  .ex_br_taken_i         (bp_itf.ex_taken),
  .ex_br_valid_i         (bp_itf.ex_valid)
);
// *****************************************************************************

// Useful tasks and functions
// *****************************************************************************
task reset_bp();
  $display("[INFO] %m: Resetting branch predictor at t = %0t", $time);
  @(posedge clk) rst = 1'b1;
  `ifdef SIM_VERBOSE
    $display("[INFO] %m: Reset is asserted at t = %0t", $time);
  `endif
  @(posedge clk) rst = 1'b0;
  `ifdef SIM_VERBOSE
    $display("[INFO] %m: Reset is de-asserted at t = %0t", $time);
  `endif
endtask
// *****************************************************************************

// Generate clock and reset
// *****************************************************************************
initial begin
  clk = 1;
  forever #1 clk = ~clk;
end

initial begin
  reset_bp();
end
// *****************************************************************************

// Read branch trace
// *****************************************************************************
logic [31:0] br_pc_trace    [TraceLen-1:0];
logic [31:0] br_instr_trace [TraceLen-1:0];
logic        br_taken_trace [TraceLen-1:0];
logic        br_pred        [TraceLen-1:0];

// Read trace to arrays
initial begin
  $dumpfile("bimodal.vcd"); 
  $dumpvars(0, bp_example_tb); 
  $readmemh("/home/kanungo3/ece511/MP2/branch_predictors/trace/br_pc_trace.txt",    br_pc_trace   );
  $readmemh("/home/kanungo3/ece511/MP2/branch_predictors/trace/br_instr_trace.txt", br_instr_trace);
  $readmemh("/home/kanungo3/ece511/MP2/branch_predictors/trace/br_taken_trace.txt", br_taken_trace);
end
// *****************************************************************************

// Feed branch trace to predictor
// *****************************************************************************
int cycle_cnt;
int trace_idx;
int total_correct;
int total_mispred;
real pred_accuracy;

initial begin
  cycle_cnt = 0;
  trace_idx = 0;
  total_correct = 0;
  total_mispred = 0;
  pred_accuracy = 0.0;
end

// Only feed branches every 4 cycles (assume the other 3 are regular instructions)
always @(posedge clk) begin
  // Stop simulation if we reach end of trace
  if (trace_idx < TraceLen) begin
    // Skip first 8 cycles due to reset
    if ((cycle_cnt > 7) && (cycle_cnt % 4 == 0)) begin
      bp_itf.pc       <= br_pc_trace[trace_idx];
      bp_itf.instr    <= br_instr_trace[trace_idx];
      bp_itf.valid    <= 1'b1;
      bp_itf.ex_pc    <= 32'b0;
      bp_itf.ex_taken <= 1'b0;
      bp_itf.ex_valid <= 1'b0;
    end
    else if ((cycle_cnt > 7) && (cycle_cnt % 4 == 1)) begin
      // Get prediction
      br_pred[trace_idx] <= bp_itf.taken;
      // Assert that branch is detected
      assert(bp.instr_b)
      else $error("[ERROR] %m: Branch instruction not detected at trace index %d", trace_idx);
      // Check if prediction is correct
      if (bp_itf.taken == br_taken_trace[trace_idx]) begin
        total_correct <= total_correct + 1;
        `ifdef SIM_VERBOSE
          $display("[INFO] %m: Correctly predicted branch at trace index %d", trace_idx);
        `endif
      end
      else begin
        total_mispred <= total_mispred + 1;
        `ifdef SIM_VERBOSE
          $display("[INFO] %m: Incorrectly predicted branch at trace index %d", trace_idx);
        `endif
      end
    end
    // Feed branch outcome 2 cycles later
    else if ((cycle_cnt > 7) && (cycle_cnt % 4 == 2)) begin
      bp_itf.pc       <= 32'b0;
      bp_itf.instr    <= 32'b0;
      bp_itf.valid    <= 1'b0;
      bp_itf.ex_pc    <= br_pc_trace[trace_idx];
      bp_itf.ex_taken <= br_taken_trace[trace_idx];
      bp_itf.ex_valid <= 1'b1;
      // Increment trace index
      trace_idx = trace_idx + 1;
    end
    else begin
      bp_itf.pc       <= 32'b0;
      bp_itf.instr    <= 32'b0;
      bp_itf.valid    <= 1'b0;
      bp_itf.ex_pc    <= 32'b0;
      bp_itf.ex_taken <= 1'b0;
      bp_itf.ex_valid <= 1'b0;
    end
    // Increment cycle
    cycle_cnt = cycle_cnt + 1;
  end
  else begin
    // Print final statistics
    $display("[STAT] %m: Total correct: %0d Total mispredicted: %0d", total_correct, total_mispred);
    $display("[STAT] %m: Prediction accuracy: %f", real'(total_correct) / real'(TraceLen));
    $display("[INFO] %m: Ending simulation");
    $stop();
    $finish;
  end
end
// *****************************************************************************

endmodule
