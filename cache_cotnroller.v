`timescale 1ns / 1ps

module cache_controller (
    input wire clk,
    input wire rst_n,

    input wire cpu_req_enable,
    input wire cpu_req_rw,              // 0 = read, 1 = write
    input wire [31:0] cpu_req_addr,
    input wire [31:0] cpu_req_datain,
    output reg [31:0] cpu_res_dataout,
    output reg cpu_res_ready,

    output reg mem_req_enable,
    output reg mem_req_rw,              
    output reg [31:0] mem_req_addr,
    output reg [511:0] mem_req_dataout,
    input wire [511:0] mem_req_datain,
    input wire mem_req_ready
);

localparam IDLE          = 3'b000;
localparam CHECK_HIT     = 3'b001;
localparam EVICT         = 3'b010;
localparam ALLOCATE      = 3'b011;
localparam SEND_TO_CPU   = 3'b100;

wire [20:0] addr_tag      = cpu_req_addr[31:11];  
wire [6:0]  addr_index    = cpu_req_addr[10:4];   
wire [3:0]  addr_offset   = cpu_req_addr[3:0];    

reg [2:0] state, next_state;

reg [536:0] cache[0:127][0:3]; 

integer i;
reg [1:0] hit_way;
reg hit;
reg evict_needed;
reg [1:0] lru_way;
reg [511:0] block_buffer;
reg [31:0] data_word;

wire [511:0] replaced_block;
reg replacer_enable;

reg latched_rw;
reg [3:0] latched_offset;
reg [31:0] latched_data;
reg [20:0] latched_tag;


replacer word_replacer (
    .data_in(latched_rw ? mem_req_datain : cache[addr_index][hit_way][511:0]),
    .word_offset(addr_offset),
    .data_write(cpu_req_datain),
    .enable(replacer_enable),
    .data_out(replaced_block)
);



integer s,w;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
    for (s = 0; s < 128; s = s + 1) begin
            for (w = 0; w < 4; w = w + 1) begin
                cache[s][w] <= 537'd0; 
            end
        end
	state <= IDLE;
    end else begin
        state <= next_state;
    end
end

always @(*) begin
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
	    evict_needed = 0;
	    replacer_enable = 0;

            hit = 0;
            hit_way = 2'b00;

           
            for (i = 0; i < 4; i = i + 1) begin
                if (cache[addr_index][i][536] == 1'b1 &&  // valid
                    cache[addr_index][i][532:512] == addr_tag) begin
                    hit = 1;
                    hit_way = i[1:0];
                end
            end

            if (hit) begin

		if (latched_rw == 1'b0) begin
                    next_state = SEND_TO_CPU;
                    end else begin
		    
                    replacer_enable = 1;
                    cache[addr_index][hit_way][511:0] = replaced_block;
                    cache[addr_index][hit_way][535] = 1'b1; 
                    next_state = IDLE;
                end

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

                for (i = 0; i < 4; i = i + 1) begin
                    if (i != hit_way && cache[addr_index][i][536] == 1'b1) begin
                        if (cache[addr_index][i][534:533] < cache[addr_index][hit_way][534:533]) begin
                            cache[addr_index][i][534:533] = cache[addr_index][i][534:533] + 1;
                        end
                    end
                end
                cache[addr_index][hit_way][534:533] = 2'b00;

            end else begin
                evict_needed = 1;
                lru_way = 2'b00;

                for (i = 0; i < 4; i = i + 1) begin
                    if (cache[addr_index][i][536] == 0) begin 
                        lru_way = i[1:0];
                        evict_needed = 0;
                    end
                end

                if (evict_needed) begin
                    for (i = 0; i < 4; i = i + 1) begin
                        if (cache[addr_index][i][534:533] == 2'b11) begin
                            lru_way = i[1:0];
                        end
                    end
                end

                if (evict_needed && cache[addr_index][lru_way][535] == 1'b1) begin
                    mem_req_enable = 1;
                    mem_req_rw = 1;
                    mem_req_addr = {cache[addr_index][lru_way][532:512], addr_index, 4'b0000};
                    mem_req_dataout = cache[addr_index][lru_way][511:0];
                    next_state = EVICT;
                end else begin
                    mem_req_enable = 1;
                    mem_req_rw = 0;
                    mem_req_addr = {addr_tag, addr_index, 4'b0000};
                    next_state = ALLOCATE;
                end

            end
        end


        EVICT: begin
            if (mem_req_ready) begin
                mem_req_enable = 1;
                mem_req_rw = 0;
                mem_req_addr = {addr_tag, addr_index, 4'b0000};
                next_state = ALLOCATE;
            end
        end

        ALLOCATE: begin
            if (mem_req_ready) begin
                block_buffer = mem_req_datain;

                if (latched_rw == 1'b1) begin
                    replacer_enable = 1;
                    cache[addr_index][lru_way][511:0] = replaced_block;
                end else begin
                    cache[addr_index][lru_way][511:0] = block_buffer;
                    cache[addr_index][lru_way][535] = 1'b0;  
                end

                cache[addr_index][lru_way][536] = 1'b1;       
                cache[addr_index][lru_way][534:533] = 2'b00;  
                cache[addr_index][lru_way][532:512] = addr_tag;

                
                for (i = 0; i < 4; i = i + 1) begin
                    if (i != lru_way && cache[addr_index][i][536] == 1'b1) begin
                        cache[addr_index][i][534:533] = cache[addr_index][i][534:533] + 1;
                    end
                end

                if (cpu_req_rw == 1'b0) begin
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

    always #5 clk = ~clk;

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

        $display("Test 1: Read miss → memory load");
        cpu_read(32'h0000_0010); 
        #50;
        memory_respond(512'hBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADBADB);
        wait (cpu_res_ready);
        $display("Read data: %h", cpu_res_dataout);

        $display("Test 2: Read hit → should reuse block");
        cpu_read(32'h0000_0010);
        wait (cpu_res_ready);
        $display("Read data: %h", cpu_res_dataout);

        $display("Test 3: Write hit");
        cpu_write(32'h0000_0010, 32'hDEADBEEF);
        #50;

        $display("Test 4: Read after write (verify DEADBEEF)");
        cpu_read(32'h0000_0010);
        wait (cpu_res_ready);
        $display("Read data: %h", cpu_res_dataout);

        $display("Test 5: Write miss to new index");
        cpu_write(32'h0000_1004, 32'hCAFEBABE);
        #50;
        memory_respond(512'hFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACEFEEDFACE);

        $display("Test 6: Fill all 4 ways (index=0, 4 different tags)");
        cpu_read(32'h0000_0010); 
        #50; memory_respond(512'hA0);
        cpu_read(32'h1000_0010); 
        #50; memory_respond(512'hA1);
        cpu_read(32'h2000_0010); 
        #50; memory_respond(512'hA2);
        cpu_read(32'h3000_0010); 
        #50; memory_respond(512'hA3);

        $display("Test 7: Read miss causes eviction (tag 4, index=0)");
        cpu_read(32'h4000_0010); 
        #50; memory_respond(512'hA4);
        wait (cpu_res_ready);
        $display("Read data after eviction: %h", cpu_res_dataout);

        $display("Test 8: Make all 4 current blocks dirty (tags 1-4)");
        cpu_write(32'h1000_0010, 32'h11111111); 
        #10;
        cpu_write(32'h2000_0010, 32'h22222222); 
        #10;
        cpu_write(32'h3000_0010, 32'h33333333); 
        #10;
        cpu_write(32'h4000_0010, 32'h44444444); 
        #10;

        $display("Test 9: Write miss with dirty eviction (tag 5 evicts tag 1)");
        cpu_write(32'h5000_0010, 32'h55555555); 
        #50;
        memory_respond(512'hA5); 

        $display("Eviction test completed.");


        $display("Testbench completed.");
        #100 $finish;
    end

endmodule
