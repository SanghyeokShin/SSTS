`timescale 1ns / 1ps

module image_reader (
    input  logic                       DE,
    input  logic [                9:0] x_pixel,
    input  logic [                9:0] y_pixel,
    output logic [$clog2(320*240)-1:0] addr,
    input  logic [               15:0] imgData,
    output logic [                3:0] r_port,
    output logic [                3:0] g_port,
    output logic [                3:0] b_port
);

    // Upscaling
    assign addr = DE ? (320 * y_pixel[9:1] + (319 - x_pixel[9:1])) : 'bz;
    assign {r_port, g_port, b_port} = DE ? {imgData[15:12], imgData[10:7], imgData[4:1]} : 0;
endmodule

module background_image_reader (
    input  logic                       DE,
    input  logic [                9:0] x_pixel,
    input  logic [                9:0] y_pixel,
    output logic [$clog2(80*60)-1:0] addr,
    input  logic [               15:0] imgData,
    output logic [                3:0] r_port,
    output logic [                3:0] g_port,
    output logic [                3:0] b_port
);

    // Upscaling
    assign addr = DE ? (80 * y_pixel[9:3] + (79 - x_pixel[9:3])) : 'bz;
    assign {r_port, g_port, b_port} = DE ? {imgData[15:12], imgData[10:7], imgData[4:1]} : 0;
endmodule

module grayFilter (
    input  logic [3:0] i_r,
    input  logic [3:0] i_g,
    input  logic [3:0] i_b,
    output logic [3:0] o_r,
    output logic [3:0] o_g,
    output logic [3:0] o_b
);
    logic [12:0] gray_sum;
    logic [3:0]  gray_out;

    
    logic [11:0] r_val;
    logic [11:0] g_val;
    logic [11:0] b_val;
    
    assign r_val = (i_r << 6) + (i_r << 3) + (i_r << 2) + i_r;
    assign g_val = (i_g << 7) + (i_g << 4) + (i_g << 3) + (i_g << 1);
    assign b_val = (i_b << 4) + (i_b << 3) + i_b;
    
    assign gray_sum = r_val + g_val + b_val;

    assign gray_out = gray_sum[12:9]; 
    
    assign o_r = gray_out;
    assign o_g = gray_out;
    assign o_b = gray_out;

endmodule

module mux_2x1 (
    input  logic        sel,
    input  logic [11:0] x0,
    input  logic [11:0] x1,
    output logic [11:0] y
);

always_comb begin
    y = x0;
    case (sel)
        1'b0: y = x0;
        1'b1: y = x1;
    endcase
end
    
endmodule