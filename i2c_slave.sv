`timescale 1ns / 1ps

module i2c_slave (
    // global signals 
    input logic clk,
    input logic reset,
    // I2C signals
    input logic scl,
    inout logic sda,

    // FND signals
    input  logic [7:0] s_tx_data,
    output logic [7:0] s_rx_data,
    output logic [3:0] i2c_slave_state_debug,

    // game ready 세팅값반영해서 화면새로고쳐주는 변수.
    output logic game_setting,
    input  logic game_over
);

    // slave address setting
    logic [6:0] slave_addr = 7'b0110010;    // ADDR = 7'h32 (WRITE일 때 8'h64, READ일 때, 8'h65)  
    //    logic [6:0] slave_addr = 7'b0110011;  // ADDR = 7'h33 (WRITE일 때 8'h66, READ일 때, 8'h67)  
    //    logic [6:0] slave_addr = 7'b0110100;  // ADDR = 7'h34 (WRITE일 때 8'h68, READ일 때, 8'h69)  

    /////////// Synchronizer Edge Detector///////////////
    logic scl_sync0, scl_sync1, scl_sync2;
    logic scl_rising, scl_falling;
    logic sda_sync0, sda_sync1, sda_sync2;
    logic sda_rising, sda_falling;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            scl_sync0 <= 1'b1;
            scl_sync1 <= 1'b1;
            scl_sync2 <= 1'b1;
            sda_sync0 <= 1'b1;
            sda_sync1 <= 1'b1;
            sda_sync2 <= 1'b1;
        end else begin
            scl_sync0 <= scl;
            scl_sync1 <= scl_sync0;
            scl_sync2 <= scl_sync1;
            sda_sync0 <= sda_wr;
            sda_sync1 <= sda_sync0;
            sda_sync2 <= sda_sync1;
        end
    end
    assign scl_rising  = scl_sync1 & ~(scl_sync2);
    assign scl_falling = ~(scl_sync1) & scl_sync2;
    assign sda_rising  = sda_sync1 & ~(sda_sync2);
    assign sda_falling = ~(sda_sync1) & sda_sync2;

    // state declaration
    typedef enum {
        S_IDLE,
        S_START,
        S_ADDR_WRITE,
        S_ADDR_COMPARE,
        S_ACK_WRITE1,
        S_ACK_WRITE2,
        S_ACK_READ1,
        S_ACK_READ2,
        S_DATA_WRITE,
        S_DATA_WRITE_DONE,
        S_DATA_READ1,
        S_DATA_READ2
    } state_i2c_slave;
    state_i2c_slave state, state_next;

    assign i2c_slave_state_debug = state;
    // s_sda 3state buffer
    logic s_sda_en;
    logic s_sda_rd;
    assign sda_wr = (~s_sda_en) ? sda : 1'bz;
    assign sda = (s_sda_en) ? s_sda_rd : 1'bz;


    // reg next logic declaration
    logic [2:0] bit_counter_reg, bit_counter_next;  // for 7 count
    logic [7:0] tx_data_reg, tx_data_next;
    logic [7:0] rx_data_reg, rx_data_next;

    // READ or WRITE signals
    logic is_read_reg, is_read_next;

    // READ ACK or READ NACK
    logic is_nack_read_reg, is_nack_read_next;

    // ADDR Compare
    logic is_addr_reg, is_addr_next;


    // assign s_rx_data = rx_data_reg;
    logic [7:0] config_reg;
    assign s_rx_data = config_reg;


    // SL
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state            <= S_IDLE;
            bit_counter_reg  <= 3'd0;
            rx_data_reg      <= 8'd0;
            tx_data_reg      <= s_tx_data;
            is_read_reg      <= 1'b0;
            is_nack_read_reg <= 1'b0;
            is_addr_reg      <= 1'b0;
        end else begin
            state            <= state_next;
            bit_counter_reg  <= bit_counter_next;
            rx_data_reg      <= rx_data_next;
            tx_data_reg      <= tx_data_next;
            is_read_reg      <= is_read_next;
            is_nack_read_reg <= is_nack_read_next;
            is_addr_reg      <= is_addr_next;
            // --- [수정] 래치 로직 변경 ---
            // 래치 신호가 1일 때, rx_data_reg (이미 안정화된 값)을 래치합니다.
            if (game_setting) begin
                config_reg <= rx_data_reg;
            end
            // --------------------------
        end
    end

    // CL
    always_comb begin
        state_next        = state;
        bit_counter_next  = bit_counter_reg;
        s_sda_en          = 1'b0;
        s_sda_rd          = 1'b0;  // 기본값: SDA 출력 시 LOW
        is_read_next      = is_read_reg;
        is_nack_read_next = is_nack_read_reg;
        is_addr_next      = is_addr_reg;
        rx_data_next      = rx_data_reg;  // Latch 방지
        tx_data_next      = tx_data_reg;  // Latch 방지
        game_setting      = 1'b0;  // [추가] 래치 신호 기본값

        // 모든 상태에서 STOP 감지
        if (scl_sync2 && sda_rising) begin
            state_next = S_IDLE;
            bit_counter_next = 3'd0;
            //            rx_data_next = 8'd0;

            //       // 모든 상태에서 START 감지
            //       end else if (scl_sync2 && sda_falling) begin
            //           state_next = S_START;
            //           bit_counter_next = 3'd0;
            //           rx_data_next = 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    bit_counter_next = 3'd0;
                    s_sda_en = 1'b0;
                    is_addr_next = 1'b0;
                    if (scl_sync2 && sda_falling) begin
                        state_next = S_START;
                    end
                end
                S_START: begin
                    s_sda_en = 1'b0;
                    if (scl_falling) begin
                        state_next = S_ADDR_WRITE;
                    end
                end
                S_ADDR_WRITE: begin
                    s_sda_en = 1'b0;
                    if (scl_rising) begin
                        rx_data_next = {rx_data_reg[6:0], sda_sync2};
                        if (bit_counter_reg == 7) begin
                            bit_counter_next = 0;
                            state_next = S_ADDR_COMPARE;
                        end else begin
                            bit_counter_next = bit_counter_reg + 1;
                            state_next = S_ADDR_WRITE;
                        end
                    end
                end
                S_ADDR_COMPARE: begin
                    s_sda_en = 1'b0;
                    if (scl_falling) begin
                        if (rx_data_reg[7:1] == slave_addr) begin
                            is_addr_next = 1'b1;
                            if (rx_data_reg[0] == 1'b0) begin
                                is_read_next = 1'b0;
                            end else begin
                                is_read_next = 1'b1;
                            end
                            state_next = S_ACK_WRITE1;  // rx_data_reg[7] == 1'b1;
                        end else begin
                            state_next = S_IDLE;
                        end
                    end
                end

                /////////////////////////
                /// S_ACK_WRITE 1_bit send
                /////////////////////////

                S_ACK_WRITE1: begin
                    s_sda_en = 1'b1;  // sda_en을 1로 enable하면서 slave가 출력할 수 있도록 한다.
                    s_sda_rd = 1'b0;
                    if (scl_rising) begin
                        state_next = S_ACK_WRITE2;
                    end
                end
                S_ACK_WRITE2: begin
                    s_sda_en = 1'b1;  // sda_en을 1로 enable하면서 slave가 출력할 수 있도록 한다.
                    s_sda_rd = 1'b0;
                    if (scl_falling) begin
                        if (is_read_reg == 1) begin
                            tx_data_next = s_tx_data; // 임시 test용 tx_data sampling 샘플링.
                            state_next = S_DATA_READ1;
                        end else begin
                            state_next = S_DATA_WRITE;
                        end
                    end
                end

                /////////////////////////
                /// S_ACK_READ 1_bit receive
                /////////////////////////

                S_ACK_READ1: begin
                    s_sda_en = 1'b0; // master가 데이터를 더 보낼거면 0, 그만 보낼거면 1 을 보낸다.
                    if (scl_rising) begin
                        is_nack_read_next = sda_sync2;
                        state_next = S_ACK_READ2;
                    end
                end
                S_ACK_READ2: begin
                    s_sda_en = 1'b0;
                    if (scl_falling) begin
                        if (is_nack_read_reg) begin
                            state_next = S_IDLE;
                        end else begin
                            tx_data_next = s_tx_data; // 임시 test용 tx_data sampling 샘플링.
                            state_next = S_DATA_READ1;
                        end
                    end
                end
                S_DATA_WRITE: begin
                    s_sda_en = 1'b0;
                    if (scl_rising) begin
                        rx_data_next = {rx_data_reg[6:0], sda_sync2};
                        if (bit_counter_reg == 7) begin
                            bit_counter_next = 0;
                            state_next = S_DATA_WRITE_DONE;
                        end else begin
                            bit_counter_next = bit_counter_reg + 1;
                        end
                    end
                end
                // rx_data는 S_DATA_WRITE_DONE 이 때 출력으로 만들 수 있다.
                S_DATA_WRITE_DONE: begin
                    s_sda_en = 1'b0;
                    game_setting = 1'b1;
                    if (scl_falling) begin
                        state_next = S_ACK_WRITE1;
                    end
                end
                S_DATA_READ1: begin
                    s_sda_en = 1'b1; // sda_en을 1로 enable하면서 slave가 출력할 수 있도록 한다.
                    s_sda_rd = tx_data_reg[7];
                    if (scl_rising) begin
                        state_next = S_DATA_READ2;
                    end
                end
                S_DATA_READ2: begin
                    s_sda_en = 1'b1; // sda_en을 1로 enable하면서 slave가 출력할 수 있도록 한다.
                    s_sda_rd = tx_data_reg[7];
                    if (scl_falling) begin
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        if (bit_counter_reg == 7) begin
                            bit_counter_next = 0;
                            state_next = S_ACK_READ1;
                        end else begin
                            bit_counter_next = bit_counter_reg + 1;
                            state_next = S_DATA_READ1;
                        end
                    end
                end

            endcase
        end
    end

endmodule
