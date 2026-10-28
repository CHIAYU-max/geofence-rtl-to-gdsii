//================================================================================
// EXPERIMENT (2026-10-26, sweep/M_serial): copy of sort_new.v with the 11x11
// combinational multiplier replaced by a serial shift-add multiplier.
// Not the submitted design; the original sort_new.v is unchanged.
//
// Changes from sort_new.v (coordinate registers and sorting are identical):
//    1. prod = diff_x * diff_y is computed over 11 cycles, LSB first:
//         hi = hi +/- (diff_y[i] ? diff_x : 0)   (subtract for the sign bit i = 10)
//         {hi, lo} = {hi, lo} >>> 1
//       cycle 11 (cnt_q == 11) holds the product and raises mul_done
//    2. New ports: mul_run (from ctrl, high in SORT / CHECK), mul_done (to ctrl)
//    3. diff_x / diff_y only depend on registers that change at a commit,
//       so they are stable during the 12 cycles of one phase
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
    input   wire            phase,
    input   wire            mul_run,    // High in SORT / CHECK, multiplier runs
    output  wire            mul_done,   // High : product ready, phase may advance
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
    // Shared cross product unit, serial multiplier
    wire        [9:0]   base_x;
    wire        [9:0]   base_y;
    wire        [9:0]   end_x;
    wire        [9:0]   end_y;
    wire signed [10:0]  diff_x;
    wire signed [10:0]  diff_y;
    wire signed [20:0]  prod;           // Product, valid when mul_done
    reg  signed [20:0]  prod_q;         // Ax*By kept for phase 1

    assign base_x = base_sel ? obj_q[19:10] : pt_q[0][19:10];
    assign base_y = base_sel ? obj_q[9:0] : pt_q[0][9:0];
    assign end_x  = phase ? pt_q[2][19:10] : pt_q[1][19:10];
    assign end_y  = phase ? pt_q[1][9:0] : pt_q[2][9:0];

    assign diff_x = {1'b0, end_x} - {1'b0, base_x};
    assign diff_y = {1'b0, end_y} - {1'b0, base_y};

    reg         [3:0]   cnt_q;          // Bit index 0-10, 11 = product ready
    reg  signed [11:0]  hi_q;           // Upper partial product
    reg         [10:0]  lo_q;           // Lower product bits shifted out of hi
    wire signed [11:0]  pp;             // Partial product of this bit
    wire signed [11:0]  sum;

    assign mul_done = mul_run && (cnt_q == 4'd11);
    assign pp       = diff_y[cnt_q] ? {diff_x[10], diff_x} : 12'sd0;
    assign sum      = (cnt_q == 4'd10) ? (hi_q - pp) : (hi_q + pp);
    assign prod     = {hi_q[9:0], lo_q};

    always @(posedge clk) begin
        if (!mul_run || mul_done) begin
            cnt_q <= 4'd0;
            hi_q  <= 12'sd0;
            lo_q  <= 11'd0;
        end
        else begin
            cnt_q <= cnt_q + 4'd1;
            hi_q  <= {sum[11], sum[11:1]};
            lo_q  <= {sum[0], lo_q[10:1]};
        end
    end

    always @(posedge clk) begin
        if (mul_done && !phase) prod_q <= prod;
    end

    assign ccw = (prod_q > prod);

endmodule
