`timescale 1ns / 1ps

module i2c_controller (
    input logic clk,
    input logic reset,

    // User Command Interface
    input  logic [1:0] i_soldier,  // 선택된 타겟 (0:Soldier0, 1:Soldier1, 2:Soldier2)
    input logic i_btn_send,  // 설정 전송(Write) 버튼
    input logic i_btn_read,  // 점수 읽기(Read) 버튼
    input logic i_btn_all,  // 동시 명령 버튼 (sw_mode==0일 때는 WRITE ALL, sw_mode==1일 때는 READ ALL)
    input logic [7:0] i_config_data,  // 보낼 설정값

    // [신규] 모드 전환 스위치 입력
    input logic i_sw_mode,  // 0: Setting, 1: Result

    // I2C Master Interface
    input logic       i_tx_ready,
    input logic       i_tx_done,
    input logic       i_rx_done,
    input logic [7:0] i_rx_data,

    output logic       o_i2c_en,
    output logic       o_i2c_stop,
    output logic       o_i2c_start,
    output logic [7:0] o_tx_data,

    // Output Registers (Received Scores)
    output logic [4:0] o_score_0,
    output logic [4:0] o_score_1,
    output logic [4:0] o_score_2,

    // Debug
    output logic [3:0] i2c_control_state_debug,
    output logic [3:0] state_all_reg_debug
    
);

    // Slave Addresses (7-bit)
    // Write: {Addr, 0}, Read: {Addr, 1}
    // 예: Soldier 0 (0x32) -> W:0x64, R:0x65
    //     Soldier 1 (0x33) -> W:0x66, R:0x67
    //     Soldier 2 (0x34) -> W:0x68, R:0x69

    logic [7:0] addr_w, addr_r;
    logic [7:0] addr_w_all, addr_r_all;

    // Button Edge Detection
    logic send_d, read_d, all_d;
    logic send_start, read_start, all_start;


    logic score_done;

    always_ff @(posedge clk) begin
        send_d <= i_btn_send;
        read_d <= i_btn_read;
        all_d  <= i_btn_all;
    end
    assign send_start = i_btn_send && !send_d;  // Posedge
    assign read_start = i_btn_read && !read_d;  // Posedge
    assign all_start  = i_btn_all && !all_d;  // Posedge



    ////////////////////////////////
    ////////  동시 명령 모드 START
    ////////////////////////////////
    // FSM States

    logic all_busy;
    logic all_setting;
    logic all_result;


    logic setting_done;
    logic result_done;

    typedef enum logic [3:0] {
        IDLE_ALL,
        SETTING_1,
        SETTING_DONE_1,
        SETTING_2,
        SETTING_DONE_2,
        SETTING_3,
        SETTING_DONE_3,
        RESULT_1,
        RESULT_DONE_1,
        RESULT_2,
        RESULT_DONE_2,
        RESULT_3,
        RESULT_DONE_3
    } state_all;
    state_all state_all_reg, state_all_next;

    // Sequential Logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state_all_reg <= IDLE_ALL;
        end else begin
            state_all_reg <= state_all_next;
        end
    end

    // Combinational Logic (FSM)
    always_comb begin
        // Default Outputs
        all_busy = 0;
        all_setting = 0;
        all_result = 0;
        state_all_next = state_all_reg;
        addr_w_all = 8'h64;
        addr_r_all = 8'h65;
        case (state_all_reg)
            IDLE_ALL: begin
                all_busy = 0;
                all_setting = 0;
                all_result = 0;
                if (all_start) begin
                    if (i_sw_mode == 0) begin
                        state_all_next = SETTING_1;
                    end else begin
                        state_all_next = RESULT_1;
                    end
                end
            end
            SETTING_1: begin
                all_busy = 1;
                all_setting = 1;
                all_result = 0;
                addr_w_all = 8'h64;
                if (!setting_done) state_all_next = SETTING_DONE_1;
            end
            SETTING_DONE_1: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 0;
                addr_w_all = 8'h64;
                if (setting_done) state_all_next = SETTING_2;
            end
            SETTING_2: begin
                all_busy = 1;
                all_setting = 1;
                all_result = 0;
                addr_w_all = 8'h66;
                if (!setting_done) state_all_next = SETTING_DONE_2;
            end
            SETTING_DONE_2: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 0;
                addr_w_all = 8'h66;
                if (setting_done) state_all_next = SETTING_3;

            end
            SETTING_3: begin
                all_busy = 1;
                all_setting = 1;
                all_result = 0;
                addr_w_all = 8'h68;
                if (!setting_done) state_all_next = SETTING_DONE_3;

            end
            SETTING_DONE_3: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 0;
                addr_w_all = 8'h68;
                if (setting_done) state_all_next = IDLE_ALL;

            end
            RESULT_1: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 1;
                addr_r_all = 8'h65;
                if (!setting_done) state_all_next = RESULT_DONE_1;

            end
            RESULT_DONE_1: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 0;
                addr_r_all = 8'h65;
                if (result_done) state_all_next = RESULT_2;

            end
            RESULT_2: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 1;
                addr_r_all = 8'h67;
                if (!setting_done) state_all_next = RESULT_DONE_2;

            end
            RESULT_DONE_2: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 0;
                addr_r_all = 8'h67;
                if (result_done) state_all_next = RESULT_3;

            end
            RESULT_3: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 1;
                addr_r_all = 8'h69;
                if (!setting_done) state_all_next = RESULT_DONE_3;

            end
            RESULT_DONE_3: begin
                all_busy = 1;
                all_setting = 0;
                all_result = 0;
                addr_r_all = 8'h69;
                if (result_done) state_all_next = IDLE_ALL;
            end
        endcase
    end



    ////////////////////////////////
    ////////  동시 명령 모드 END
    ////////////////////////////////


    always_comb begin
        if (all_busy == 0) begin
            case (i_soldier)
                2'b00: begin
                    addr_w = 8'h64;
                    addr_r = 8'h65;
                end  // Slave 0 (0x32)
                2'b01: begin
                    addr_w = 8'h66;
                    addr_r = 8'h67;
                end  // Slave 1 (0x33)
                2'b10: begin
                    addr_w = 8'h68;
                    addr_r = 8'h69;
                end  // Slave 2 (0x34)
                default: begin
                    addr_w = 8'h64;
                    addr_r = 8'h65;
                end
            endcase
        end else begin  // all_busy == 1
            addr_w = addr_w_all;
            addr_r = addr_r_all;
        end
    end

    // Score Registers
    logic [4:0] score_0, score_1, score_2;
    assign o_score_0 = score_0;
    assign o_score_1 = score_1;
    assign o_score_2 = score_2;

    // FSM States
    typedef enum logic [3:0] {
        IDLE,
        // Write Sequence (Config)
        W_ADDR,
        W_WAIT,
        W_DATA,
        W_DONE,
        W_STOP,
        // Read Sequence (Score)
        R_ADDR,
        R_WAIT,
        R_READ,
        R_DONE,
        R_STOP
    } state_t;

    state_t state, state_next;
    assign i2c_control_state_debug = state;
    assign state_all_reg_debug = state_all_reg;

    // Sequential Logic
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state   <= IDLE;
            score_0 <= 0;
            score_1 <= 0;
            score_2 <= 0;
        end else begin
            state <= state_next;

            // 데이터 수신 완료 시 해당 타겟 레지스터에 저장
            if (score_done) begin
                case (i_soldier)
                    2'd0: score_0 <= i_rx_data[4:0];
                    2'd1: score_1 <= i_rx_data[4:0];
                    2'd2: score_2 <= i_rx_data[4:0];
                endcase
            end
        end
    end

    // Combinational Logic (FSM)
    always_comb begin
        // Default Outputs
        o_i2c_en    = 1'b0;
        o_i2c_start = 1'b0;
        o_i2c_stop  = 1'b0;
        o_tx_data   = 8'h00;

        score_done = 1'b0;
        setting_done = 1'b0;
        result_done = 1'b0;
        state_next  = state;
        case (state)
            IDLE: begin
                setting_done = 1'b1;
                result_done = 1'b1;
                o_i2c_en    = 1'b0;
                o_i2c_start = 1'b0;
                o_i2c_stop  = 1'b0;
                if (all_busy == 0) begin
                    if (i_tx_ready) begin
                        if (send_start)
                            state_next = W_ADDR;  // SEND 버튼 -> 쓰기
                        else if (read_start)
                            state_next = R_ADDR;  // READ 버튼 -> 읽기
                    end
                end else begin
                    if (i_tx_ready) begin
                        if (all_setting)
                            state_next = W_ADDR;  // SEND 버튼 -> 쓰기
                        else if (all_result)
                            state_next = R_ADDR;  // READ 버튼 -> 읽기
                    end
                end

            end

            // ----------------------------------------------------
            // WRITE Sequence: [Start] -> [Addr+W] -> [Config] -> [Stop]
            // ----------------------------------------------------
            W_ADDR: begin
                o_i2c_en    = 1'b1;
                o_i2c_stop  = 1'b0;
                o_i2c_start = 1'b1;
                o_tx_data   = addr_w;
                if (i_tx_ready) state_next = W_WAIT;
            end
            W_WAIT: begin
                o_i2c_en    = 1'b0;
                o_i2c_stop  = 1'b0;
                o_i2c_start = 1'b0;
                state_next = W_DATA;
            end
            W_DATA: begin
                o_i2c_en    = 1'b1;
                o_i2c_stop  = 1'b0;
                o_i2c_start = 1'b0;
                o_tx_data = i_config_data;  // 설정값 전송
                if (i_tx_ready) begin
                    state_next = W_STOP;
                end
            end
            W_STOP: begin
                o_i2c_en    = 1'b1;
                o_i2c_stop  = 1'b1;
                o_i2c_start = 1'b0;
                if (i_tx_ready) begin
                    state_next = IDLE;
                end
            end

            // ----------------------------------------------------
            // READ Sequence: [Start] -> [Addr+R] -> [Data(NACK)] -> [Stop]
            // ----------------------------------------------------
            // 1바이트만 읽으므로 바로 NACK을 보내서 끝냅니다.
            R_ADDR: begin
                o_i2c_en    = 1'b1;
                o_i2c_stop  = 1'b0;
                o_i2c_start = 1'b1;
                o_tx_data   = addr_r;
                if (i_tx_ready) state_next = R_WAIT;
            end
            R_WAIT: begin
                o_i2c_en    = 1'b0;
                o_i2c_stop  = 1'b0;
                o_i2c_start = 1'b0;
                state_next = R_READ;
            end
            R_READ: begin
                // Read NACK Mode (Last/Single Byte): en=0, start=1, stop=1
                o_i2c_en    = 1'b0;
                o_i2c_start = 1'b1;
                o_i2c_stop  = 1'b1;

                // i_rx_done 시점에 데이터는 Sequential 블록에서 캡처됨
                if (i_tx_ready) state_next = R_STOP;
            end
            R_STOP: begin
                o_i2c_en    = 1'b1;
                o_i2c_stop  = 1'b1;
                o_i2c_start = 1'b0;
                score_done = 1'b1;
                if (i_tx_ready) begin
                    state_next = IDLE;
                end
            end
        endcase
    end

endmodule
