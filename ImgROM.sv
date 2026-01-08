`timescale 1ns / 1ps

module ImgROM #(
    parameter string MEM_FILE = "forest.mem" // 파일 경로를 parameter로 정의
) (
    input  logic                     clk,
    input  logic [$clog2(80*60)-1:0] addr,
    output logic [             15:0] data
);
    localparam ROM_SIZE = 80 * 60;
    logic [15:0] mem[0:ROM_SIZE-1];

    initial begin
        $readmemh(MEM_FILE, mem);
    end

    always_ff @(posedge clk) begin
        data <= mem[addr];
    end
endmodule

module mux_nx1 #(
    parameter BIT_SIZE = 16
) (
    input  logic [         1:0] sel,
    input  logic [BIT_SIZE-1:0] rom_0,
    input  logic [BIT_SIZE-1:0] rom_1,
    input  logic [BIT_SIZE-1:0] rom_2,
    output logic [BIT_SIZE-1:0] rom
);
    always_comb begin
        rom = 0;
        case (sel)
            2'b00: rom = rom_0;
            2'b01: rom = rom_1;
            2'b10: rom = rom_2;
        endcase
    end
endmodule
