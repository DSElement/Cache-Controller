module tag_array_4way (
    input clk,
    input rst,

    input [6:0] index,            
    input [18:0] tag_in,           
    input       valid_in,
    input       dirty_in,

    input       write_en,         
    input [1:0] write_way,        

    input       update_lru,       
    input [1:0] accessed_way,     

    output [18:0] tag_out [3:0], 
    output       valid_out [3:0],
    output       dirty_out [3:0],

    output       hit,
    output [1:0] hit_way,

    output [1:0] lru_way           
);
    reg [18:0] tag_mem   [3:0][127:0];   
    reg        valid_mem [3:0][127:0];
    reg        dirty_mem [3:0][127:0];

    // LRU storage: 2-bit pseudo-LRU per set
    reg [1:0] lru [127:0];

    integer w;

    generate
        genvar i;
        for (i = 0; i < 4; i = i + 1) begin : output_read
            assign tag_out[i]   = tag_mem[i][index];
            assign valid_out[i] = valid_mem[i][index];
            assign dirty_out[i] = dirty_mem[i][index];
        end
    endgenerate

    wire [3:0] match = {
        valid_mem[3][index] && tag_mem[3][index] == tag_in,
        valid_mem[2][index] && tag_mem[2][index] == tag_in,
        valid_mem[1][index] && tag_mem[1][index] == tag_in,
        valid_mem[0][index] && tag_mem[0][index] == tag_in
    };

    assign hit     = |match;
    assign hit_way = match[3] ? 2'd3 :
                     match[2] ? 2'd2 :
                     match[1] ? 2'd1 :
                     match[0] ? 2'd0 : 2'd0;

    // Select replacement way based on LRU value
    assign lru_way = lru[index];

    always @(posedge clk) begin
        if (rst) begin
            for (w = 0; w < 4; w = w + 1) begin
                valid_mem[w][index] <= 1'b0;
                dirty_mem[w][index] <= 1'b0;
                tag_mem[w][index]   <= 19'd0;
            end
            lru[index] <= 2'd0;
        end
        else begin
            if (write_en) begin
                tag_mem[write_way][index]   <= tag_in;
                valid_mem[write_way][index] <= valid_in;
                dirty_mem[write_way][index] <= dirty_in;
            end

            if (update_lru) begin
                lru[index] <= accessed_way;
            end
        end
    end

endmodule
