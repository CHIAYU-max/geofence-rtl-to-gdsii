//================================================================================
//
// Module Name: geofence
// Features :
//    1. Geofence system built from 6 receivers (convex hexagon)
//    2. Receivers may arrive in any order, the fence order is rebuilt by sorting
//    3. Area oriented : one shared 11x11 multiplier, no random access to points
// Function Descriptions :
//    1. After reset, cycle 1 takes the object, cycles 2-7 take the 6 receivers
//    2. u_sort keeps the 7 coordinates and reorders the receivers
//    3. u_ctrl sequences load -> sort -> check and drives valid / is_inside
//    4. valid is a one cycle pulse, is_inside is valid in the same cycle
//    5. Timing :
//          X/Y      | obj | r1 | r2 | r3 | r4 | r5 | r6 |  ...  |    |    | obj |
//          valid    ________________________________________|""""|__________
//          is_inside ---------------------------------------< ok >----------
// Notes :
//    1. Port names and the active high reset are fixed by the contest SPEC,
//       so the rst_n / _i / _o naming rules cannot be applied on this module
//    2. Top module holds wires and instances only
// Author : (your name)
//
//================================================================================
module geofence (
    // input signals
    input   wire            clk,        // Clock source, rising edge active
    input   wire            reset,      // Active high asynchronous reset
    input   wire    [9:0]   X,          // X coordinate of object / receiver
    input   wire    [9:0]   Y,          // Y coordinate of object / receiver
    // output signals
    output  wire            valid,      // Active high, is_inside is valid
    output  wire            is_inside   // High : object is inside the fence
);

    // ----------------------------------------------------------------------
    // Control signals from u_ctrl to u_sort
    wire            load_en;            // Shift a new coordinate in
    wire            sort_en;            // Commit one sorting step
    wire            sort_rot;           // Sorting step is a plain rotation
    wire            check_en;           // Commit one inside checking step
    wire            base_sel;           // Vector origin, 0 : receiver 0, 1 : object
    wire            phase;              // Multiplier phase, 0 : Ax*By, 1 : Bx*Ay

    // ----------------------------------------------------------------------
    // Status signal from u_sort to u_ctrl
    wire            ccw;                // Cross product > 0 (counter clockwise)

    // ----------------------------------------------------------------------
    // Controller : FSM, step counters and module outputs
    geofence_ctrl u_ctrl (
        .clk      (clk),
        .reset    (reset),
        .ccw      (ccw),
        .load_en  (load_en),
        .sort_en  (sort_en),
        .sort_rot (sort_rot),
        .check_en (check_en),
        .base_sel (base_sel),
        .phase    (phase),
        .valid    (valid),
        .is_inside(is_inside)
    );

    // ----------------------------------------------------------------------
    // Datapath : coordinate registers, receiver sorting and cross product
    sort u_sort (
        .clk      (clk),
        .x        (X),
        .y        (Y),
        .load_en  (load_en),
        .sort_en  (sort_en),
        .sort_rot (sort_rot),
        .check_en (check_en),
        .base_sel (base_sel),
        .phase    (phase),
        .ccw      (ccw)
    );

endmodule
