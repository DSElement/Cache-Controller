module address_parser (
    input  [31:0] addr,
    output [18:0] tag,
    output [6:0]  index,
    output [3:0]  block_offset,
    output [1:0]  word_offset
);

    assign tag = addr[31:13];

    assign index = addr[12:6]; //7 bits because we have 128 blocks

    assign block_offset = addr[5:2]; //4 bits because we have 16 words

    assign word_offset = addr[1:0];  //2 bits because we have 4 bytes/word

endmodule
