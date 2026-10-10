# Results (every number below comes from a tool run; source file in brackets)

Design: `ped_crossing_ctrl` wrapped as `tt_um_ped_crossing_ctrl`. Flow: Tiny Tapeout GitHub Action `ttsky26d`
(LibreLane: Yosys, OpenROAD, Magic, KLayout, Netgen, Verilator) on the SkyWater **sky130A** PDK, run on GitHub Actions.
These are **post-layout, pre-silicon** results. No chip was fabricated or measured.

## 1. Functional verification (Icarus Verilog 12.0, run on GitHub Actions `verify` and locally)

| Item | Result | Source |
|---|---|---|
| Self-checking testbench | 400,038 checks, 0 errors | `verification/sim_log.txt` |
| Bug-injection (mutation) test | 16 / 16 injected bugs detected | `verification/mutation_results.txt` |
| Wrapper cocotb tests (RTL) | 6 / 6 pass | `test/` |
| Verilator `-Wall` lint of the RTL | clean | `make lint` |
| Production-timing smoke test | start-up all-red = 20,000,000 clocks (2 s at 10 MHz) | `verification/tb_fullsize_smoke.v` |
| Gate-level simulation of the final netlist | pass (checks reset/start-up state only) | Actions `gl_test` |

## 2. Synthesis

| Item | Standalone Yosys run (`synthesis/`) | Chip flow (Tiny Tapeout wrapper) |
|---|---|---|
| Cells | 177 (`stat_sky130.txt`) | 195 (`physical_design/reports/synthesis-stats.txt`) |
| Flip-flops | 39 | 39 (`dfrtp_2`), 45.8 % of synthesized cell area |
| Cell area | 1796.7 µm² | 2237.1 µm² |
| Latches | 0 | 0 |

The two runs differ because the flow uses different cell drive strengths, adds tie cells for the constant outputs
(13 `conb` cells) and includes the wrapper. **Use the chip-flow numbers for the chip.**
The 39 flip-flops are: 3 state, 24 prescaler, 6 tick counter, 3 + 2 input synchronizers, 1 request latch.

## 3. Physical design (final run) [`physical_design/reports/final_metrics.json`]

| Item | Result |
|---|---|
| Die size | 161.0 × 111.52 µm (one Tiny Tapeout 1×1 tile, ≈ 17,955 µm²) |
| Standard cells placed | 453 instances: 39 sequential, 134 multi-input combinational, 14 inverters, 8 buffers, 10 clock buffers, 23 timing-repair buffers (7 hold buffers), 225 tap cells; plus 3,757 fill cells |
| Standard-cell area | 2966.6 µm² (includes tap cells and clock buffers) |
| Utilisation | 18.0 % standard-cell (final metrics); 15.8 % shown in the Actions routing summary (different point in the flow) |
| Routing | 246 nets, wire length 4376 µm |
| Clock constraint used by the flow | 20 ns (50 MHz), input/output delay 4 ns, uncertainty 0.25 ns [`constraints.sdc`] |
| Worst setup slack | **+8.36 ns** (slowest corner `ss_100C_1v60`); +13.9 ns at typical `tt_025C_1v80` |
| Worst hold slack | **+0.123 ns** (fastest corner `ff_n40C_1v95`) |
| Setup / hold violations | **0 / 0** in all 9 corners (3 PVT × min/nom/max) |
| Max slew / cap / fanout violations | 0 / 0 / 0 |
| Estimated power | 231 µW total (internal 186 µW, switching 45 µW, leakage 16 nW) — static estimate from the flow's default activity, **not measured** |
| Worst IR drop | 37 µV |

Our own design target is a 10 MHz clock (100 ns period). The flow checked it against the stricter 50 MHz constraint above, so
this result says timing is met with positive slack at 50 MHz; it does **not** say 50 MHz is the maximum frequency.

## 4. Sign-off style checks

| Check | Result | Source |
|---|---|---|
| Magic DRC | 0 errors | `final_metrics.json`, precheck |
| KLayout DRC checks (FEOL, BEOL, off-grid, zero-area, pin-label, nwell/urpm) | pass | `precheck_results.md` |
| LVS (Netgen) | "Circuits match uniquely", 0 errors | `lvs.netgen.rpt` |
| Antenna | 0 violating nets / pins | `final_metrics.json` |
| Tiny Tapeout precheck | 15 / 15 checks pass | `precheck_results.md` |
| Verilator lint inside the flow | 0 errors, 0 warnings | `final_metrics.json` |
| Flow errors | 0 (a few informational tool warnings are in the logs) | `final_metrics.json` |
| Disconnected pins | 15, 0 critical: the unused inputs `ena`, `ui_in[7:2]`, `uio_in[7:0]` | flow log |

## 5. Deliverables

* Final layout: `physical_design/tt_um_ped_crossing_ctrl.gds` (1,091,980 bytes), abstract `…lef`, final netlist.
* Layout picture: `physical_design/gds_render.png`.
* All reports: `physical_design/reports/`.

## 6. What these results do NOT show

Simulation and the checks above do not prove the design works for every possible input sequence (formal verification would be the next step),
do not include metastability (MTBF) analysis of the synchronizers, and are not silicon measurements. Power is an estimate.
This is an educational controller, not suitable for real traffic infrastructure.
