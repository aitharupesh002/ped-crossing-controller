`timescale 1ns/1ps
// Human-readable demo: prints every state change with the clock count and lamp outputs.
// Short timing (1 tick = 4 clocks): GREEN(min)=20, YELLOW=8, ALLRED1=12, WALK=16, CLEAR=20, ALLRED2=8 clocks.
module tb_demo;
    reg clk = 0, rst_n = 0, ped_req = 0, emergency_req = 0;
    wire vr, vy, vg, pw, pc, ps, pwait, eact; wire [2:0] st;
    ped_crossing_ctrl #(.CLK_DIV(4), .PRE_W(3), .T_GREEN(5), .T_YELLOW(2), .T_ALLRED1(3),
                        .T_WALK(4), .T_CLEAR(5), .T_ALLRED2(2)) dut (
        .clk(clk), .rst_n(rst_n), .ped_req(ped_req), .emergency_req(emergency_req),
        .vehicle_red(vr), .vehicle_yellow(vy), .vehicle_green(vg), .ped_walk(pw), .ped_clear(pc),
        .ped_stop(ps), .ped_wait(pwait), .emergency_active(eact), .state_dbg(st));
    always #5 clk = ~clk;

    integer cycle = 0, last_change = 0;
    reg [2:0] prev = 3'd7;
    always @(negedge clk) begin
        cycle = cycle + 1;
        if (st !== prev) begin
            $display("clock %4d | now %-8s | previous state lasted %3d clocks | veh R%0d Y%0d G%0d | ped WALK%0d CLEAR%0d STOP%0d | WAIT%0d EMERG%0d",
                cycle, name(st), cycle - last_change, vr, vy, vg, pw, pc, ps, pwait, eact);
            prev = st; last_change = cycle;
        end
    end
    function [8*8-1:0] name(input [2:0] s);
        case (s) 0: name = "ALLRED2"; 1: name = "GREEN"; 2: name = "YELLOW"; 3: name = "ALLRED1";
                 4: name = "WALK"; 5: name = "CLEAR"; default: name = "ILLEGAL"; endcase
    endfunction
    task note(input [8*100-1:0] s); begin $display("\n>>> %0s", s); end endtask
    task show(input [8*60-1:0] s);
        begin $display("clock %4d | %0s: state=%0s WAIT=%0d EMERG=%0d", cycle, s, name(st), pwait, eact); end
    endtask
    task wait_clocks(input integer n); begin repeat (n) @(negedge clk); end endtask
    task press; begin @(negedge clk); #2 ped_req = 1; wait_clocks(1); #2 ped_req = 0; end endtask

    initial begin
        note("RESET: expect ALLRED2 (all red, ped STOP)");
        wait_clocks(3); rst_n = 1;
        wait_clocks(40);
        note("PEDESTRIAN PRESSES BUTTON after minimum green: expect WAIT=1, then Y, AR1, WALK(WAIT clears), CLEAR, AR2, GREEN");
        press;
        wait_clocks(110);
        note("EMERGENCY HELD + pedestrian button: expect GREEN is HELD, WAIT stays 1");
        @(negedge clk); #2 emergency_req = 1;
        wait_clocks(3); press;
        wait_clocks(60);
        show("GREEN held, no state change");
        note("EMERGENCY RELEASED: expect pending request now served (YELLOW ...)");
        @(negedge clk); #2 emergency_req = 0;
        wait_clocks(100);
        note("EMERGENCY DURING WALK: expect WALK ends early -> CLEAR (full 20 clocks) -> ALLRED2 -> GREEN");
        press;
        while (st != 3'd4) @(negedge clk);       // wait until WALK has started
        wait_clocks(3);
        @(negedge clk); #2 emergency_req = 1;
        wait_clocks(60);
        @(negedge clk); #2 emergency_req = 0;
        wait_clocks(20);
        $display("\nDemo finished."); $finish;
    end
endmodule
