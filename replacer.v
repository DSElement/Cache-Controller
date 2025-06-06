module replacer (
    input wire [511:0] data_in,
    input wire [3:0] word_offset,
    input wire [31:0] data_write,
    input wire enable,
    output reg [511:0] data_out
);
    integer i;

    always @(*) begin
        data_out = data_in;
        if (enable) begin
            case (word_offset)
                4'd0:  data_out[ 31:  0] = data_write;
                4'd1:  data_out[ 63: 32] = data_write;
                4'd2:  data_out[ 95: 64] = data_write;
                4'd3:  data_out[127: 96] = data_write;
                4'd4:  data_out[159:128] = data_write;
                4'd5:  data_out[191:160] = data_write;
                4'd6:  data_out[223:192] = data_write;
                4'd7:  data_out[255:224] = data_write;
                4'd8:  data_out[287:256] = data_write;
                4'd9:  data_out[319:288] = data_write;
                4'd10: data_out[351:320] = data_write;
                4'd11: data_out[383:352] = data_write;
                4'd12: data_out[415:384] = data_write;
                4'd13: data_out[447:416] = data_write;
                4'd14: data_out[479:448] = data_write;
                4'd15: data_out[511:480] = data_write;
                default: ;
            endcase
        end
    end
endmodule
