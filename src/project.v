/*
 * Pedestrian crossing controller with safe emergency preemption
 * Tiny Tapeout wrapper around ped_crossing_ctrl (EDUCATIONAL DESIGN)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ped_crossing_ctrl (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

`ifdef FAST_SIM
    // Short timing for RTL simulation only: 1 tick = 4 clocks
    localparam integer CLK_DIV = 4;
    localparam integer PRE_W   = 3;
`else
    // Real timing: 10 MHz clock -> 1 tick = 1 second
    localparam integer CLK_DIV = 10_000_000;
    localparam integer PRE_W   = 24;
`endif

    wire       vehicle_red, vehicle_yellow, vehicle_green;
    wire       ped_walk, ped_clear, ped_stop, ped_wait, emergency_active;
    wire [2:0] state_dbg;

    ped_crossing_ctrl #(
        .CLK_DIV  (CLK_DIV),
        .PRE_W    (PRE_W),
        .T_GREEN  (20),
        .T_YELLOW (3),
        .T_ALLRED1(2),
        .T_WALK   (7),
        .T_CLEAR  (10),
        .T_ALLRED2(2)
    ) u_ctrl (
        .clk             (clk),
        .rst_n           (rst_n),
        .ped_req         (ui_in[0]),
        .emergency_req   (ui_in[1]),
        .vehicle_red     (vehicle_red),
        .vehicle_yellow  (vehicle_yellow),
        .vehicle_green   (vehicle_green),
        .ped_walk        (ped_walk),
        .ped_clear       (ped_clear),
        .ped_stop        (ped_stop),
        .ped_wait        (ped_wait),
        .emergency_active(emergency_active),
        .state_dbg       (state_dbg)
    );

    assign uo_out  = {emergency_active, ped_wait, ped_stop, ped_clear,
                      ped_walk, vehicle_green, vehicle_yellow, vehicle_red};

    // uio[2:0] = FSM state (debug), all other bidirectional pins are inputs
    assign uio_out = {5'b00000, state_dbg};
    assign uio_oe  = 8'b0000_0111;

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, ui_in[7:2], uio_in, 1'b0};

endmodule
