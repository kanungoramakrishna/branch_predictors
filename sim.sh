#!/bin/bash

rm -rf simv.daidir
rm simv
vcs -sverilog rtl/bp_example_tb.sv rtl/ibex_pkg.sv rtl/bp_interface.sv rtl/$1/*.sv