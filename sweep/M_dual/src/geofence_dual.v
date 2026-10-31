// EXPERIMENT (2026-10-31, sweep/M_dual): copy of geofence_new.v without the phase
// signal, for the two-multiplier datapath. Not the submitted design.
module geofence (
    input   wire            clk,
    input   wire            reset,
    input   wire    [9:0]   X,
    input   wire    [9:0]   Y,
    output  wire            valid,
    output  wire            is_inside
);

    wire            load_en;
    wire            sort_en;
    wire            sort_rot;
    wire            check_en;
    wire            base_sel;
    wire            ccw;

    geofence_ctrl u_ctrl (
        .clk      (clk),
        .reset    (reset),
        .ccw      (ccw),
        .load_en  (load_en),
        .sort_en  (sort_en),
        .sort_rot (sort_rot),
        .check_en (check_en),
        .base_sel (base_sel),
        .valid    (valid),
        .is_inside(is_inside)
    );

    sort u_sort (
        .clk      (clk),
        .x        (X),
        .y        (Y),
        .load_en  (load_en),
        .sort_en  (sort_en),
        .sort_rot (sort_rot),
        .check_en (check_en),
        .base_sel (base_sel),
        .ccw      (ccw)
    );

endmodule
