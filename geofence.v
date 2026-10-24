module geofence (clk,reset,X,Y,valid,is_inside);
input clk;
input reset;
input [9:0] X;
input [9:0] Y;
output reg valid;
output reg is_inside;

reg cal_data_val, fence_data_val, sort_val;
reg [1:0] state, nextState;
reg [9:0] cal_data_x, cal_data_y;
reg [0:5] [9:0] fence_data_x, fence_data_y;
reg [0:5] [9:0] sort_data_x, sort_data_y;

localparam IDLE 2'd0;
localparam SORT 2'd1;
localparam CAL 2'd2;

    always@ (posedge clk or negedge reset) begin
        if (reset) begin
            state <= IDLE;
        end else begin
            state <= nextState;
        end
    end


    always@(state) begin
         case (state)
            `IDLE: begin
                if (cal_data_val) begin
                    nextState = SORT;
                end else begin
                    nextState = IDLE;
                end 
            end

             `SORT: begin
                if (sort_val) begin
                    nextState = CAL;
                end else begin
                    nextState = SORT;
                end
            end
        
            `CAL: begin
                if (valid) begin
                    nextState = IDLE;
                end else begin 
                    nextState = CAL;
                end                
            end
        endcase
    end

    always@ (posedge clk or negedge reset) begin
        if (reset) begin
            valid <= 1'b0;
        end else begin
            case (state) 
                `IDLE: begin
                    cal_data_x = X;
                    cal_data_y = Y;
                    cal_data_val = 1;
                end

                `SORT: begin
                    if (sort_val) begin
                        
                    end else begin

                    end
                end

                `CAL: begin
                    if (valid) begin
                        is_inside <= is_inside;
                    end else begin
                        is_inside <= 1'b0;
                    end
                end
            endcase
        end
    end
endmodule

