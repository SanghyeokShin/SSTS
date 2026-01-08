`timescale 1ns / 1ps

module red_tracker (
    input  logic        clk,
    input  logic        reset,
    
    // VGA 신호 (현재 화면에 그려지고 있는 픽셀 정보)
    input  logic        i_vsync,   // 프레임 종료 감지용
    input  logic        i_de,      // 픽셀 유효 신호 (Data Enable)
    input  logic [9:0]  i_x,       // 현재 픽셀 X 좌표
    input  logic [9:0]  i_y,       // 현재 픽셀 Y 좌표
    input  logic [15:0] i_data,    // RGB565 데이터 (From Frame Buffer)

    // 결과 출력 (계산된 중심 좌표)
    output logic [9:0]  o_target_x,
    output logic [9:0]  o_target_y,
    output logic        o_detected // 빨간 물체 감지 여부
);

    // 1. 빨간색 판별 (Threshold 튜닝 필요)
    // RGB565 format: R[15:11], G[10:5], B[4:0]
    logic [4:0] r_val;
    logic [5:0] g_val;
    logic [4:0] b_val;

    assign r_val = i_data[15:11];
    assign g_val = i_data[10:5];
    assign b_val = i_data[4:0];

    logic is_red;
    // 조건: Red가 20 이상(Max 31)이고, Green/Blue가 적을 때
    assign is_red = (r_val > 5'd20) && (g_val < 6'd15) && (b_val < 5'd15);

    // 2. Bounding Box 레지스터
    // [수정] 12비트로 확장하여 오버플로우 원천 차단 (4096 범위)
    logic [11:0] x_min, x_max; 
    logic [11:0] y_min, y_max; // Y좌표도 안전하게 12비트로 통일
    logic [16:0] pixel_count; // 감지된 빨간 픽셀 수

    // VSYNC 엣지 검출 (프레임 시작 감지)
    logic vsync_d;
    logic vsync_start; // Vsync Rising Edge (프레임 끝/다음 시작)
    
    always_ff @(posedge clk) begin
        vsync_d <= i_vsync;
    end
    assign vsync_start = i_vsync && !vsync_d; // Positive Edge

    // 3. 메인 로직
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            o_target_x <= 0;
            o_target_y <= 0;
            o_detected <= 0;
            // 초기화 값: 12비트 최대값 근처로 넉넉하게 설정하여 비교 오류 방지
            x_min <= 12'd4095; x_max <= 0; 
            y_min <= 12'd4095; y_max <= 0;
            pixel_count <= 0;
        end else begin
            if (vsync_start) begin
                // --- 프레임 종료: 결과 업데이트 ---
                if (pixel_count > 50) begin // 노이즈 방지
                    o_detected <= 1'b1;
                    
                    // [수정 완료] 12비트 연산
                    // (최대 1023 + 1023 = 2046)은 12비트(4095) 안에 아주 여유롭게 들어갑니다.
                    o_target_x <= (x_min + x_max) >> 1;
                    o_target_y <= (y_min + y_max) >> 1;
                    
                end else begin
                    o_detected <= 1'b0; // 물체 없음
                end

                // 다음 프레임을 위해 초기화
                x_min <= 12'd4095; x_max <= 0;
                y_min <= 12'd4095; y_max <= 0;
                pixel_count <= 0;

            end else begin
                // --- 프레임 진행 중: 빨간색 탐색 ---
                
                // [수정] 화면 가장자리 (좌우 10픽셀) 노이즈 무시
                // i_x < 10 인 구간의 노이즈가 x_min을 0으로 만드는 것을 방지합니다.
                if (i_de && is_red && (i_x > 10) && (i_x < 630)) begin
                    pixel_count <= pixel_count + 1;
                    
                    // [수정] 10비트 입력을 12비트 그릇에 담아 비교
                    if ({2'b00, i_x} < x_min) x_min <= {2'b00, i_x};
                    if ({2'b00, i_x} > x_max) x_max <= {2'b00, i_x};
                    
                    if ({2'b00, i_y} < y_min) y_min <= {2'b00, i_y};
                    if ({2'b00, i_y} > y_max) y_max <= {2'b00, i_y};
                end
            end
        end
    end

endmodule