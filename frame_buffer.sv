`timescale 1ns / 1ps

module frame_buffer(
    // write side
    input logic wclk,
    input logic we,
    input logic [16:0] wAddr,  // [$clog2(320*240)-1:0] 
    input logic [15:0] wData,

    // read side
    input logic rclk,
    input logic oe,
    input logic [16:0] rAddr,  // [$clog2(320*240)-1:0] 
    output logic [15:0] rData

    );

    logic [15:0] mem[0:(320*240)-1];

    // write side
    always_ff @(posedge wclk) begin
        if (we) mem[wAddr] <= wData;
    end

    // read side
    always_ff @( posedge rclk) begin
        if (oe) rData <= mem[rAddr];
    end
endmodule
