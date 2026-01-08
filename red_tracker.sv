`timescale 1ns / 1ps

module red_tracker (
    input  logic        clk,
    input  logic        reset,
    input  logic        v_sync,
    input  logic        DE,
    input  logic [9:0]  x_pixel,
    input  logic [9:0]  y_pixel,
    input  logic [15:0] data,
    output logic [9:0]  aim_x,
    output logic [9:0]  aim_y,
    output logic        aim_detected
);

    logic [4:0] r_val;
    logic [5:0] g_val;
    logic [4:0] b_val;

    assign r_val = data[15:11];
    assign g_val = data[10:5];
    assign b_val = data[4:0];

    logic is_red;
    assign is_red = (r_val > 5'd20) && (g_val < 6'd15) && (b_val < 5'd15);

    logic [11:0] x_min, x_max;
    logic [11:0] y_min, y_max;
    logic [16:0] pixel_count;

    logic vsync_d;
    logic vsync_start;

    always_ff @(posedge clk) begin
        vsync_d <= v_sync;
    end

    assign vsync_start = v_sync && !vsync_d;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            aim_x <= 0;
            aim_y <= 0;
            aim_detected <= 0;
            x_min <= 12'd4095; 
            x_max <= 0; 
            y_min <= 12'd4095; 
            y_max <= 0;
            pixel_count <= 0;
        end else begin
            if (vsync_start) begin
                if (pixel_count > 50) begin
                    aim_detected <= 1'b1;
                    aim_x <= (x_min + x_max) >> 1;
                    aim_y <= (y_min + y_max) >> 1;
                end else begin
                    aim_detected <= 1'b0;
                end

                x_min <= 12'd4095; 
                x_max <= 0;
                y_min <= 12'd4095; 
                y_max <= 0;
                pixel_count <= 0;

            end else begin
                if (DE && is_red && (x_pixel > 10) && (x_pixel < 630)) begin
                    pixel_count <= pixel_count + 1;

                    if ({2'b00, x_pixel} < x_min) x_min <= {2'b00, x_pixel};
                    if ({2'b00, x_pixel} > x_max) x_max <= {2'b00, x_pixel};

                    if ({2'b00, y_pixel} < y_min) y_min <= {2'b00, y_pixel};
                    if ({2'b00, y_pixel} > y_max) y_max <= {2'b00, y_pixel};
                end
            end
        end
    end

endmodule