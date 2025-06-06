`timescale 1ns / 1ps

module cache_controller (
    input wire clk,
    input wire rst_n,

    // CPU interface
    input wire cpu_req_enable,
    input wire cpu_req_rw,              // 0 = read, 1 = write
    input wire [31:0] cpu_req_addr,
    input wire [31:0] cpu_req_datain,
    output reg [31:0] cpu_res_dataout,
    output reg cpu_res_ready,

    // Main memory interface
    output reg mem_req_enable,
    output reg mem_req_rw,              // 0 = read, 1 = write
    output reg [31:0] mem_req_addr,
    output reg [511:0] mem_req_dataout,
    input wire [511:0] mem_req_datain,
    input wire mem_req_ready
);

// =============== Internal Constants ===============
localparam IDLE          = 3'b000;
localparam CHECK_HIT     = 3'b001;
localparam EVICT         = 3'b010;
localparam ALLOCATE      = 3'b011;
localparam SEND_TO_CPU   = 3'b100;

// =============== Address Fields ===============
wire [20:0] addr_tag      = cpu_req_addr[31:11];  // 21 bits
wire [6:0]  addr_index    = cpu_req_addr[10:4];   // 128 sets (7 bits)
wire [3:0]  addr_offset   = cpu_req_addr[3:0];    // 16 words per block (4 bits)

// =============== FSM State ===============
reg [2:0] state, next_state;

// =============== Cache Line Definition ===============
// [536]    valid
// [535]    dirty
// [534:533] age
// [532:512] tag
// [511:0]   data block (16 words)
reg [536:0] cache[0:127][0:3]; // 128 sets × 4 ways

// =============== Internal Variables ===============
integer i;
reg [1:0] hit_way;
reg hit;
reg evict_needed;
reg [1:0] lru_way;
reg [511:0] block_buffer;
reg [31:0] data_word;

//insantiere replacer
wire [511:0] replaced_block;
reg replacer_enable;

replacer word_replacer (
    .data_in(cache[addr_index][hit_way][511:0]),
    .word_offset(addr_offset),
    .data_write(cpu_req_datain),
    .enable(replacer_enable),
    .data_out(replaced_block)
);

//register declarations
reg latched_rw;
reg [3:0] latched_offset;
reg [31:0] latched_data;
reg [20:0] latched_tag;



// =============== FSM ===============
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

always @(*) begin
    // default transitions
    //next_state = state;
    cpu_res_ready = 0;
    mem_req_enable = 0;

    case (state)
        IDLE: begin
            if (cpu_req_enable) begin
        	latched_rw     = cpu_req_rw;
        	latched_offset = cpu_req_addr[3:0];
        	latched_tag    = cpu_req_addr[31:11];
        	latched_data   = cpu_req_datain;
        	next_state = CHECK_HIT;
    end
        end

        CHECK_HIT: begin
            hit = 0;
            hit_way = 2'b00;

            // Search all 4 ways for a hit
            for (i = 0; i < 4; i = i + 1) begin
                if (cache[addr_index][i][536] == 1'b1 &&  // valid
                    cache[addr_index][i][532:512] == addr_tag) begin
                    hit = 1;
                    hit_way = i[1:0];
                end
            end

            if (hit) begin

		if (latched_rw == 1'b0) begin
                    // READ hit: extract word
                    next_state = SEND_TO_CPU;
                    end else begin
                    // WRITE hit: use replacer
                    replacer_enable = 1;
                    #1; // allow one delta cycle (for simulation)
                    cache[addr_index][hit_way][511:0] = replaced_block;
                    cache[addr_index][hit_way][535] = 1'b1; // set dirty bit
                    next_state = IDLE;
                end

                // Extract word from hit block
                block_buffer = cache[addr_index][hit_way][511:0];
                case (addr_offset)
                    4'd0:  data_word = block_buffer[ 31:  0];
                    4'd1:  data_word = block_buffer[ 63: 32];
                    4'd2:  data_word = block_buffer[ 95: 64];
                    4'd3:  data_word = block_buffer[127: 96];
                    4'd4:  data_word = block_buffer[159:128];
                    4'd5:  data_word = block_buffer[191:160];
                    4'd6:  data_word = block_buffer[223:192];
                    4'd7:  data_word = block_buffer[255:224];
                    4'd8:  data_word = block_buffer[287:256];
                    4'd9:  data_word = block_buffer[319:288];
                    4'd10: data_word = block_buffer[351:320];
                    4'd11: data_word = block_buffer[383:352];
                    4'd12: data_word = block_buffer[415:384];
                    4'd13: data_word = block_buffer[447:416];
                    4'd14: data_word = block_buffer[479:448];
                    4'd15: data_word = block_buffer[511:480];
                    default: data_word = 32'd0;
                endcase

                // LRU update logic on hit
                for (i = 0; i < 4; i = i + 1) begin
                    if (i != hit_way && cache[addr_index][i][536] == 1'b1) begin
                        // If age is less than hit way’s original age, increment
                        if (cache[addr_index][i][534:533] < cache[addr_index][hit_way][534:533]) begin
                            cache[addr_index][i][534:533] = cache[addr_index][i][534:533] + 1;
                        end
                    end
                end
                // Reset age of the accessed way to 0
                cache[addr_index][hit_way][534:533] = 2'b00;

            end else begin
                // Find invalid way first
                evict_needed = 1;
                lru_way = 2'b00;

                for (i = 0; i < 4; i = i + 1) begin
                    if (cache[addr_index][i][536] == 0) begin // valid == 0
                        lru_way = i[1:0];
                        evict_needed = 0;
                    end
                end

                // If all valid, find LRU (age == 3)
                if (evict_needed) begin
                    for (i = 0; i < 4; i = i + 1) begin
                        if (cache[addr_index][i][534:533] == 2'b11) begin
                            lru_way = i[1:0];
                        end
                    end
                end

                if (evict_needed && cache[addr_index][lru_way][535] == 1'b1) begin
                    // Dirty → Evict before allocate
                    mem_req_enable = 1;
                    mem_req_rw = 1;
                    mem_req_addr = {cache[addr_index][lru_way][532:512], addr_index, 4'b0000};
                    mem_req_dataout = cache[addr_index][lru_way][511:0];
                    next_state = EVICT;
                end else begin
                    // Clean or invalid → go to allocation
                    mem_req_enable = 1;
                    mem_req_rw = 0;
                    mem_req_addr = {addr_tag, addr_index, 4'b0000};
                    next_state = ALLOCATE;
                end

            end
        end


        EVICT: begin
            if (mem_req_ready) begin
                // After write-back, request memory read
                mem_req_enable = 1;
                mem_req_rw = 0;
                mem_req_addr = {addr_tag, addr_index, 4'b0000};
                next_state = ALLOCATE;
            end
        end

        ALLOCATE: begin
            if (mem_req_ready) begin
                // Step 1: Get the fetched block
                block_buffer = mem_req_datain;

                // Step 2: Overwrite if it's a write miss
                if (latched_rw == 1'b1) begin
                    // write hit simulation: modify block with replacer
                    replacer_enable = 1;
                    #1; // allow delta cycle (simulation-safe)
                    cache[addr_index][lru_way][511:0] = replaced_block;
                    cache[addr_index][lru_way][535] = 1'b1;  // dirty
                end else begin
                    cache[addr_index][lru_way][511:0] = block_buffer;
                    cache[addr_index][lru_way][535] = 1'b0;  // clean (read miss)
                end

                // Step 3: Tag, valid, age
                cache[addr_index][lru_way][536] = 1'b1;       // valid
                cache[addr_index][lru_way][534:533] = 2'b00;  // youngest
                cache[addr_index][lru_way][532:512] = addr_tag;

                // Step 4: Age update for other ways
                for (i = 0; i < 4; i = i + 1) begin
                    if (i != lru_way && cache[addr_index][i][536] == 1'b1) begin
                        cache[addr_index][i][534:533] = cache[addr_index][i][534:533] + 1;
                    end
                end

                // Step 5: Post-allocate action
                if (cpu_req_rw == 1'b0) begin
                    // If read miss, return fetched word to CPU
                    case (addr_offset)
                        4'd0:  data_word = block_buffer[ 31:  0];
                        4'd1:  data_word = block_buffer[ 63: 32];
                        4'd2:  data_word = block_buffer[ 95: 64];
                        4'd3:  data_word = block_buffer[127: 96];
                        4'd4:  data_word = block_buffer[159:128];
                        4'd5:  data_word = block_buffer[191:160];
                        4'd6:  data_word = block_buffer[223:192];
                        4'd7:  data_word = block_buffer[255:224];
                        4'd8:  data_word = block_buffer[287:256];
                        4'd9:  data_word = block_buffer[319:288];
                        4'd10: data_word = block_buffer[351:320];
                        4'd11: data_word = block_buffer[383:352];
                        4'd12: data_word = block_buffer[415:384];
                        4'd13: data_word = block_buffer[447:416];
                        4'd14: data_word = block_buffer[479:448];
                        4'd15: data_word = block_buffer[511:480];
                        default: data_word = 32'd0;
                    endcase
                    next_state = SEND_TO_CPU;
                end else begin
                    // If write miss: write was completed, just return
                    next_state = IDLE;
                end
            end
        end



        SEND_TO_CPU: begin
            cpu_res_dataout = data_word;
            cpu_res_ready = 1;
            next_state = IDLE;
        end


    endcase
end

// =============== TODO (Next Steps) ===============
// 1. Implement hit detection logic
// 2. Implement LRU update logic
// 3. Implement eviction and write-back path
// 4. Implement block allocation path
// 5. Read/write CPU word in 512-bit block
// 6. Integrate with replacer.v for write operations

endmodule


`timescale 1ns / 1ps

