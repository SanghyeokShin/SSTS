`timescale 1ns / 1ps

module button_debounce #(
    parameter F_BTN   = 1_000_000,
    parameter NUM_DEB = 16
) (
    input  logic clk,
    input  logic reset,
    input  logic i_btn,
    output logic o_btn
);

    localparam IDLE = 2'b00, DEBOUNCE = 2'b01, PULSE = 2'b10, STOP = 2'b11;
    logic [1:0] state_reg, state_next;
    logic [$clog2(NUM_DEB)-1:0] deb_cnt_reg, deb_cnt_next;
    logic w_tick;

    btn_tick_gen #(
        .FREQ(F_BTN)
    ) U_TICK (
        .*,
        .o_tick(w_tick)
    );

    assign o_btn = (state_reg == PULSE);

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state_reg   <= 0;
            deb_cnt_reg <= 0;
        end else begin
            state_reg   <= state_next;
            deb_cnt_reg <= deb_cnt_next;
        end
    end

    always_comb begin
        state_next   = state_reg;
        deb_cnt_next = deb_cnt_reg;
        case (state_reg)
            IDLE: begin
                deb_cnt_next = 0;
                if (i_btn) begin
                    state_next = DEBOUNCE;
                end
            end
            DEBOUNCE: begin
                if (w_tick) begin
                    if (i_btn) begin
                        if (deb_cnt_reg == NUM_DEB - 1) begin
                            state_next = PULSE;
                        end else begin
                            deb_cnt_next = deb_cnt_reg + 1;
                        end
                    end else begin
                        state_next = IDLE;
                    end
                end
            end
            PULSE: begin
                state_next = STOP;
            end
            STOP: begin
                if (!i_btn) begin
                    state_next = IDLE;
                end
            end
        endcase
    end

endmodule

module btn_tick_gen #(
    parameter FREQ = 1_000_000
) (
    input  logic clk,
    input  logic reset,
    output logic o_tick
);

    localparam F_COUNT = 100_000_000 / FREQ;

    logic [$clog2(F_COUNT)-1:0] r_cnt;
    logic r_tick;
    assign o_tick = r_tick;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            r_cnt  <= 0;
            r_tick <= 1'b0;
        end else begin
            if (r_cnt == F_COUNT - 1) begin
                r_cnt  <= 0;
                r_tick <= 1'b1;
            end else begin
                r_cnt  <= r_cnt + 1;
                r_tick <= 1'b0;
            end
        end
    end

endmodule