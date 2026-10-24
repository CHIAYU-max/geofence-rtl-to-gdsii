module sort(clk, reset, fence_data_val, fence_data_x, fence_data_y,
 sort_data_x, sort_data_y, sort_val);
input clk, reset, fence_data_val;
input [9:0] fence_data_x, fence_data_y;
output [59:0] sort_data_x, sort_data_y;
output sort_val;

reg [9:0] first_x, first_y;
reg [0:5] [9:0] points_x, points_y;       
reg [2:0] sortState, ;

localparam load: 3'd0;
localparam init: 3'd1;
localparam scan: 3'd2;
localparam compare: 3'd3;
localparam done: 3'd4;

    always@ (posedge clk or posedge reset) begin
        if (reset) begin
            sortState <= load;
        end else begin
            case (sortState)
            `load: begin
                points




