`timescale 1ns / 1ps

module commander_top (
    input logic clk,
    input logic reset,

    // --- User Interface ---
    input logic [1:0] sw,  // sw[0]: Mode Select (0:Setting, 1:Result)
    input logic [3:0] btn, // btn[0]:Select, btn[1]:Send, btn[2]:Read

    // --- OV7670 side ---
    output logic       xclk,
    input  logic       pclk,
    input  logic       href,
    input  logic       vsync,
    input  logic [7:0] data,
    output logic       SIO_C,
    output logic       SIO_D,

    // --- VGA side ---
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] r_port,
    output logic [3:0] g_port,
    output logic [3:0] b_port,

    // --- I2C Master Interface ---
    output logic scl,
    inout  logic sda,

    // debugging LED
    output logic [3:0] i2c_control_state_debug,  // led[3:0]
    output logic [4:0] i2c_master_state_debug,   // led[7:4]
    output logic [3:0] state_all_reg_debug,  // led[14:11]
    output logic       led_red_detected      //led[15]
);

    logic sys_clk;
    assign xclk = sys_clk;

    // 비디오 신호
    logic DE;
    logic [9:0] x_pixel, y_pixel;
    logic we;
    logic [16:0] wAddr, rAddr;
    logic [15:0] wData, rData;

    logic [3:0] cam_r, cam_g, cam_b;
    logic [3:0] final_r, final_g, final_b;

    // Tracker 신호
    logic [9:0] aim_x, aim_y;
    logic aim_detected;
    assign led_red_detected = aim_detected;

    // I2C & Controller 신호
    logic i2c_en, i2c_stop, i2c_start;
    logic tx_ready, tx_done, rx_done;
    logic [7:0] tx_data, rx_data;

    // System State & Config Connection
    logic [7:0] current_config;  // 설정값
    logic [1:0] soldier;  // 선택된 Soldier 번호
    logic       ui_mode;  // 0: Setting, 1: Result
    logic [3:0] fsm_state;

    // Data Signals (Score & Rank)
    logic [4:0] score_0, score_1, score_2;
    logic [1:0] rank_0, rank_1, rank_2;

    // -------------------------------------------------------
    // System Modules (Clocks, VGA, Camera, Tracker)
    // -------------------------------------------------------
    pixel_clk_gen P_CLK_GEN (
        .clk  (clk),
        .reset(reset),
        .pclk (sys_clk)
    );

    VGA_Syncher U_VGA_SYNCHER (
        .clk(sys_clk),
        .reset(reset),
        .h_sync(h_sync),
        .v_sync(v_sync),
        .DE(DE),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel)
    );

    sccb U_SCCB (
        .clk  (clk),
        .reset(reset),
        .SIO_D(SIO_D),
        .SIO_C(SIO_C)
    );

    OV7670_controller U_OV7670_CTRL (
        .pclk(pclk),
        .reset(reset),
        .href(href),
        .vsync(vsync),
        .data(data),
        .we(we),
        .wAddr(wAddr),
        .wData(wData)
    );

    frame_buffer U_FRAME_BUFFER (
        .wclk(pclk),
        .we(we),
        .wAddr(wAddr),
        .wData(wData),
        .rclk(sys_clk),
        .oe(1'b1),
        .rAddr(rAddr),
        .rData(rData)
    );

    image_reader U_IMG_READER (
        .DE(DE),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .addr(rAddr),
        .imgData(rData),
        .r_port(cam_r),
        .g_port(cam_g),
        .b_port(cam_b)
    );

    red_tracker U_RED_TRACKER (
        .clk(sys_clk),
        .reset(reset),
        .i_vsync(v_sync),
        .i_de(DE),
        .i_x(x_pixel),
        .i_y(y_pixel),
        .i_data(rData),
        .o_target_x(aim_x),
        .o_target_y(aim_y),
        .o_detected(aim_detected)
    );

    // -------------------------------------------------------
    // 1. Commander Controller (Logic & Calc)
    // -------------------------------------------------------
    commander_controller U_COMM_CONTROLLER (
        .clk  (sys_clk),
        .reset(reset),

        // Inputs
        .i_aim_x     (aim_x),
        .i_aim_y     (aim_y),
        .i_btn_select(btn[0]),
        .i_sw_mode   (sw[0]),    // [신규] 스위치 입력 (모드 전환)
        .i_score_0   (score_0),
        .i_score_1   (score_1),
        .i_score_2   (score_2),

        // Outputs
        .o_config (current_config),
        .o_soldier(soldier),
        .o_ui_mode(ui_mode),         // -> UI
        .o_rank_0 (rank_0),
        .o_rank_1 (rank_1),
        .o_rank_2 (rank_2)
    );

    // -------------------------------------------------------
    // 2. I2C Controller (Communication)
    // -------------------------------------------------------
    i2c_controller U_I2C_CONTROLLER (
        .clk  (clk),
        .reset(reset),

        .i_soldier(soldier),
        .i_btn_send(btn[1]),
        .i_btn_read(btn[2]),
        .i_btn_all(btn[3]),
        .i_config_data(current_config),
        .i_sw_mode(sw[0]),  // [신규] 스위치 입력 (모드 전환)

        .i_tx_ready(tx_ready),
        .i_tx_done (tx_done),
        .i_rx_done (rx_done),
        .i_rx_data (rx_data),
        .o_i2c_en(i2c_en),
        .o_i2c_stop(i2c_stop),
        .o_i2c_start(i2c_start),
        .o_tx_data(tx_data),

        .o_score_0(score_0),
        .o_score_1(score_1),
        .o_score_2(score_2),
        .i2c_control_state_debug(i2c_control_state_debug),
        .state_all_reg_debug(state_all_reg_debug)
    );

    // -------------------------------------------------------
    // 3. UI Generation (Display)
    // -------------------------------------------------------
    commander_ui_gen U_UI_GEN (
        .clk  (sys_clk),
        .reset(reset),
        .i_x  (x_pixel),
        .i_y  (y_pixel),
        .i_de (DE),

        .i_config (current_config),
        .i_soldier(soldier),
        .i_ui_mode(ui_mode),         // 화면 모드 (0:Setting, 1:Result)

        .i_score_0(score_0),
        .i_score_1(score_1),
        .i_score_2(score_2),
        .i_rank_0 (rank_0),
        .i_rank_1 (rank_1),
        .i_rank_2 (rank_2),

        .i_bg_r(cam_r),
        .i_bg_g(cam_g),
        .i_bg_b(cam_b),
        .i_aim_x(aim_x),
        .i_aim_y(aim_y),
        .i_aim_detected(aim_detected),

        .o_r(final_r),
        .o_g(final_g),
        .o_b(final_b)
    );

    // -------------------------------------------------------
    // 4. I2C Master Driver
    // -------------------------------------------------------
    i2c_master U_I2C_MASTER (
        .clk(clk),
        .reset(reset),
        .scl(scl),
        .sda(sda),
        .i2c_en(i2c_en),
        .i2c_stop(i2c_stop),
        .i2c_start(i2c_start),
        .tx_ready(tx_ready),
        .tx_done(tx_done),
        .rx_done(rx_done),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .i2c_master_state_debug(i2c_master_state_debug)
    );

    assign r_port = final_r;
    assign g_port = final_g;
    assign b_port = final_b;
endmodule
