`timescale 1ns/1ps
// Runs the SAME stimulus on the RTL and on the Yosys gate-level netlist (short timing) and compares
// every output at every clock. Stimulus = the demo scenario (reset, pedestrian cycle, emergency hold, emergency in WALK).
module tb_rtl_vs_gls;
    reg clk = 0, rst_n = 0, ped_req = 0, emergency_req = 0;
    wire [10:0] r, g; wire [2:0] rst_, gst;
    wire r_vr,r_vy,r_vg,r_pw,r_pc,r_ps,r_wait,r_em; wire [2:0] r_st;
    wire g_vr,g_vy,g_vg,g_pw,g_pc,g_ps,g_wait,g_em; wire [2:0] g_st;
    ped_crossing_ctrl #(.CLK_DIV(4), .PRE_W(3), .T_GREEN(5), .T_YELLOW(2), .T_ALLRED1(3),
                        .T_WALK(4), .T_CLEAR(5), .T_ALLRED2(2)) rtl (
        .clk(clk), .rst_n(rst_n), .ped_req(ped_req), .emergency_req(emergency_req),
        .vehicle_red(r_vr), .vehicle_yellow(r_vy), .vehicle_green(r_vg), .ped_walk(r_pw), .ped_clear(r_pc),
        .ped_stop(r_ps), .ped_wait(r_wait), .emergency_active(r_em), .state_dbg(r_st));
    ped_gls gls (
        .clk(clk), .rst_n(rst_n), .ped_req(ped_req), .emergency_req(emergency_req),
        .vehicle_red(g_vr), .vehicle_yellow(g_vy), .vehicle_green(g_vg), .ped_walk(g_pw), .ped_clear(g_pc),
        .ped_stop(g_ps), .ped_wait(g_wait), .emergency_active(g_em), .state_dbg(g_st));
    always #5 clk = ~clk;

    integer cycle = 0, checks = 0, errors = 0;
    always @(negedge clk) begin
        cycle = cycle + 1;
        checks = checks + 1;
        if ({r_vr,r_vy,r_vg,r_pw,r_pc,r_ps,r_wait,r_em,r_st} !== {g_vr,g_vy,g_vg,g_pw,g_pc,g_ps,g_wait,g_em,g_st}) begin
            errors = errors + 1;
            if (errors < 10) $display("MISMATCH clock %0d: RTL st=%0d GLS st=%0d", cycle, r_st, g_st);
        end
    end
    task wait_clocks(input integer n); begin repeat (n) @(negedge clk); end endtask
    task press; begin @(negedge clk); #2 ped_req = 1; wait_clocks(1); #2 ped_req = 0; end endtask
    initial begin
        $dumpfile("gls/rtl_vs_gls.vcd"); $dumpvars(0, tb_rtl_vs_gls);
        wait_clocks(3); rst_n = 1;
        wait_clocks(40);
        press; wait_clocks(110);
        @(negedge clk); #2 emergency_req = 1; wait_clocks(3); press; wait_clocks(60);
        @(negedge clk); #2 emergency_req = 0; wait_clocks(100);
        press; while (r_st != 3'd4) @(negedge clk);
        wait_clocks(3); @(negedge clk); #2 emergency_req = 1; wait_clocks(60);
        @(negedge clk); #2 emergency_req = 0; wait_clocks(20);
        $display("RTL vs GLS: %0d clock samples compared, %0d mismatches -> %0s", checks, errors, errors==0 ? "PASS" : "FAIL");
        $finish;
    end
endmodule
