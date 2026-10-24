//================================================================================
//
// Module Name: geofence_ctrl
// Features :
//    1. Main FSM of the geofence system
//    2. Every sorting / checking step takes 2 cycles (2 multiplier phases)
// Function Descriptions :
//    1. S0_LOAD  : 7 cycles, shift the object and the 6 receivers in
//    2. S1_SORT  : 4 passes x 5 steps, bubble sort of receivers 1-5 by angle
//                  around receiver 0, step 4 of each pass is a plain rotation
//    3. S2_CHECK : 6 steps, one fence edge per step, is_inside is cleared as
//                  soon as one edge is not counter clockwise seen from object
//    4. S3_DONE  : valid is high for this cycle, then back to S0_LOAD
// Author : (your name)
//
//================================================================================
module geofence_ctrl (
    // input signals
    input   wire            clk,        // Clock source, rising edge active
    input   wire            reset,      // Active high asynchronous reset
    input   wire            ccw,        // High : cross product > 0, valid in phase 1
    // output signals
    output  wire            load_en,    // Active high, shift a new coordinate in
    output  wire            sort_en,    // Active high, commit one sorting step
    output  wire            sort_rot,   // Active high, sorting step is a rotation
    output  wire            check_en,   // Active high, commit one checking step
    output  wire            base_sel,   // Vector origin, 0 : receiver 0, 1 : object
    output  wire            phase,      // Multiplier phase, 0 : Ax*By, 1 : Bx*Ay
    output  reg             valid,      // Register out, active high result valid
    output  reg             is_inside   // Register out, high : object is inside
);

    // ----------------------------------------------------------------------
    // FSM State Assignment
    localparam [1:0]
        S0_LOAD  = 2'b00,
        S1_SORT  = 2'b01,
        S2_CHECK = 2'b10,
        S3_DONE  = 2'b11;

    // ----------------------------------------------------------------------
    // Last count of each counter
    localparam [2:0]
        LOAD_LAST  = 3'd6,              // 1 object + 6 receivers
        SORT_LAST  = 3'd4,              // 4 compares + 1 rotation per pass
        CHECK_LAST = 3'd5;              // 6 fence edges
    localparam [1:0]
        PASS_LAST  = 2'd3;              // 4 passes sort 5 receivers

    reg     [1:0]   state_q;            // Current state
    reg     [1:0]   next_state;         // Next state
    reg     [2:0]   step_q;             // Step counter inside a state
    reg     [1:0]   pass_q;             // Sorting pass counter
    reg             phase_q;            // Multiplier phase

    wire            load_done;          // Last coordinate is being loaded
    wire            sort_done;          // Last sorting step is being committed
    wire            check_done;         // Last fence edge is being checked

    assign load_done  = (step_q == LOAD_LAST);
    assign sort_done  = phase_q && (step_q == SORT_LAST) && (pass_q == PASS_LAST);
    assign check_done = phase_q && (step_q == CHECK_LAST);

    // ----------------------------------------------------------------------
    // Sequential Body
    // Assign combination result to current state @ clock rising
    always @(posedge clk or posedge reset) begin
        // reset to LOAD state, the object arrives in the first cycle
        if (reset) state_q <= S0_LOAD;
        else state_q <= next_state;
    end

    // ----------------------------------------------------------------------
    // Determine Next State
    always @(*) begin
        next_state = state_q;
        case (state_q)
            S0_LOAD: begin
                // Leave after the 6th receiver is loaded
                if (load_done) next_state = S1_SORT;
            end // end S0_LOAD
            S1_SORT: begin
                // Leave after the last rotation of the last pass
                if (sort_done) next_state = S2_CHECK;
            end // end S1_SORT
            S2_CHECK: begin
                // Leave after the 6th fence edge is checked
                if (check_done) next_state = S3_DONE;
            end // end S2_CHECK
            S3_DONE: begin
                // valid is high for one cycle only
                next_state = S0_LOAD;
            end // end S3_DONE
            default: next_state = S0_LOAD;
        endcase
    end

    // ----------------------------------------------------------------------
    // Step, pass and phase counters
    // All counters are back to zero when a state is left
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            step_q  <= 3'd0;
            pass_q  <= 2'd0;
            phase_q <= 1'b0;
        end
        else begin
            case (state_q)
                S0_LOAD: begin
                    // One coordinate per cycle
                    if (load_done) step_q <= 3'd0;
                    else step_q <= step_q + 3'd1;
                end // end S0_LOAD
                S1_SORT: begin
                    phase_q <= ~phase_q;
                    // A step is finished in phase 1
                    if (phase_q) begin
                        if (sort_rot) begin
                            step_q <= 3'd0;
                            pass_q <= pass_q + 2'd1;
                        end
                        else step_q <= step_q + 3'd1;
                    end // end if phase_q
                end // end S1_SORT
                S2_CHECK: begin
                    phase_q <= ~phase_q;
                    // A step is finished in phase 1
                    if (phase_q) begin
                        if (check_done) step_q <= 3'd0;
                        else step_q <= step_q + 3'd1;
                    end // end if phase_q
                end // end S2_CHECK
                default: begin
                    step_q  <= 3'd0;
                    pass_q  <= 2'd0;
                    phase_q <= 1'b0;
                end
            endcase
        end
    end

    // ----------------------------------------------------------------------
    // Datapath Control Signals
    assign load_en  = (state_q == S0_LOAD);
    assign sort_en  = (state_q == S1_SORT) && phase_q;
    assign sort_rot = (step_q == SORT_LAST);
    assign check_en = (state_q == S2_CHECK) && phase_q;
    assign base_sel = (state_q == S2_CHECK);
    assign phase    = phase_q;

    // ----------------------------------------------------------------------
    // Module Output Signals
    // 1. valid is high only in S3_DONE and low after reset
    // 2. is_inside is preset during sorting and cleared by any failing edge
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
