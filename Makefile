SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

# Convenience targets (run from the repository root). Needs: iverilog, yosys, verilator
.PHONY: sim demo lint mutate lib synth wave clean
RTL = src/ped_crossing_ctrl.v
TB  = verification/tb_ped_crossing_ctrl.v

sim:
	mkdir -p sim
	iverilog -g2012 -Wall -o sim/tb.vvp $(RTL) $(TB)
	vvp sim/tb.vvp | tee verification/sim_log.txt

demo:   # readable timeline of state changes (short timing)
	mkdir -p sim
	iverilog -g2012 -o sim/demo.vvp $(RTL) verification/tb_demo.v
	vvp sim/demo.vvp | tee verification/demo_log.txt

wave:
	mkdir -p sim
	iverilog -g2012 -o sim/tb.vvp $(RTL) $(TB)
	vvp sim/tb.vvp +vcd
	gtkwave sim/ped_ctrl.vcd &

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module tt_um_ped_crossing_ctrl src/project.v src/ped_crossing_ctrl.v

mutate:
	bash verification/mutation_test.sh | tee verification/mutation_results.txt
	! grep -q -e SURVIVED -e 'DID NOT APPLY' verification/mutation_results.txt

LIBRAW = synthesis/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
LIBFLT = synthesis/lib/sky130_fd_sc_hd__tt_025C_1v80_filtered.lib
lib:   # download the Sky130 HD liberty file (12 MB, not stored in git) and drop dont_use cells
	mkdir -p synthesis/lib
	curl -sSL -o $(LIBRAW) https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
	python3 synthesis/filter_lib.py $(LIBRAW) $(LIBFLT)

synth: lib
	yosys -q -l synthesis/yosys_generic_log.txt synthesis/synth_generic.ys
	yosys -q -l synthesis/yosys_sky130_log.txt synthesis/synth_sky130.ys
	@grep -E "Number of cells|Chip area" synthesis/stat_generic.txt synthesis/stat_sky130.txt

clean:
	rm -rf sim
