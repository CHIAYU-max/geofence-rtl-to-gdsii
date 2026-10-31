//================================================================================
// EXPERIMENT (2026-10-31, sweep/N_gon): the shift-sort design of geofence_new.v,
// geofence_ctrl.v and sort_new.v generalized to `RECV receivers (`RECV >= 4).
// One decision takes (N+1) load + 2(N-2)(N-1) sort + 2N check + 1 done cycles,
// which is 60 for N = 6. Not the submitted design.
//================================================================================
`ifndef RECV
`define RECV 6
`endif
module geofence (
    input   wire            clk,
    input   wire            reset,
    input   wire    [9:0]   X,
    input   wire    [9:0]   Y,
    output  reg             valid,
    output  reg             is_inside
);

    localparam integer N  = `RECV;
    localparam integer CW = $clog2(N + 1);

    localparam [CW-1:0]
        LOAD_LAST  = N,                 // 1 object + N receivers
        SORT_LAST  = N - 2,             // N-2 compares + 1 rotation per pass
        PASS_LAST  = N - 3,             // N-2 passes sort N-1 receivers
        CHECK_LAST = N - 1;             // N fence edges

    localparam [1:0]
        S0_LOAD  = 2'b00,
        S1_SORT  = 2'b01,
        S2_CHECK = 2'b10,
        S3_DONE  = 2'b11;

    reg     [1:0]       state_q;
    reg     [1:0]       next_state;
    reg     [CW-1:0]    step_q;
    reg     [CW-1:0]    pass_q;
    reg                 phase_q;

    wire    load_done  = (step_q == LOAD_LAST);
    wire    sort_rot   = (step_q == SORT_LAST);
    wire    sort_done  = phase_q && sort_rot && (pass_q == PASS_LAST);
    wire    check_done = phase_q && (step_q == CHECK_LAST);
    wire    load_en    = (state_q == S0_LOAD);
    wire    sort_en    = (state_q == S1_SORT) && phase_q;
    wire    check_en   = (state_q == S2_CHECK) && phase_q;
    wire    base_sel   = (state_q == S2_CHECK);
    wire    ccw;

    always @(posedge clk or posedge reset) begin
        if (reset) state_q <= S0_LOAD;
        else state_q <= next_state;
    end

    always @(*) begin
        next_state = state_q;
        case (state_q)
            S0_LOAD:  if (load_done) next_state = S1_SORT;
            S1_SORT:  if (sort_done) next_state = S2_CHECK;
            S2_CHECK: if (check_done) next_state = S3_DONE;
            S3_DONE:  next_state = S0_LOAD;
            default:  next_state = S0_LOAD;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            step_q  <= 0;
            pass_q  <= 0;
            phase_q <= 1'b0;
        end
        else begin
            case (state_q)
                S0_LOAD: begin
                    if (load_done) step_q <= 0;
                    else step_q <= step_q + 1'b1;
                end
                S1_SORT: begin
                    phase_q <= ~phase_q;
                    if (phase_q) begin
                        if (sort_rot) begin
                            step_q <= 0;
                            pass_q <= pass_q + 1'b1;
                        end
                        else step_q <= step_q + 1'b1;
                    end
                end
                S2_CHECK: begin
                    phase_q <= ~phase_q;
                    if (phase_q) begin
                        if (check_done) step_q <= 0;
                        else step_q <= step_q + 1'b1;
                    end
                end
                default: begin
                    step_q  <= 0;
                    pass_q  <= 0;
                    phase_q <= 1'b0;
                end
            endcase
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            valid     <= 1'b0;
            is_inside <= 1'b0;
        end
        else begin
            valid <= (next_state == S3_DONE);
            if (state_q == S1_SORT) is_inside <= 1'b1;
            else if (check_en && (!ccw)) is_inside <= 1'b0;
        end
    end

    // ----------------------------------------------------------------------
    // Coordinate registers
    reg     [19:0]  obj_q;
    reg     [19:0]  pt_q[0:N-1];

    wire            first_is_min = ccw || sort_rot;

    always @(posedge clk) begin
        if (load_en) obj_q <= pt_q[0];
    end

    always @(posedge clk) begin
        if (load_en || check_en) pt_q[0] <= pt_q[1];
    end

    always @(posedge clk) begin
        if (load_en || check_en) pt_q[1] <= pt_q[2];
        else if (sort_en && first_is_min) pt_q[1] <= pt_q[2];
    end

    genvar i;
    generate
        for (i = 2; i < N-1; i = i + 1) begin : g_shift
            always @(posedge clk) begin
                if (load_en || sort_en || check_en) pt_q[i] <= pt_q[i+1];
            end
        end
    endgenerate

    always @(posedge clk) begin
        if (load_en) pt_q[N-1] <= {X, Y};
        else if (check_en) pt_q[N-1] <= pt_q[0];
        else if (sort_en) begin
            if (first_is_min) pt_q[N-1] <= pt_q[1];
            else pt_q[N-1] <= pt_q[2];
        end
    end

    // ----------------------------------------------------------------------
    // Shared cross product unit, same as sort_new.v
    wire        [9:0]   base_x = base_sel ? obj_q[19:10] : pt_q[0][19:10];
    wire        [9:0]   base_y = base_sel ? obj_q[9:0] : pt_q[0][9:0];
    wire        [9:0]   end_x  = phase_q ? pt_q[2][19:10] : pt_q[1][19:10];
    wire        [9:0]   end_y  = phase_q ? pt_q[1][9:0] : pt_q[2][9:0];
    wire signed [10:0]  diff_x = {1'b0, end_x} - {1'b0, base_x};
    wire signed [10:0]  diff_y = {1'b0, end_y} - {1'b0, base_y};
    wire signed [20:0]  prod   = diff_x * diff_y;
    reg  signed [20:0]  prod_q;

    always @(posedge clk) begin
        prod_q <= prod;
    end

    assign ccw = (prod_q > prod);

endmodule
