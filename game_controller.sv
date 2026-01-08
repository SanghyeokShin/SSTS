`timescale 1ns / 1ps

module game_controller (
    input logic clk,
    input logic reset,
    input logic btn_start,
    input logic btn_fire,

    input logic [9:0] aim_x,
    input logic [9:0] aim_y,
    input logic       aim_detected,

    input logic [7:0] i2c_data,
    // input logic [5:0] time_limit,
    // input logic [3:0] shot_limit,

    input  logic       game_setting,
    output logic [9:0] target_x,
    output logic [9:0] target_y,
    output logic       target_on,
    output logic       start_timer_on,
    output logic [4:0] score,
    output logic [7:0] slave2master,
    output logic [5:0] time_left,
    output logic [4:0] shot_left,
    output logic [2:0] start_timer,
    output logic       game_ready,
    output logic       game_over,
    output logic [1:0] bg_sel
);

    typedef enum logic [2:0] {
        IDLE,
        SETTING,
        WAIT,
        PLAY,
        GAME_OVER
    } state_t;
    state_t state_reg, state_next;

    localparam TARGET_SIZE_HALF = 16;
    localparam CNT_1SEC = 25000000;

    logic [15:0] lfsr;
    logic [9:0] rand_x, rand_y;
    logic btn_fire_delay;
    logic btn_fire_pos;

    logic [$clog2(CNT_1SEC)-1:0] game_timer_reg, game_timer_next;
    logic [$clog2(CNT_1SEC * 3)-1:0] respawn_timer_reg, respawn_timer_next;
    logic [2:0] start_timer_reg, start_timer_next;

    logic [5:0] time_limit_reg, time_limit_next;
    logic [4:0] shot_limit_reg, shot_limit_next;
    logic [1:0] limit_reg, limit_next;
    logic [1:0] bg_sel_reg, bg_sel_next;
    logic [1:0] bg_out_reg, bg_out_next;

    logic game_over_reg, game_over_next;
    logic [4:0] score_reg, score_next;
    logic [9:0] target_x_reg, target_x_next;
    logic [9:0] target_y_reg, target_y_next;
    logic target_on_reg, target_on_next;
    logic [6:0] slave2master_reg, slave2master_next;

    assign time_left = time_limit_reg;
    assign shot_left = shot_limit_reg;
    assign target_x = target_x_reg;
    assign target_y = target_y_reg;
    assign target_on = target_on_reg;
    assign start_timer_on = (state_reg == WAIT);

    assign score = score_reg;

    assign slave2master = {1'b0, limit_reg, score_reg};

    assign game_over = game_over_reg;

    assign rand_x = 50 + (lfsr[9:0] % 540);
    assign rand_y = 50 + (lfsr[15:6] % 380);

    assign btn_fire_pos = btn_fire && !btn_fire_delay;

    assign game_ready = (state_reg == PLAY) ? 1'b0 : 1'b1;

    assign bg_sel = bg_out_reg;

    assign start_timer = start_timer_reg;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            lfsr              <= 16'hACE1;
            btn_fire_delay    <= 0;
            state_reg         <= IDLE;
            score_reg         <= 0;
            target_x_reg      <= 320;
            target_y_reg      <= 240;
            target_on_reg     <= 0;
            game_timer_reg    <= 0;
            respawn_timer_reg <= 0;
            start_timer_reg   <= 3'd5;
            time_limit_reg    <= 0;
            shot_limit_reg    <= 0;
            limit_reg         <= 0;
            // bg_out_reg        <= 0;
            game_over_reg     <= 0;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            btn_fire_delay <= btn_fire;
            state_reg <= state_next;
            score_reg <= score_next;
            target_x_reg <= target_x_next;
            target_y_reg <= target_y_next;
            target_on_reg <= target_on_next;
            game_timer_reg <= game_timer_next;
            respawn_timer_reg <= respawn_timer_next;
            start_timer_reg <= start_timer_next;
            time_limit_reg <= time_limit_next;
            shot_limit_reg <= shot_limit_next;
            limit_reg <= limit_next;
            bg_sel_reg <= bg_sel_next;
            bg_out_reg <= bg_out_next;
            game_over_reg <= game_over_next;
        end
    end

    always_comb begin
        state_next         = state_reg;
        score_next         = score_reg;
        target_x_next      = target_x_reg;
        target_y_next      = target_y_reg;
        target_on_next     = target_on_reg;
        game_timer_next    = game_timer_reg;
        respawn_timer_next = respawn_timer_reg;
        start_timer_next   = start_timer_reg;
        time_limit_next    = time_limit_reg;
        shot_limit_next    = shot_limit_reg;
        limit_next         = limit_reg;
        bg_sel_next        = bg_sel_reg;
        bg_out_next        = bg_out_reg;
        game_over_next     = game_over_reg;

        case (state_reg)
            IDLE: begin
                start_timer_next   = 3'd5;
                target_on_next     = 0;
                score_next         = score_reg;
                game_timer_next    = 0;
                respawn_timer_next = 0;
                game_over_next     = 0;
                if (game_setting) begin
                    // if (1'b1) begin
                    state_next    = SETTING;

                    // i2c를 받아와서 디코딩 해주기
                    bg_sel_next   = i2c_data[7:6];
                    limit_next    = i2c_data[5:4];

                    target_x_next = 320;
                    target_y_next = 240;
                end
            end
            SETTING: begin
                score_next      = 0;
                time_limit_next = 0;
                shot_limit_next = 0;
                case (limit_reg)
                    2'b00: begin
                        time_limit_next = 6'd15;
                        shot_limit_next = 5'd5;
                    end
                    2'b01: begin
                        time_limit_next = 6'd30;
                        shot_limit_next = 5'd10;
                    end
                    2'b10: begin
                        time_limit_next = 6'd60;
                        shot_limit_next = 5'd20;
                    end
                endcase
                case (bg_sel_reg)
                    2'b00: begin
                        bg_out_next = 2'b00;
                    end
                    2'b01: begin
                        bg_out_next = 2'b01;
                    end
                    2'b10: begin
                        bg_out_next = 2'b10;
                    end
                endcase
                //    if (btn_start) begin
                state_next = WAIT;
                //    end
            end
            WAIT: begin
                // 마스터에서 받아온 설정값 기반 화면으로 전환 후 5초 카운터
                if (start_timer_reg == 0) begin
                    state_next       = PLAY;
                    target_on_next   = 1'b1;
                    start_timer_next = 3'd5;
                end else begin
                    if (game_timer_reg >= CNT_1SEC) begin
                        game_timer_next  = 0;
                        start_timer_next = start_timer_reg - 1;
                    end else begin
                        game_timer_next = game_timer_reg + 1;
                    end
                end
            end
            PLAY: begin
                if (time_limit_reg == 0) begin
                    state_next = GAME_OVER;
                end

                if (game_timer_reg >= CNT_1SEC) begin
                    game_timer_next = 0;
                    if (time_limit_reg > 0)
                        time_limit_next = time_limit_reg - 1;
                end else begin
                    game_timer_next = game_timer_reg + 1;
                end

                if (btn_fire_pos) begin
                    if (shot_limit_reg > 0)
                        shot_limit_next = shot_limit_reg - 1;
                    else shot_limit_next = 0;

                    if (aim_detected && target_on_reg) begin
                        if ((aim_x >= target_x_reg - TARGET_SIZE_HALF) &&
                            (aim_x <= target_x_reg + TARGET_SIZE_HALF) &&
                            (aim_y >= target_y_reg - TARGET_SIZE_HALF) &&
                            (aim_y <= target_y_reg + TARGET_SIZE_HALF)) begin

                            if (shot_limit_reg > 0) begin
                                score_next = score_reg + 1;
                                target_on_next = 1'b0;
                            end
                        end
                    end
                end

                respawn_timer_next = respawn_timer_reg + 1;

                if (respawn_timer_reg >= CNT_1SEC * 3) begin
                    respawn_timer_next = 0;
                    target_x_next = rand_x;
                    target_y_next = rand_y;
                    target_on_next = 1'b1;
                end
            end

            GAME_OVER: begin
                target_on_next = 0;
                game_over_next = 1'b1;
                state_next     = IDLE;

            end
        endcase
    end

endmodule
