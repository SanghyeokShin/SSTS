`timescale 1ns / 1ps

module soldier_top (
    // global side
    input  logic       clk,
    input  logic       reset,
    // game logic
    input  logic       btn_fire,
    input  logic       btn_start,
    input  logic       sw_cam,
    // OV7670 side
    output logic       xclk,
    input  logic       pclk,
    input  logic       href,
    input  logic       vsync,
    input  logic [7:0] data,
    // VGA side
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] r_port,
    output logic [3:0] g_port,
    output logic [3:0] b_port,
    // SCCB side
    output logic       SIO_C,
    output logic       SIO_D,
    // --- I2C Master Interface ---
    input  logic       scl,
    inout  logic       sda,
    output logic [3:0] i2c_slave_state_debug,
    output logic       aim_detected_led
);

    // global side
    logic                     sys_clk;

    // VGA side
    logic                     DE;
    logic [              9:0] x_pixel;
    logic [              9:0] y_pixel;

    // OV7670 side
    logic                     wclk;
    logic                     we;
    logic [             16:0] wAddr;  // [$clog2(320*240)-1:0] 
    logic [             15:0] wData;
    logic                     rclk;
    logic                     oe;
    logic [             16:0] rAddr;  // [$clog2(320*240)-1:0] 
    logic [             15:0] rData;  //imgData of IMG_MEM_READER

    // ROM side
    logic [$clog2(80*60)-1:0] rom_Addr;
    logic [15:0] rom_forest, rom_desert, rom_snow, rom_data;

    // img side ???
    logic [1:0] bg_sel;
    logic [11:0] img_cam, img_rom, img_color, img_gray, img_bg;

    // game side
    logic o_fire, o_start;
    logic [9:0] aim_x, aim_y;
    logic aim_detected;
    logic [9:0] target_x, target_y;
    logic target_on, start_timer_on;
    logic [4:0] score;
    logic [5:0] time_limit, time_left;
    logic [4:0] shot_limit, shot_left;
    logic [2:0] start_timer;
    logic game_ready, game_setting, setting_done, game_over;

    // i2c side
    logic [7:0] i2c_data;
    logic [7:0] slave2master;

    // led debug
    assign aim_detected_led = aim_detected;

    assign xclk = sys_clk;


    button_debounce #(
        .F_BTN  (1_000_000),
        .NUM_DEB(32)
    ) U_BD_START (
        .clk  (sys_clk),
        .reset(reset),
        .i_btn(btn_start),
        .o_btn(o_start)
    );

    button_debounce #(
        .F_BTN  (1_000_000),
        .NUM_DEB(32)
    ) U_BD_FIRE (
        .clk  (sys_clk),
        .reset(reset),
        .i_btn(btn_fire),
        .o_btn(o_fire)
    );

    sccb U_SCCB (
        .clk  (clk),
        .reset(reset),
        .SIO_D(SIO_D),
        .SIO_C(SIO_C)
    );

    pixel_clk_gen P_CLK_GEN (
        .clk  (clk),
        .reset(reset),
        .pclk (sys_clk)
    );

    VGA_Syncher U_VGA_SYNCHER (
        .clk    (sys_clk),
        .reset  (reset),
        .h_sync (h_sync),
        .v_sync (v_sync),
        .DE     (DE),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel)
    );

    image_reader U_IMG_ROM_READER (
        .DE     (DE),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .addr   (rAddr),
        .imgData(rData),
        .r_port (img_cam[11:8]),
        .g_port (img_cam[7:4]),
        .b_port (img_cam[3:0])
    );

    background_image_reader U_background_image_reader (
        .DE     (DE),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .addr   (rom_Addr),
        .imgData(rom_data),
        .r_port (img_rom[11:8]),
        .g_port (img_rom[7:4]),
        .b_port (img_rom[3:0])
    );

    grayFilter U_grayFilter (
        .i_r(img_rom[11:8]),
        .i_g(img_rom[7:4]),
        .i_b(img_rom[3:0]),
        .o_r(img_gray[11:8]),
        .o_g(img_gray[7:4]),
        .o_b(img_gray[3:0])
    );

    ImgROM #(
        .MEM_FILE("forest.mem")
    ) U_ImgROM_Forest (
        .clk (sys_clk),
        .addr(rom_Addr),
        .data(rom_forest)
    );

    ImgROM #(
        .MEM_FILE("desert.mem")
    ) U_ImgROM_Desert (
        .clk (sys_clk),
        .addr(rom_Addr),
        .data(rom_desert)
    );

    ImgROM #(
        .MEM_FILE("snow.mem")
    ) U_ImgROM_Snow (
        .clk (sys_clk),
        .addr(rom_Addr),
        .data(rom_snow)
    );

    mux_nx1 #(
        .BIT_SIZE(16)
    ) U_MUX_ROM (
        .sel  (bg_sel),
        .rom_0(rom_forest),
        .rom_1(rom_desert),
        .rom_2(rom_snow),
        .rom  (rom_data)
    );


    game_controller U_GAME_CONTROLLER (
        .clk           (sys_clk),
        .reset         (reset),
        .btn_start     (o_start),
        .btn_fire      (o_fire),
        .aim_x         (aim_x),
        .aim_y         (aim_y),
        .aim_detected  (aim_detected),
        .i2c_data      (i2c_data),
        .game_setting  (game_setting),
        .target_x      (target_x),
        .target_y      (target_y),
        .target_on     (target_on),
        .start_timer_on(start_timer_on),
        .score         (score),
        .slave2master  (slave2master),
        .time_left     (time_left),
        .shot_left     (shot_left),
        .start_timer   (start_timer),
        .game_ready    (game_ready),
        .game_over     (game_over),
        .bg_sel        (bg_sel)
    );

    mux_2x1 U_MUX_GRAY (
        .sel(game_ready),
        .x0 (img_rom),
        .x1 (img_gray),
        .y  (img_color)
    );

    mux_2x1 U_MUX_CAM (
        .sel(sw_cam),
        .x0 (img_color),
        .x1 (img_cam),
        .y  (img_bg)
    );

    pixel_mixer U_PIXEL_MIXER (
        .img_bg        (img_bg),
        .aim_x         (aim_x),
        .aim_y         (aim_y),
        .x_pixel       (x_pixel),
        .y_pixel       (y_pixel),
        .target_x      (target_x),
        .target_y      (target_y),
        .target_on     (target_on),
        .score         (score),
        .time_left     (time_left),
        .shot_left     (shot_left),
        .start_timer   (start_timer),
        .start_timer_on(start_timer_on),
        .aim_detected  (aim_detected),
        .r_port        (r_port),
        .g_port        (g_port),
        .b_port        (b_port)
    );

    frame_buffer U_FRAME_BUFFER (
        // write side
        .wclk (pclk),
        .we   (we),
        .wAddr(wAddr),  // [$clog2(320*240)-1:0] 
        .wData(wData),
        // read side 
        .rclk (sys_clk),
        .oe   (1'b1),
        .rAddr(rAddr),  // [$clog2(320*240)-1:0] 
        .rData(rData)
    );

    OV7670_controller U_OV7670_MEM_CONTROLLER (
        .pclk (pclk),
        .reset(reset),
        // OV7670 side
        .href (href),
        .vsync(vsync),
        .data (data),
        // memory side
        .we   (we),
        .wAddr(wAddr),  // 320 * 240
        .wData(wData)
    );

    red_tracker U_RED_TRACKER (
        .clk         (sys_clk),
        .reset       (reset),
        .v_sync      (v_sync),
        .DE          (DE),
        .x_pixel     (x_pixel),
        .y_pixel     (y_pixel),
        .data        (rData),
        .aim_x       (aim_x),
        .aim_y       (aim_y),
        .aim_detected(aim_detected)
    );

    i2c_slave U_I2C_SLAVE (
        .clk                  (clk),
        .reset                (reset),
        .scl                  (scl),
        .sda                  (sda),
        .s_tx_data            (slave2master),
        .s_rx_data            (i2c_data),
        .i2c_slave_state_debug(i2c_slave_state_debug),
        .game_setting         (game_setting),
        .game_over            (game_over)
    );

endmodule
