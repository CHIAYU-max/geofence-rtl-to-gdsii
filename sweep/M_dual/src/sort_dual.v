//================================================================================
// EXPERIMENT (2026-10-31, sweep/M_dual): copy of sort_new.v with two 11x11
// multipliers. Both products are ready in the same cycle, so the phase mux and
// prod_q are gone; coordinate registers and sorting are identical.
//================================================================================
module sort (
    input   wire            clk,
    input   wire    [9:0]   x,
    input   wire    [9:0]   y,
    input   wire            load_en,
    input   wire            sort_en,
    input   wire            sort_rot,
    input   wire            check_en,
    input   wire            base_sel,
    output  wire            ccw
);

    reg     [19:0]  obj_q;
    reg     [19:0]  pt_q[0:5];

    wire            first_is_min;

    assign first_is_min = ccw || sort_rot;

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

    always @(posedge clk) begin
        if (load_en || sort_en || check_en) begin
            pt_q[2] <= pt_q[3];
            pt_q[3] <= pt_q[4];
            pt_q[4] <= pt_q[5];
        end
    end

    always @(posedge clk) begin
        if (load_en) pt_q[5] <= {x, y};
        else if (check_en) pt_q[5] <= pt_q[0];
        else if (sort_en) begin
            if (first_is_min) pt_q[5] <= pt_q[1];
            else pt_q[5] <= pt_q[2];
        end
    end

    // ----------------------------------------------------------------------
    // Cross product, Ax*By and Bx*Ay in the same cycle
    wire        [9:0]   base_x;
    wire        [9:0]   base_y;
    wire signed [10:0]  ax;
    wire signed [10:0]  ay;
    wire signed [10:0]  bx;
    wire signed [10:0]  by;
    wire signed [20:0]  prod_a;
    wire signed [20:0]  prod_b;

    assign base_x = base_sel ? obj_q[19:10] : pt_q[0][19:10];
    assign base_y = base_sel ? obj_q[9:0] : pt_q[0][9:0];

    assign ax = {1'b0, pt_q[1][19:10]} - {1'b0, base_x};
    assign ay = {1'b0, pt_q[1][9:0]} - {1'b0, base_y};
    assign bx = {1'b0, pt_q[2][19:10]} - {1'b0, base_x};
    assign by = {1'b0, pt_q[2][9:0]} - {1'b0, base_y};

    assign prod_a = ax * by;
    assign prod_b = bx * ay;

    assign ccw = (prod_a > prod_b);

endmodule
