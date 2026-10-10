// -----------------------------------------------------------------------------
// ped_crossing_ctrl.v
// Demand-responsive pedestrian crossing controller with safe emergency
// preemption. EDUCATIONAL DESIGN - not suitable for real traffic infrastructure.
//
// Single clock domain. Asynchronous-assert active-low reset (rst_n). Reset
// de-assertion is assumed to be synchronous to clk (no reset synchronizer).
//
// Phase durations are counted in "ticks"; one tick = CLK_DIV clock cycles.
//   Each timed phase lasts exactly  T_xxx * CLK_DIV  clock cycles.
//   VEH_GREEN is a *minimum* green: it lasts at least T_GREEN * CLK_DIV cycles.
// -----------------------------------------------------------------------------
module ped_crossing_ctrl #(
    parameter integer CLK_DIV   = 10_000_000, // clk cycles per tick (10 MHz -> 1 s)
    parameter integer PRE_W     = 24,         // prescaler width, must hold CLK_DIV-1
    parameter integer T_GREEN   = 20,         // minimum vehicle green (ticks)
    parameter integer T_YELLOW  = 3,
    parameter integer T_ALLRED1 = 2,          // all-red before WALK
    parameter integer T_WALK    = 7,
    parameter integer T_CLEAR   = 10,         // pedestrian clearance
    parameter integer T_ALLRED2 = 2           // all-red before vehicles resume
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ped_req,        // asynchronous push button
    input  wire       emergency_req,  // asynchronous emergency-preemption request

    output wire       vehicle_red,
    output wire       vehicle_yellow,
    output wire       vehicle_green,
    output wire       ped_walk,
    output wire       ped_clear,      // pedestrian clearance: do not start, finish crossing
    output wire       ped_stop,
    output wire       ped_wait,       // request registered, waiting for WALK
    output wire       emergency_active, // synchronized emergency request is asserted
    output wire [2:0] state_dbg
);

    // ---------------------------------------------------------------- states
    localparam [2:0] S_ALLRED2 = 3'd0;  // reset state: all red, then vehicle green
    localparam [2:0] S_GREEN   = 3'd1;
    localparam [2:0] S_YELLOW  = 3'd2;
    localparam [2:0] S_ALLRED1 = 3'd3;
    localparam [2:0] S_WALK    = 3'd4;
    localparam [2:0] S_CLEAR   = 3'd5;
    // 3'd6 and 3'd7 are illegal -> recover to S_ALLRED2

    reg [2:0] state, state_next;

    // ------------------------------------------------- input synchronizers
    reg ped_s1, ped_s2, ped_s3;   // s3 = previous value, for rising-edge detect
    reg em_s1,  em_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ped_s1 <= 1'b0; ped_s2 <= 1'b0; ped_s3 <= 1'b0;
            em_s1  <= 1'b0; em_s2  <= 1'b0;
        end else begin
            ped_s1 <= ped_req;  ped_s2 <= ped_s1;  ped_s3 <= ped_s2;
            em_s1  <= emergency_req; em_s2 <= em_s1;
        end
    end

    wire ped_rise = ped_s2 & ~ped_s3;   // one pulse per button press
    wire emerg    = em_s2;              // level request

    // ---------------------------------------------------- prescaler + timer
    reg [PRE_W-1:0] pre;
    reg [5:0]       cnt;                // ticks elapsed in the current state (saturates at 63)

    localparam [PRE_W-1:0] PRE_LAST = CLK_DIV[PRE_W-1:0] - 1'b1;  // last prescaler count of a tick
    wire tick = (pre == PRE_LAST);

    reg [5:0] dur;                      // duration of the current timed state
    always @(*) begin
        case (state)
            S_YELLOW:  dur = T_YELLOW[5:0];
            S_ALLRED1: dur = T_ALLRED1[5:0];
            S_WALK:    dur = T_WALK[5:0];
            S_CLEAR:   dur = T_CLEAR[5:0];
            default:   dur = T_ALLRED2[5:0];
        endcase
    end

    wire phase_done = tick && (cnt == dur - 6'd1);
    wire green_met  = (cnt >= T_GREEN[5:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pre <= {PRE_W{1'b0}};
            cnt <= 6'd0;
        end else if (state_next != state) begin
            pre <= {PRE_W{1'b0}};       // every phase starts with a fresh tick
            cnt <= 6'd0;
        end else begin
            pre <= tick ? {PRE_W{1'b0}} : pre + 1'b1;
            if (tick && cnt != 6'd63) cnt <= cnt + 6'd1;
        end
    end

    // ------------------------------------------------ pedestrian request latch
    reg ped_pending;
    wire in_walk_or_clear = (state == S_WALK) || (state == S_CLEAR);
    wire start_walk       = (state == S_ALLRED1) && (state_next == S_WALK);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                          ped_pending <= 1'b0;
        else if (start_walk)                 ped_pending <= 1'b0;  // clear wins over set
        else if (ped_rise && !in_walk_or_clear) ped_pending <= 1'b1;
    end

    // ------------------------------------------------------------ next state
    always @(*) begin
        state_next = state;
        case (state)
            S_GREEN:   if (ped_pending && !emerg && green_met) state_next = S_YELLOW;
            S_YELLOW:  if (phase_done) state_next = S_ALLRED1;
            S_ALLRED1: if (phase_done) state_next = emerg ? S_GREEN : S_WALK;
            S_WALK:    if (emerg || phase_done) state_next = S_CLEAR;
            S_CLEAR:   if (phase_done) state_next = S_ALLRED2;
            S_ALLRED2: if (phase_done) state_next = S_GREEN;
            default:   state_next = S_ALLRED2;   // illegal-state recovery
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_ALLRED2;
        else        state <= state_next;
    end

    // ---------------------------------------------- Moore outputs (all states)
    reg v_r, v_y, v_g, p_w, p_c, p_s;
    always @(*) begin
        // default: everything red / stop (also used for illegal states)
        v_r = 1'b1; v_y = 1'b0; v_g = 1'b0;
        p_w = 1'b0; p_c = 1'b0; p_s = 1'b1;
        case (state)
            S_GREEN:  begin v_r = 1'b0; v_g = 1'b1; end
            S_YELLOW: begin v_r = 1'b0; v_y = 1'b1; end
            S_WALK:   begin p_w = 1'b1; p_s = 1'b0; end
            S_CLEAR:  begin p_c = 1'b1; p_s = 1'b0; end
            default:  ;  // S_ALLRED1, S_ALLRED2, illegal: all red, ped stop
        endcase
    end

    assign vehicle_red      = v_r;
    assign vehicle_yellow   = v_y;
    assign vehicle_green    = v_g;
    assign ped_walk         = p_w;
    assign ped_clear        = p_c;
    assign ped_stop         = p_s;
    assign ped_wait         = ped_pending;
    assign emergency_active = emerg;
    assign state_dbg        = state;

endmodule
