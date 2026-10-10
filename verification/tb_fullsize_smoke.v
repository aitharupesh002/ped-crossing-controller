`timescale 1ns/1ps
// Smoke test with the PRODUCTION parameters (10 MHz clock, 1 tick = 1 s):
// after reset the start-up all-red phase must last exactly T_ALLRED2*CLK_DIV = 20,000,000 clocks.
module tb_fullsize_smoke;
    reg clk = 0, rst_n = 0;
    wire vr, vy, vg, pw, pc, ps, pwait, eact; wire [2:0] st;
    ped_crossing_ctrl dut(.clk(clk), .rst_n(rst_n), .ped_req(1'b0), .emergency_req(1'b0),
        .vehicle_red(vr), .vehicle_yellow(vy), .vehicle_green(vg), .ped_walk(pw), .ped_clear(pc),
        .ped_stop(ps), .ped_wait(pwait), .emergency_active(eact), .state_dbg(st));
    always #5 clk = ~clk;
    integer n = 0;
    initial begin
        repeat (3) @(negedge clk);
        #1 rst_n = 1;
        while (st != 3'd1) begin @(negedge clk); n = n + 1; end
        $display("start-up all-red lasted %0d clocks (expected 20000000)", n);
        if (n == 20000000 && vg && ps) $display("SMOKE TEST PASSED"); else $display("SMOKE TEST FAILED");
        $finish;
    end
endmodule
