// ECE511 MP2 Fall 2021
// Example interface to branch predictor.

`resetall
`timescale 1ns/10ps
interface bp_interface;
  logic [31:0] pc;
  logic [31:0] instr;
  logic        valid;
  logic        taken;
  logic [31:0] target;
  logic [31:0] ex_pc;
  logic        ex_taken;
  logic        ex_valid;
endinterface
