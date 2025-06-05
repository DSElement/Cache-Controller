module data_array_4way (
    input clk,

    input [6:0]  index,             // Set index: 128 sets
    input [1:0]  way_select,        // Which way
    input [5:2]  block_offset,      // Word offset in block (16 words)
    input [1:0]  word_offset,       // Byte offset in word (4 bytes)
    input        write_en_block,   // Write full block (memory refill)
    input        write_en_word,    // Write 1 word (CPU)
    input [511:0] block_data_in,   // From memory
    input [31:0]  word_data_in,    // From CPU

    output [31:0] word_data_out    // To CPU
);

    reg [511:0] data_mem [3:0][127:0]; // [WAY][SET] = 64 bytes/block

    wire [511:0] selected_block = data_mem[way_select][index];

    // Extract the 32-bit word from selected block
    assign word_data_out = selected_block[block_offset * 32 +: 32];

    always @(posedge clk) begin
        if (write_en_block) begin
            // Full block write (from memory)
            data_mem[way_select][index] <= block_data_in;
        end else if (write_en_word) begin
            // CPU writes one 32-bit word at offset
            data_mem[way_select][index][block_offset * 32 +: 32] <= word_data_in;
        end
    end

endmodule
