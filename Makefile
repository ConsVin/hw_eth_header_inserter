SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl

VHDL_SOURCES += $(PWD)/vhd/byte_arr_pkg.rtl.vhd\
				$(PWD)/vhd/eth_header.rtl.vhd \
				

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = eth_header

# MODULE is the basename of the Python test file
MODULE = test_eth_header
# SIM_ARGS ?= --vcd=waveform.vcd
SIM_ARGS ?= --wave=waveform.ghw 


# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim