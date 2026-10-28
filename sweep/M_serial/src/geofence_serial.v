// EXPERIMENT (2026-10-26, sweep/M_serial): copy of geofence_new.v that also
// connects mul_run / mul_done for the serial multiplier. Not the submitted design.
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
    wire            phase;
    wire            mul_run;
    wire            mul_done;
    wire            ccw;

    geofence_ctrl u_ctrl (
        .clk      (clk),
        .reset    (reset),
        .ccw      (ccw),
        .mul_done (mul_done),
        .load_en  (load_en),
        .sort_en  (sort_en),
        .sort_rot (sort_rot),
        .check_en (check_en),
        .base_sel (base_sel),
        .phase    (phase),
        .mul_run  (mul_run),
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
        .phase    (phase),
        .mul_run  (mul_run),
        .mul_done (mul_done),
        .ccw      (ccw)
    );

endmodule
