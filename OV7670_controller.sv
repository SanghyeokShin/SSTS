`timescale 1ns / 1ps

module OV7670_controller (
    input  logic        pclk,
    input  logic        reset,
    // OV7670 side
    input  logic        href,
    input  logic        vsync,
    input  logic [ 7:0] data,
    // memory side
    output logic        we,
    output logic [16:0] wAddr,  // 320 * 240
    output logic [15:0] wData
);

    logic [17:0] pixelCounter;  // 640 * 240
    logic [15:0] pixelData;

    assign wData = pixelData;

    always_ff @(posedge pclk) begin
        if (reset) begin
            pixelCounter <= 0;
            pixelData    <= 0;
            we           <= 1'b0;
            wAddr        <= 0;
        end else begin
            if (href) begin
                if (pixelCounter[0] == 1'b0) begin
                    we              <= 1'b0;
                    pixelData[15:8] <= data;
                end else begin
                    we             <= 1'b1;
                    pixelData[7:0] <= data;
                    wAddr          <= wAddr + 1;
                end
                pixelCounter <= pixelCounter + 1;
            end else if (vsync) begin
                we           <= 1'b0;
                wAddr        <= 0;
                pixelCounter <= 0;
            end
        end
    end

endmodule
