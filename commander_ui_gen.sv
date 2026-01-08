`timescale 1ns / 1ps

module commander_ui_gen (
    input  logic        clk,
    input  logic        reset,
    
    // VGA 신호
    input  logic [9:0]  i_x,
    input  logic [9:0]  i_y,
    input  logic        i_de,

    // UI 상태 정보
    input  logic [7:0]  i_config,     // 현재 설정값
    input  logic [1:0]  i_soldier, // [입력] 현재 선택된 Soldier 번호
    input  logic        i_ui_mode,    // 0:Setting, 1:Result

    // 결과 데이터
    input  logic [4:0]  i_score_0, i_score_1, i_score_2,
    input  logic [1:0]  i_rank_0,  i_rank_1,  i_rank_2,

    // 배경용 카메라 영상
    input  logic [3:0]  i_bg_r,
    input  logic [3:0]  i_bg_g,
    input  logic [3:0]  i_bg_b,

    // 조준선 정보
    input  logic [9:0]  i_aim_x,
    input  logic [9:0]  i_aim_y,
    input  logic        i_aim_detected,

    // 최종 출력
    output logic [3:0]  o_r,
    output logic [3:0]  o_g,
    output logic [3:0]  o_b
);

    // =========================================================================
    // [기존 유지] 숫자 그리기 함수 (7-Segment 스타일)
    // =========================================================================
    function automatic logic draw_num(
        input [9:0] x, input [9:0] y, 
        input [9:0] pos_x, input [9:0] pos_y, 
        input [3:0] digit
    );
        logic [6:0] seg; 
        
        if (x >= pos_x && x < pos_x + 20 && y >= pos_y && y < pos_y + 34) begin
            case(digit)
                4'd0: seg = 7'b1111110; 4'd1: seg = 7'b0110000; 4'd2: seg = 7'b1101101;
                4'd3: seg = 7'b1111001; 4'd4: seg = 7'b0110011; 4'd5: seg = 7'b1011011;
                4'd6: seg = 7'b1011111; 4'd7: seg = 7'b1110000; 4'd8: seg = 7'b1111111;
                4'd9: seg = 7'b1111011; default: seg = 7'b0000000;
            endcase
            
            draw_num = 0;
            if (seg[6] && y < pos_y + 4) draw_num = 1; // Top
            if (seg[5] && x >= pos_x + 16 && y < pos_y + 17) draw_num = 1; // TR
            if (seg[4] && x >= pos_x + 16 && y >= pos_y + 17) draw_num = 1; // BR
            if (seg[3] && y >= pos_y + 30) draw_num = 1; // Bot
            if (seg[2] && x < pos_x + 4 && y >= pos_y + 17) draw_num = 1; // BL
            if (seg[1] && x < pos_x + 4 && y < pos_y + 17) draw_num = 1; // TL
            if (seg[0] && y >= pos_y + 15 && y < pos_y + 19) draw_num = 1; // Mid
        end else begin
            draw_num = 0;
        end
    endfunction

    // =========================================================================
    // 1. UI 영역 정의 (3개 열로 재배치)
    // =========================================================================
    logic in_col_1, in_col_2, in_col_3;
    logic in_row_1, in_row_2, in_row_3;

    // [수정됨] 화면 전체(640px) 기준으로 좌/중/우 대칭 배치 (폭 100px)
    assign in_col_1 = (i_x >= 50)  && (i_x < 150); // Left
    assign in_col_2 = (i_x >= 270) && (i_x < 370); // Center
    assign in_col_3 = (i_x >= 490) && (i_x < 590); // Right
    // in_col_4 삭제됨

    assign in_row_1 = (i_y >= 100) && (i_y < 180);
    assign in_row_2 = (i_y >= 200) && (i_y < 280);
    assign in_row_3 = (i_y >= 300) && (i_y < 380);

    // =========================================================================
    // 2. 문자 그리기 로직 (헤더 + 버튼 텍스트)
    // =========================================================================
    logic draw_char;

    always_comb begin
        draw_char = 0;

        // ---------------------------------------------------------------------
        // [상단 헤더 문자] Y 60~90 영역
        // ---------------------------------------------------------------------
        if (i_y >= 60 && i_y < 90) begin
            
            // [Col 1] 'S' (Select) - X좌표 90~110 (Col 1 중심)
            if (i_x >= 90 && i_x < 110) begin
                if ( (i_y < 65) || (i_y >= 72 && i_y < 77) || (i_y >= 85) || (i_x < 95 && i_y < 75) || (i_x >= 105 && i_y >= 75) ) draw_char = 1;
            end

            // [MODE 0] 설정 화면 헤더: B, T (A 삭제)
            if (i_ui_mode == 0) begin
                // B (Col 2) - X좌표 310~330 (Col 2 중심)
                if (i_x >= 310 && i_x < 330) begin
                     if ( (i_x < 315) || (i_y < 65) || (i_y >= 72 && i_y < 77) || (i_y >= 85) || (i_x >= 325 && !(i_y >= 72 && i_y < 77)) ) draw_char = 1;
                end
                // T (Col 3) - X좌표 530~550 (Col 3 중심)
                else if (i_x >= 530 && i_x < 550) begin
                    if ( (i_y < 65) || (i_x >= 537 && i_x < 543) ) draw_char = 1;
                end
            end 
            
            // [MODE 1] 결과 화면 헤더: SCORE, RANK (배치 조정)
            else begin
                
                // 1. "SCORE" (Col 2 위쪽: 270 ~ 365)
                if (i_y >= 70 && i_y < 90) begin
                    // S
                    if (i_x >= 270 && i_x < 285) begin
                        if ((i_y < 74) || (i_y >= 78 && i_y < 82) || (i_y >= 86) || (i_x < 274 && i_y < 80) || (i_x >= 281 && i_y >= 80)) draw_char = 1;
                    end
                    // C
                    else if (i_x >= 290 && i_x < 305) begin
                        if ((i_y < 74) || (i_y >= 86) || (i_x < 294)) draw_char = 1;
                    end
                    // O
                    else if (i_x >= 310 && i_x < 325) begin
                        if ((i_y < 74) || (i_y >= 86) || (i_x < 314) || (i_x >= 321)) draw_char = 1;
                    end
                    // R
                    else if (i_x >= 330 && i_x < 345) begin
                        if ((i_x < 334) || (i_y < 74) || (i_y >= 78 && i_y < 82) || (i_x >= 341 && i_y < 80) || 
                            (i_x >= 341 && i_y >= 80 && (i_x + 70 >= i_y + 329) && (i_x + 70 <= i_y + 331))) draw_char = 1;
                    end
                    // E
                    else if (i_x >= 350 && i_x < 365) begin
                        if ((i_x < 354) || (i_y < 74) || (i_y >= 78 && i_y < 82) || (i_y >= 86)) draw_char = 1;
                    end
                end

                // 2. "RANK" (Col 3 위쪽: 490 ~ 565)
                if (i_y >= 70 && i_y < 90) begin
                    // R
                    if (i_x >= 490 && i_x < 505) begin
                        if ((i_x < 494) || (i_y < 74) || (i_y >= 78 && i_y < 82) || (i_x >= 501 && i_y < 80) || 
                            (i_x >= 501 && i_y >= 80 && (i_x + 70 >= i_y + 489) && (i_x + 70 <= i_y + 491))) draw_char = 1;
                    end
                    // A
                    else if (i_x >= 510 && i_x < 525) begin
                        if ((i_x < 514) || (i_x >= 521) || (i_y < 74) || (i_y >= 78 && i_y < 82)) draw_char = 1;
                    end
                    // N
                    else if (i_x >= 530 && i_x < 545) begin
                        if ((i_x < 534) || (i_x >= 541) || (i_x + 70 == i_y + 530)) draw_char = 1;
                    end
                    // K
                    else if (i_x >= 550 && i_x < 565) begin
                        if ((i_x < 554) || (i_y + 554 == i_x + 80) || (i_x + i_y == 634)) draw_char = 1;
                    end
                end
            end
        end

        // ---------------------------------------------------------------------
        // [버튼 내부 텍스트] S1, S2, S3 (1열 공통)
        // ---------------------------------------------------------------------
        // Col 1의 시작이 30->50으로 이동했으므로, 텍스트 좌표도 +20 이동
        else if (in_col_1) begin
            if (in_row_1 && i_y >= 130 && i_y < 150) begin // S1
                 if (i_x >= 80 && i_x < 95) begin // S
                     if ( (i_y < 133) || (i_y >= 138 && i_y < 141) || (i_y >= 147) || (i_x < 83 && i_y < 140) || (i_x >= 92 && i_y >= 140) ) draw_char = 1;
                 end else if (i_x >= 105 && i_x < 120) begin // 1
                     if ( (i_x >= 112 && i_x < 115) ) draw_char = 1;
                 end
            end else if (in_row_2 && i_y >= 230 && i_y < 250) begin // S2
                 if (i_x >= 80 && i_x < 95) begin // S
                     if ( (i_y < 233) || (i_y >= 238 && i_y < 241) || (i_y >= 247) || (i_x < 83 && i_y < 240) || (i_x >= 92 && i_y >= 240) ) draw_char = 1;
                 end else if (i_x >= 105 && i_x < 120) begin // 2
                     if ( (i_y < 233) || (i_y >= 238 && i_y < 241) || (i_y >= 247) || (i_x >= 117 && i_y < 240) || (i_x < 108 && i_y >= 240) ) draw_char = 1;
                 end
            end else if (in_row_3 && i_y >= 330 && i_y < 350) begin // S3
                 if (i_x >= 80 && i_x < 95) begin // S
                     if ( (i_y < 333) || (i_y >= 338 && i_y < 341) || (i_y >= 347) || (i_x < 83 && i_y < 340) || (i_x >= 92 && i_y >= 340) ) draw_char = 1;
                 end else if (i_x >= 105 && i_x < 120) begin // 3
                     if ( (i_y < 333) || (i_y >= 338 && i_y < 341) || (i_y >= 347) || (i_x >= 117) ) draw_char = 1;
                 end
            end
        end
    end

    // =========================================================================
    // 3. 설정값 및 선택값 디코딩
    // =========================================================================
    logic [1:0] sel_bg;
    logic [1:0] sel_time;
    // sel_count 삭제됨
    
    assign sel_bg    = i_config[7:6];
    assign sel_time  = i_config[5:4];
    
    // [점수 숫자 분해]
    logic [3:0] s0_tens, s0_ones, s1_tens, s1_ones, s2_tens, s2_ones;
    assign s0_tens = (i_score_0 / 10);
    assign s0_ones = (i_score_0 % 10);
    assign s1_tens = (i_score_1 / 10);
    assign s1_ones = (i_score_1 % 10);
    assign s2_tens = (i_score_2 / 10);
    assign s2_ones = (i_score_2 % 10);

    // =========================================================================
    // 4. 최종 픽셀 합성
    // =========================================================================
    always_comb begin
        // [Layer 0] 배경
        o_r = i_bg_r >> 1; o_g = i_bg_g >> 1; o_b = i_bg_b >> 1;

        if (i_de) begin
            
            // -----------------------------------------------------------------
            // [Layer 1] 공통 영역 및 모드별 그래픽
            // -----------------------------------------------------------------
            
            // [공통: Col 1] Soldier 선택 버튼 (X: 50~150)
            if (in_col_1) begin
                if (in_row_1) begin // Soldier 1
                    if (i_soldier == 2'd0 && ((i_x < 52 || i_x > 147) || (i_y < 102 || i_y > 177))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end 
                    else begin o_r=4'hC; o_g=4'hC; o_b=4'hC; end 
                end else if (in_row_2) begin // Soldier 2
                    if (i_soldier == 2'd1 && ((i_x < 52 || i_x > 147) || (i_y < 202 || i_y > 277))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                    else begin o_r=4'hC; o_g=4'hC; o_b=4'hC; end
                end else if (in_row_3) begin // Soldier 3
                    if (i_soldier == 2'd2 && ((i_x < 52 || i_x > 147) || (i_y < 302 || i_y > 377))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                    else begin o_r=4'hC; o_g=4'hC; o_b=4'hC; end
                end
            end

            // [MODE 0] 설정 화면 요소 (2,3열)
            else if (i_ui_mode == 0) begin
                
                // [Col 2] 배경 (B) - X: 270~370
                if (in_col_2) begin
                    if (in_row_1) begin // 개활지
                        if (sel_bg == 2'b00 && ((i_x < 272 || i_x > 367) || (i_y < 102 || i_y > 177))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                        else begin o_r=4'h2; o_g=4'hA; o_b=4'h2; end 
                    end else if (in_row_2) begin // 사막
                        if (sel_bg == 2'b01 && ((i_x < 272 || i_x > 367) || (i_y < 202 || i_y > 277))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                        else begin o_r=4'hD; o_g=4'h8; o_b=4'h2; end
                    end else if (in_row_3) begin // 눈
                        if (sel_bg == 2'b10 && ((i_x < 272 || i_x > 367) || (i_y < 302 || i_y > 377))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                        else begin o_r=4'hF; o_g=4'hF; o_b=4'hF; end
                    end
                end

                // [Col 3] 시간 (T) - X: 490~590
                else if (in_col_3) begin
                      if (in_row_1) begin // 10s
                        if (sel_time == 2'b00 && ((i_x < 492 || i_x > 587) || (i_y < 102 || i_y > 177))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                        else if (i_x < 490 + 30) begin o_r=4'hF; o_g=4'h0; o_b=4'hF; end
                    end else if (in_row_2) begin // 30s
                        if (sel_time == 2'b01 && ((i_x < 492 || i_x > 587) || (i_y < 202 || i_y > 277))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                        else if (i_x < 490 + 60) begin o_r=4'hF; o_g=4'h0; o_b=4'hF; end
                    end else if (in_row_3) begin // 60s
                        if (sel_time == 2'b10 && ((i_x < 492 || i_x > 587) || (i_y < 302 || i_y > 377))) begin o_r=4'hF; o_g=4'h0; o_b=4'h0; end
                        else begin o_r=4'hF; o_g=4'h0; o_b=4'hF; end
                    end
                end

            end 
            
            // [MODE 1] 결과 화면 요소 (2,3열) - 숫자 위치 재조정
            else begin    
              
                // 1행 (S1 줄)
                if (in_row_1) begin
                    // 점수 (Score) - Col 2 중앙(320) 부근 (300, 325)
                    if (draw_num(i_x, i_y, 300, 120, s0_tens) || draw_num(i_x, i_y, 325, 120, s0_ones)) begin
                        o_r = 4'hF; o_g = 4'hF; o_b = 4'h0; // 노란색
                    end
                    // 랭크 (Rank) - Col 3 중앙(540) 부근 (530)
                    if (draw_num(i_x, i_y, 530, 120, {2'b00, i_rank_0})) begin
                        o_r = 4'hF; o_g = 4'h0; o_b = 4'h0; // 빨간색
                    end
                end
                
                // 2행 (S2 줄)
                else if (in_row_2) begin
                    // 점수
                    if (draw_num(i_x, i_y, 300, 220, s1_tens) || draw_num(i_x, i_y, 325, 220, s1_ones)) begin
                        o_r = 4'hF; o_g = 4'hF; o_b = 4'h0;
                    end
                    // 랭크
                    if (draw_num(i_x, i_y, 530, 220, {2'b00, i_rank_1})) begin
                        o_r = 4'hF; o_g = 4'h0; o_b = 4'h0;
                    end
                end
                
                // 3행 (S3 줄)
                else if (in_row_3) begin
                    // 점수
                    if (draw_num(i_x, i_y, 300, 320, s2_tens) || draw_num(i_x, i_y, 325, 320, s2_ones)) begin
                        o_r = 4'hF; o_g = 4'hF; o_b = 4'h0;
                    end
                    // 랭크
                    if (draw_num(i_x, i_y, 530, 320, {2'b00, i_rank_2})) begin
                        o_r = 4'hF; o_g = 4'h0; o_b = 4'h0;
                    end
                end

            end // End of Mode 1

            // -----------------------------------------------------------------
            // [Layer 2] 텍스트 (그래픽 위에 덮어씀)
            // -----------------------------------------------------------------
            if (draw_char) begin
                o_r = 4'hF; o_g = 4'hF; o_b = 4'hF;
            end

            // -----------------------------------------------------------------
            // [Layer 3] 조준선 (최상위)
            // -----------------------------------------------------------------
            if (i_aim_detected && 
               (((i_y >= i_aim_y - 1) && (i_y <= i_aim_y + 1) && (i_x >= i_aim_x - 10) && (i_x <= i_aim_x + 10)) || 
                ((i_x >= i_aim_x - 1) && (i_x <= i_aim_x + 1) && (i_y >= i_aim_y - 10) && (i_y <= i_aim_y + 10)))) 
            begin
                o_r = 4'h0; o_g = 4'hF; o_b = 4'h0;
            end
        end
    end

endmodule