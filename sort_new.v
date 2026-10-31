//================================================================================
//
// Module Name: sort
// Features :
//    1. Coordinate storage of the object and the 6 receivers
//    2. Receiver sorting by shifting only, compared pair is always pt 1 / pt 2
//    3. One 11x11 signed multiplier shared by sorting and inside checking
// Function Descriptions :
//    1. load_en  : obj <- pt0 <- pt1 <- ... <- pt5 <- {x, y}
//                  after 7 shifts obj is the object, pt0-pt5 are the receivers
//    2. sort_en  : pt1-pt5 is a ring, the smaller angle of pt1 / pt2 goes to
//                  the tail (pt5), the larger one stays in pt1
//                  4 compares + 1 rotation (sort_rot) = one bubble sort pass
//    3. check_en : pt0-pt5 is a ring and rotates by one, so every fence edge
//                  passes through pt1 / pt2
//    4. ccw      : cross product of A = pt1 - base and B = pt2 - base is > 0
//                  phase 0 : prod_q = Ax * By
//                  phase 1 : ccw    = prod_q > Bx * Ay
//                  base is pt0 when sorting and obj when checking, because
//                  (pt1 - obj) x (pt2 - pt1) = (pt1 - obj) x (pt2 - obj)
// Notes :
//    1. Data registers have no reset, they are always loaded before used
// Author : Chia-Yu Lee
//
//================================================================================
module sort (
    // input signals
    input   wire            clk,        // Clock source, rising edge active
    input   wire    [9:0]   x,          // X coordinate of object / receiver
    input   wire    [9:0]   y,          // Y coordinate of object / receiver
    input   wire            load_en,    // Active high, shift a new coordinate in
    input   wire            sort_en,    // Active high, commit one sorting step
    input   wire            sort_rot,   // Active high, sorting step is a rotation
    input   wire            check_en,   // Active high, commit one checking step
    input   wire            base_sel,   // Vector origin, 0 : receiver 0, 1 : object
    input   wire            phase,      // Multiplier phase, 0 : Ax*By, 1 : Bx*Ay
    // output signals
    output  wire            ccw         // High : cross product > 0, valid in phase 1
);

    // ----------------------------------------------------------------------
    // Coordinate registers, {x, y} of each point
    reg     [19:0]  obj_q;              // Object under test
    reg     [19:0]  pt_q[0:5];          // Receivers, fence order after sorting

    wire            first_is_min;       // pt1 goes to the tail in a sorting step

    assign first_is_min = ccw || sort_rot;

    // Object, only moves while loading
    always @(posedge clk) begin
        if (load_en) obj_q <= pt_q[0];
    end

    // Receiver 0, origin of the sorting vectors, so it is kept while sorting
    always @(posedge clk) begin
        if (load_en || check_en) pt_q[0] <= pt_q[1];
    end

    // Receiver 1, keeps the larger angle of pt1 / pt2 while sorting
    always @(posedge clk) begin
        if (load_en || check_en) pt_q[1] <= pt_q[2];
        else if (sort_en && first_is_min) pt_q[1] <= pt_q[2];
    end

    // Receivers 2-4, plain shift in every mode
    always @(posedge clk) begin
        if (load_en || sort_en || check_en) begin
            pt_q[2] <= pt_q[3];
            pt_q[3] <= pt_q[4];
            pt_q[4] <= pt_q[5];
        end
    end

    // Receiver 5, tail of the shift chain and of both rings
    always @(posedge clk) begin
        if (load_en) pt_q[5] <= {x, y};
        else if (check_en) pt_q[5] <= pt_q[0];
        else if (sort_en) begin
            if (first_is_min) pt_q[5] <= pt_q[1];
            else pt_q[5] <= pt_q[2];
        end
    end

    // ----------------------------------------------------------------------
    // Shared cross product unit
    // Only one x difference and one y difference are needed per phase
    wire        [9:0]   base_x;         // Vector origin
    wire        [9:0]   base_y;
    wire        [9:0]   end_x;          // Vector end point used in this phase
    wire        [9:0]   end_y;
    wire signed [10:0]  diff_x;         // phase 0 : Ax, phase 1 : Bx
    wire signed [10:0]  diff_y;         // phase 0 : By, phase 1 : Ay
    wire signed [20:0]  prod;           // phase 0 : Ax*By, phase 1 : Bx*Ay
    reg  signed [20:0]  prod_q;         // Ax*By kept for phase 1

    assign base_x = base_sel ? obj_q[19:10] : pt_q[0][19:10];
    assign base_y = base_sel ? obj_q[9:0] : pt_q[0][9:0];
    assign end_x  = phase ? pt_q[2][19:10] : pt_q[1][19:10];
    assign end_y  = phase ? pt_q[1][9:0] : pt_q[2][9:0];

    assign diff_x = {1'b0, end_x} - {1'b0, base_x};
    assign diff_y = {1'b0, end_y} - {1'b0, base_y};
    assign prod   = diff_x * diff_y;

    // Captured every cycle, only the phase 0 value is used (in phase 1)
    always @(posedge clk) begin
        prod_q <= prod;
    end

    // Ax*By - Bx*Ay > 0 : B is counter clockwise from A
    assign ccw = (prod_q > prod);

endmodule
