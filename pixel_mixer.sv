`timescale 1ns / 1ps

module pixel_mixer (
    input  logic [11:0] img_bg,
    // AIM (조준점) 입력
    input  logic [ 9:0] aim_x,
    input  logic [ 9:0] aim_y,
    input  logic        aim_detected,
    // TARGET (과녁) 입력 (수정됨: 좌표 입력 받음)
    input  logic [ 9:0] target_x,
    input  logic [ 9:0] target_y,
    input  logic        target_on,       // 타겟 표시 여부
    // SEG DISPLAY
    input  logic [ 4:0] score,           // 점수 입력 (추가됨)
    input  logic [ 5:0] time_left,       // 남은 시간
    input  logic [ 4:0] shot_left,       // 남은 사격횟수
    input  logic [ 2:0] start_timer,
    input  logic        start_timer_on,
    // 공통 입력
    input  logic [ 9:0] x_pixel,
    input  logic [ 9:0] y_pixel,
    // 최종 출력
    output logic [ 3:0] r_port,
    output logic [ 3:0] g_port,
    output logic [ 3:0] b_port
);
    // --- 파라미터 ---
    localparam logic [11:0] RED = 12'hF00;
    localparam logic [11:0] GREEN = 12'h0F0;
    localparam logic [11:0] BLUE = 12'h00F;
    localparam logic [11:0] WHITE = 12'hFFF;
    localparam logic [11:0] YELLOW = 12'hFF0;
    localparam logic [11:0] BLACK = 12'h000;

    localparam logic [11:0] AIM_COLOR = RED;
    localparam logic [11:0] SCORE_COLOR = YELLOW;
    localparam logic [11:0] TIMER_COLOR = WHITE;


    localparam logic [11:0] TARGET_COLOR_Z1 = YELLOW;
    localparam logic [11:0] TARGET_COLOR_Z2 = RED;
    localparam logic [11:0] TARGET_COLOR_Z3 = BLUE;
    localparam logic [11:0] TARGET_COLOR_Z4 = BLACK;
    localparam logic [11:0] TARGET_COLOR_Z5 = WHITE;

    localparam THK = 1;
    localparam LEN = 10;
    localparam TARGET_SIZE_HALF = 16;

    // --- 점수 표시 로직 (7-Segment Style for VGA) ---
    // 오른쪽 상단 위치 설정 (예: x=580, y=30 근처)
    logic is_score_pixel;
    logic is_time_pixel;
    logic is_shot_pixel;
    logic is_start_timer_pixel;
    logic [3:0] digit_to_draw;
    logic [9:0] score_x_offset;

/*
    function logic draw_digit(input [3:0] num, input [9:0] px, input [9:0] py,
                              input [9:0] ox, input [9:0] oy);
        // 7-segment 논리: 가로 4px, 세로 8px 크기 가정 (스케일 조정 가능)
        // a,b,c,d,e,f,g 세그먼트
        logic seg_a, seg_b, seg_c, seg_d, seg_e, seg_f, seg_g;
        logic on;

        // 상대 좌표 (확대 2배: 가로 8, 세로 16 정도)
        int dx, dy;
        dx = (px - ox) >> 1;
        dy = (py - oy) >> 1;

        // 범위 체크 (0~5, 0~9)
        if (dx < 0 || dx > 5 || dy < 0 || dy > 9) return 0;

        // 세그먼트 정의
        seg_a = (dy == 0) && (dx > 0 && dx < 5);
        seg_b = (dx == 5) && (dy > 0 && dy < 5);
        seg_c = (dx == 5) && (dy > 5 && dy < 9);
        seg_d = (dy == 9) && (dx > 0 && dx < 5);
        seg_e = (dx == 0) && (dy > 5 && dy < 9);
        seg_f = (dx == 0) && (dy > 0 && dy < 5);
        seg_g = (dy == 5) && (dx > 0 && dx < 5);

        case (num)
            0:       on = seg_a | seg_b | seg_c | seg_d | seg_e | seg_f;
            1:       on = seg_b | seg_c;
            2:       on = seg_a | seg_b | seg_d | seg_e | seg_g;
            3:       on = seg_a | seg_b | seg_c | seg_d | seg_g;
            4:       on = seg_b | seg_c | seg_f | seg_g;
            5:       on = seg_a | seg_c | seg_d | seg_f | seg_g;
            6:       on = seg_a | seg_c | seg_d | seg_e | seg_f | seg_g;
            7:       on = seg_a | seg_b | seg_c | seg_f;
            8:       on = seg_a | seg_b | seg_c | seg_d | seg_e | seg_f | seg_g;
            9:       on = seg_a | seg_b | seg_c | seg_d | seg_f | seg_g;
            default: on = 0;
        endcase
        return on;
    endfunction
    */

    function logic draw_digit(input [3:0] num, input [9:0] px, input [9:0] py,
                              input [9:0] ox, input [9:0] oy,
                              input [5:0] w, input [5:0] h);
        // 7-segment 논리: 가로 4px, 세로 8px 크기 가정 (스케일 조정 가능)
        // a,b,c,d,e,f,g 세그먼트
        logic seg_a, seg_b, seg_c, seg_d, seg_e, seg_f, seg_g;
        logic on;

        // 상대 좌표 (확대 2배: 가로 8, 세로 16 정도)
        int dx, dy;
        dx = (px - ox) >> 1;
        dy = (py - oy) >> 1;

        // 범위 체크 (0~5, 0~9)
        if (dx < 0 || dx > w || dy < 0 || dy > h) return 0;

        // 세그먼트 정의
        seg_a = (dy == 0) && (dx > 0 && dx < w);
        seg_b = (dx == w) && (dy > 0 && dy < w);
        seg_c = (dx == w) && (dy > w && dy < h);
        seg_d = (dy == h) && (dx > 0 && dx < w);
        seg_e = (dx == 0) && (dy > w && dy < h);
        seg_f = (dx == 0) && (dy > 0 && dy < w);
        seg_g = (dy == w) && (dx > 0 && dx < w);

        case (num)
            0:       on = seg_a | seg_b | seg_c | seg_d | seg_e | seg_f;
            1:       on = seg_b | seg_c;
            2:       on = seg_a | seg_b | seg_d | seg_e | seg_g;
            3:       on = seg_a | seg_b | seg_c | seg_d | seg_g;
            4:       on = seg_b | seg_c | seg_f | seg_g;
            5:       on = seg_a | seg_c | seg_d | seg_f | seg_g;
            6:       on = seg_a | seg_c | seg_d | seg_e | seg_f | seg_g;
            7:       on = seg_a | seg_b | seg_c | seg_f;
            8:       on = seg_a | seg_b | seg_c | seg_d | seg_e | seg_f | seg_g;
            9:       on = seg_a | seg_b | seg_c | seg_d | seg_f | seg_g;
            default: on = 0;
        endcase
        return on;
    endfunction

    // 1. SCORE
    assign is_score_pixel = draw_digit(
        score / 10, x_pixel, y_pixel, 580, 30, 4, 8
    ) || draw_digit(
        score % 10, x_pixel, y_pixel, 600, 30, 4, 8
    );

    // 2. TIME
    assign is_time_pixel = draw_digit(
        time_left / 10, x_pixel, y_pixel, 280, 30, 4, 8
    ) || draw_digit(
        time_left % 10, x_pixel, y_pixel, 300, 30, 4, 8
    );

    // 3. SHOT
    assign is_shot_pixel = draw_digit(
        shot_left / 10, x_pixel, y_pixel, 520, 30, 4, 8
    ) || draw_digit(
        shot_left % 10, x_pixel, y_pixel, 540, 30, 4, 8
    );

    // 4. START_TIMER
    assign is_start_timer_pixel = start_timer_on && (draw_digit(
        start_timer / 10, x_pixel, y_pixel, 260, 240, 20, 40
    ) || draw_digit(
        start_timer, x_pixel, y_pixel, 320, 240, 20, 40
    ));

    // --- 타겟 영역 계산 ---
    logic is_in_target_area;
    assign is_in_target_area = target_on && 
        (x_pixel >= target_x - TARGET_SIZE_HALF) && (x_pixel < target_x + TARGET_SIZE_HALF) &&
        (y_pixel >= target_y - TARGET_SIZE_HALF) && (y_pixel < target_y + TARGET_SIZE_HALF);

    // --- 픽셀 렌더링 로직 ---
    always_comb begin
        logic [11:0] pixel_color;

        // 1. 기본 색상: 배경
        pixel_color = img_bg;

        // 2. 타겟 렌더링 (5-Color)
        if (is_in_target_area) begin
            logic [5:0] rel_x, rel_y;
            logic [5:0]
                dist_x, dist_y;  // Center로부터의 거리 (절댓값)
            logic [4:0] max_dist;  // 중심으로부터의 최대 거리 (D)

            rel_x = x_pixel - (target_x - TARGET_SIZE_HALF);  // 0 ~ 31
            rel_y = y_pixel - (target_y - TARGET_SIZE_HALF);  // 0 ~ 31

            // 중심으로부터의 거리 계산 (Center = TARGET_SIZE_HALF = 16 가정)
            // $dist\_x = |rel\_x - 16|$
            dist_x = (rel_x > TARGET_SIZE_HALF) ? (rel_x - TARGET_SIZE_HALF) : (TARGET_SIZE_HALF - rel_x);
            // $dist\_y = |rel\_y - 16|$
            dist_y = (rel_y > TARGET_SIZE_HALF) ? (rel_y - TARGET_SIZE_HALF) : (TARGET_SIZE_HALF - rel_y);

            // 최대 거리 (D) 계산: 동심원 형태 대신 동심 사각형 형태의 영역을 만듦
            max_dist = (dist_x > dist_y) ? dist_x : dist_y;

            // 5단계 색상 영역 판단 (가장 안쪽부터 판단)
            if (max_dist < 4) begin
                // D < 4 (중심 8x8) -> Zone 1 (예: 노랑)
                pixel_color = TARGET_COLOR_Z1;
            end else if (max_dist < 7) begin
                // 4 <= D < 7 -> Zone 2 (예: 빨강)
                pixel_color = TARGET_COLOR_Z2;
            end else if (max_dist < 10) begin
                // 7 <= D < 10 -> Zone 3 (예: 파랑)
                pixel_color = TARGET_COLOR_Z3;
            end else if (max_dist < 13) begin
                // 10 <= D < 13 -> Zone 4 (예: 검정)
                pixel_color = TARGET_COLOR_Z4;
            end else begin
                // 13 <= D <= 16 -> Zone 5 (예: 흰색)
                pixel_color = TARGET_COLOR_Z5;
            end
        end

        // 3. AIM (조준점)
        if (aim_detected) begin
            if ((y_pixel >= aim_y - THK) && (y_pixel <= aim_y + THK) &&
                (x_pixel >= aim_x - LEN) && (x_pixel <= aim_x + LEN)) begin
                pixel_color = AIM_COLOR;
            end 
            else if ((x_pixel >= aim_x - THK) && (x_pixel <= aim_x + THK) &&
                (y_pixel >= aim_y - LEN) && (y_pixel <= aim_y + LEN)) begin
                pixel_color = AIM_COLOR;
            end
        end

        // 4. 점수, 시간, 탄환 표시 (가장 최상위 레이어)
        if (is_score_pixel) begin
            pixel_color = SCORE_COLOR;
        end
        if (is_time_pixel) begin
            pixel_color = SCORE_COLOR;
        end
        if (is_shot_pixel) begin
            pixel_color = SCORE_COLOR;
        end

        if (is_start_timer_pixel) begin
            pixel_color = TIMER_COLOR;  // 혹은 다른 색상 (예: RED)
        end

        {r_port, g_port, b_port} = pixel_color;
    end

endmodule