module cache_controller_tb;

    reg clk, rst_n;
    reg cpu_req_enable;
    reg cpu_req_rw;
    reg [31:0] cpu_req_addr;
    reg [31:0] cpu_req_datain;
    wire [31:0] cpu_res_dataout;
    wire cpu_res_ready;

    wire mem_req_enable;
    wire mem_req_rw;
    wire [31:0] mem_req_addr;
    wire [511:0] mem_req_dataout;
    reg [511:0] mem_req_datain;
    reg mem_req_ready;

    // Instantiate DUT
    cache_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req_enable(cpu_req_enable),
        .cpu_req_rw(cpu_req_rw),
        .cpu_req_addr(cpu_req_addr),
        .cpu_req_datain(cpu_req_datain),
        .cpu_res_dataout(cpu_res_dataout),
        .cpu_res_ready(cpu_res_ready),
        .mem_req_enable(mem_req_enable),
        .mem_req_rw(mem_req_rw),
        .mem_req_addr(mem_req_addr),
        .mem_req_dataout(mem_req_dataout),
        .mem_req_datain(mem_req_datain),
        .mem_req_ready(mem_req_ready)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Initialize
    task reset();
    begin
        clk = 0; rst_n = 0;
        cpu_req_enable = 0; cpu_req_rw = 0;
        cpu_req_addr = 0; cpu_req_datain = 0;
        mem_req_ready = 0;
        #20;
        rst_n = 1;
    end
    endtask

    // Send CPU read
    task cpu_read(input [31:0] addr);
    begin
        @(negedge clk);
        cpu_req_enable = 1;
        cpu_req_rw = 0;
        cpu_req_addr = addr;
        @(negedge clk);
        cpu_req_enable = 0;
    end
    endtask

    // Send CPU write
    task cpu_write(input [31:0] addr, input [31:0] data);
    begin
        @(negedge clk);
        cpu_req_enable = 1;
        cpu_req_rw = 1;
        cpu_req_addr = addr;
        cpu_req_datain = data;
        @(negedge clk);
        cpu_req_enable = 0;
    end
    endtask

    // Provide memory response
    task memory_respond(input [511:0] data);
    begin
        @(posedge clk);
        mem_req_datain = data;
        mem_req_ready = 1;
        @(posedge clk);
        mem_req_ready = 0;
    end
    endtask

    initial begin
        reset();

        // Test 1: Read miss (block load)
        $display("Test 1: Read miss → memory load");
        cpu_read(32'h0000_0010); // index = 0, offset = 4
        #50;
        memory_respond(512'hBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADB);
        wait (cpu_res_ready);
        $display("Read data: %h", cpu_res_dataout);

        // Test 2: Read hit
        $display("Test 2: Read hit → should reuse block");
        cpu_read(32'h0000_0010);
        wait (cpu_res_ready);
        $display("Read data: %h", cpu_res_dataout);

        // Test 3: Write hit
        $display("Test 3: Write hit");
        cpu_write(32'h0000_0010, 32'hDEADBEEF);
        #50;

        // Test 4: Read after write (verify write took effect)
        $display("Test 4: Read after write (verify DEADBEEF)");
        cpu_read(32'h0000_0010);
        wait (cpu_res_ready);
        $display("Read data: %h", cpu_res_dataout);

        // Test 5: Write miss (different index, should load block then write)
        $display("Test 5: Write miss to new index");
        cpu_write(32'h0000_1004, 32'hCAFEBABE);
        #50;
        memory_respond(512'hFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACE);

        // Optional: More tests for eviction when all ways are full and dirty

        $display("Testbench completed.");
        #100 $finish;
    end

endmodule
