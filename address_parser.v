module address_decoder (
    input  [31:0] addr,
    output [20:0] tag,
    output [6:0]  index,
    output [3:0]  block_offset
);

assign tag = addr[31:11];

assign index = addr[10:4];

assign block_offset = addr[3:0];

endmodule
