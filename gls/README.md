# Gate-level simulation (GLS): RTL vs synthesised netlist

- `synth_short.ys`: synthesises the same RTL with the short simulation timing (1 tick = 4 clocks) using Yosys' generic gates.
- `ped_short_netlist.v` / `ped_gls.v`: the resulting gate-level netlist (module renamed `ped_gls`).
- `tb_rtl_vs_gls.v`: runs the same stimulus on RTL and netlist and compares every output at every clock.
- `rtl_vs_gls_log.txt`: result. 432 clock samples compared, 0 mismatches.
- `make_waveforms.py` draws `images/RTL_waveform.png` and `images/GLS_waveform.png` from the simulation VCD (matplotlib, not GTKWave).

Limits: this GLS uses Yosys generic gates with zero delay, not the Sky130 cells with timing. It shows the synthesis step preserved the behaviour for this stimulus only.
Run: `yosys -q gls/synth_short.ys && sed 's/^module ped_crossing_ctrl(/module ped_gls(/' gls/ped_short_netlist.v > gls/ped_gls.v && iverilog -o gls/rg.vvp gls/tb_rtl_vs_gls.v src/ped_crossing_ctrl.v gls/ped_gls.v && vvp gls/rg.vvp`
