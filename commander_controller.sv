`timescale 1ns / 1ps

module commander_controller (
    input logic clk,
    input logic reset,

    // --- UI Input ---
    input logic [9:0] i_aim_x,      // Red Tracker X
    input logic [9:0] i_aim_y,      // Red Tracker Y
    input logic       i_btn_select, // 설정 변경 버튼 (Select)

    // [신규] 모드 전환 스위치 입력
    input logic i_sw_mode,  // 0: Setting, 1: Result

    // --- Data Input ---
    input logic [4:0] i_score_0,  // Soldier 1 점수
    input logic [4:0] i_score_1,  // Soldier 2 점수
    input logic [4:0] i_score_2,  // Soldier 3 점수

    // --- Output ---
    output logic [7:0] o_config,   // 결정된 설정값
    output logic [1:0] o_soldier,  // 선택된 타겟
    output logic       o_ui_mode,  // 0: Setting Mode, 1: Result Mode

    // 등수 출력
    output logic [1:0] o_rank_0,
    output logic [1:0] o_rank_1,
    output logic [1:0] o_rank_2
);

    // 내부 레지스터
    logic [7:0] config_reg;
    logic [1:0] target_reg;

    // Default: BG(01=사막), Time(01=30s), Count(0101=5마리)
    // Count 설정 기능은 삭제되었으므로 초기값(0101)이 계속 유지됩니다.
    localparam DEFAULT_CONFIG = 8'b01_01_0101; 

    assign o_config  = config_reg;
    assign o_soldier = target_reg;

    // [변경] 모드는 스위치 값 그대로 출력 (레지스터 아님)
    assign o_ui_mode = i_sw_mode;

    // 버튼 엣지 검출
    logic btn_sel_d;
    logic sel_posedge;

    always_ff @(posedge clk) begin
        btn_sel_d <= i_btn_select;
    end
    assign sel_posedge = i_btn_select && !btn_sel_d;

    // =========================================================================
    // 1. UI Hit Test (화면 터치 로직) - 좌표 수정됨
    // =========================================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            config_reg <= DEFAULT_CONFIG;
            target_reg <= 2'd0;
        end else if (sel_posedge) begin

            // [MODE 0] 환경 설정 모드일 때만 설정값 변경 가능
            if (i_sw_mode == 1'b0) begin
                
                // [Col 2] 배경 설정 (중앙: 270 ~ 370) - 좌표 수정됨
                if (i_aim_x >= 270 && i_aim_x < 370) begin
                    if (i_aim_y >= 100 && i_aim_y < 180)
                        config_reg[7:6] <= 2'b00;
                    else if (i_aim_y >= 200 && i_aim_y < 280)
                        config_reg[7:6] <= 2'b01;
                    else if (i_aim_y >= 300 && i_aim_y < 380)
                        config_reg[7:6] <= 2'b10;
                end 
                // [Col 3] 시간 설정 (우측: 490 ~ 590) - 좌표 수정됨
                else if (i_aim_x >= 490 && i_aim_x < 590) begin
                    if (i_aim_y >= 100 && i_aim_y < 180)
                        config_reg[5:4] <= 2'b00;
                    else if (i_aim_y >= 200 && i_aim_y < 280)
                        config_reg[5:4] <= 2'b01;
                    else if (i_aim_y >= 300 && i_aim_y < 380)
                        config_reg[5:4] <= 2'b10;
                end 
                
                // [삭제됨] Col 4 (Target Count) 설정 로직 삭제
            end

            // [공통] Soldier 선택 (좌측: 50 ~ 150) - Setting/Result 모드 모두 가능
            // 좌표 수정됨 (30~130 -> 50~150)
            if (i_aim_x >= 50 && i_aim_x < 150) begin
                if (i_aim_y >= 100 && i_aim_y < 180) target_reg <= 2'd0;
                else if (i_aim_y >= 200 && i_aim_y < 280) target_reg <= 2'd1;
                else if (i_aim_y >= 300 && i_aim_y < 380) target_reg <= 2'd2;
            end
        end
    end

    // =========================================================================
    // 2. Ranking Logic (Standard Competition Ranking) - 유지
    // =========================================================================
    always_comb begin

        // ---------------------------------------------------------
        // Soldier 0 등수 계산
        // ---------------------------------------------------------
        if (i_score_1 > i_score_0 && i_score_2 > i_score_0) begin
            o_rank_0 = 3;
        end
        else if (i_score_1 > i_score_0 || i_score_2 > i_score_0) begin
            o_rank_0 = 2;
        end
        else begin
            o_rank_0 = 1;
        end

        // ---------------------------------------------------------
        // Soldier 1 등수 계산
        // ---------------------------------------------------------
        if (i_score_0 > i_score_1 && i_score_2 > i_score_1) begin
            o_rank_1 = 3;
        end else if (i_score_0 > i_score_1 || i_score_2 > i_score_1) begin
            o_rank_1 = 2;
        end else begin
            o_rank_1 = 1;
        end

        // ---------------------------------------------------------
        // Soldier 2 등수 계산
        // ---------------------------------------------------------
        if (i_score_0 > i_score_2 && i_score_1 > i_score_2) begin
            o_rank_2 = 3;
        end else if (i_score_0 > i_score_2 || i_score_1 > i_score_2) begin
            o_rank_2 = 2;
        end else begin
            o_rank_2 = 1;
        end
    end
endmodule