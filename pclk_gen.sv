`timescale 1ns / 1ps

module pixel_clk_gen (
    input  logic clk,
    input  logic reset,
    output logic pclk
);
    logic [1:0] p_counter;
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            pclk      <= 1'b0;
            p_counter <= 0;
        end else begin
            if (p_counter == 3) begin
                pclk      <= 1'b1;
                p_counter <= 0;
            end else begin
                pclk      <= 1'b0;
                p_counter <= p_counter + 1;
            end
        end
    end

endmodule