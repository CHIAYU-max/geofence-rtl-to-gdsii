//================================================================================
// EXPERIMENT (2026-10-26, sweep/M_serial): copy of geofence_ctrl.v for the
// serial multiplier. Not the submitted design; the original is unchanged.
//
// Changes from geofence_ctrl.v:
//    1. New input mul_done, new output mul_run (high in S1_SORT / S2_CHECK)
//    2. In SORT / CHECK the phase toggles and the step advances only when
//       mul_done is high, so every phase lasts 12 cycles instead of 1
//================================================================================
module geofence_ctrl (
    input   wire            clk,
    input   wire            reset,
    input   wire            ccw,
    input   wire            mul_done,   // High : product ready
    output  wire            load_en,
    output  wire            sort_en,
    output  wire            sort_rot,
    output  wire            check_en,
    output  wire            base_sel,
    output  wire            phase,
    output  wire            mul_run,    // High : multiplier runs
    output  reg             valid,
    output  reg             is_inside
);

    localparam [1:0]
        S0_LOAD  = 2'b00,
        S1_SORT  = 2'b01,
        S2_CHECK = 2'b10,
        S3_DONE  = 2'b11;

    localparam [2:0]
        LOAD_LAST  = 3'd6,
        SORT_LAST  = 3'd4,
        CHECK_LAST = 3'd5;
    localparam [1:0]
        PASS_LAST  = 2'd3;

    reg     [1:0]   state_q;
    reg     [1:0]   next_state;
    reg     [2:0]   step_q;
    reg     [1:0]   pass_q;
    reg             phase_q;

    wire            load_done;
    wire            sort_done;
    wire            check_done;

    assign load_done  = (step_q == LOAD_LAST);
    assign sort_done  = phase_q && mul_done && (step_q == SORT_LAST) && (pass_q == PASS_LAST);
    assign check_done = phase_q && mul_done && (step_q == CHECK_LAST);

    always @(posedge clk or posedge reset) begin
        if (reset) state_q <= S0_LOAD;
        else state_q <= next_state;
    end

    always @(*) begin
        next_state = state_q;
        case (state_q)
            S0_LOAD:  if (load_done)  next_state = S1_SORT;
            S1_SORT:  if (sort_done)  next_state = S2_CHECK;
            S2_CHECK: if (check_done) next_state = S3_DONE;
            S3_DONE:  next_state = S0_LOAD;
            default:  next_state = S0_LOAD;
        endcase
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            step_q  <= 3'd0;
            pass_q  <= 2'd0;
            phase_q <= 1'b0;
        end
        else begin
            case (state_q)
                S0_LOAD: begin
                    if (load_done) step_q <= 3'd0;
                    else step_q <= step_q + 3'd1;
                end
                S1_SORT: begin
                    if (mul_done) begin
                        phase_q <= ~phase_q;
                        if (phase_q) begin
                            if (sort_rot) begin
                                step_q <= 3'd0;
                                pass_q <= pass_q + 2'd1;
                            end
                            else step_q <= step_q + 3'd1;
                        end
                    end
                end
                S2_CHECK: begin
                    if (mul_done) begin
                        phase_q <= ~phase_q;
                        if (phase_q) begin
                            if (check_done) step_q <= 3'd0;
                            else step_q <= step_q + 3'd1;
                        end
                    end
                end
                default: begin
                    step_q  <= 3'd0;
                    pass_q  <= 2'd0;
                    phase_q <= 1'b0;
                end
            endcase
        end
    end

    assign load_en  = (state_q == S0_LOAD);
    assign sort_en  = (state_q == S1_SORT) && phase_q && mul_done;
    assign sort_rot = (step_q == SORT_LAST);
    assign check_en = (state_q == S2_CHECK) && phase_q && mul_done;
    assign base_sel = (state_q == S2_CHECK);
    assign phase    = phase_q;
    assign mul_run  = (state_q == S1_SORT) || (state_q == S2_CHECK);

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

endmodule
