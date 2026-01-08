`timescale 1ns / 1ps

module i2c_master (
    // global signals 
    input  logic       clk,
    input  logic       reset,
    // I2C signals
    output logic       scl,
    inout  logic       sda,
    // axi Control Register
    input  logic       i2c_en,                 // CR[0]
    input  logic       i2c_stop,               // CR[1]
    input  logic       i2c_start,              // CR[2]
    // axi State Register
    output logic       tx_ready,               // SR[0]
    output logic       tx_done,                // SR[1]
    output logic       rx_done,                // SR[2]
    // axi ODR
    input  logic [7:0] tx_data,
    // axi IDR
    output logic [7:0] rx_data,
    output logic [4:0] i2c_master_state_debug
);

    // sda 3state buffer
    logic sda_en;
    logic sda_wr;
    logic sda_rd;
    assign sda_rd = sda;
    assign sda = (sda_en) ? sda_wr : 1'bz;

    /////////// Synchronizer Edge Detector///////////////    
    logic i2c_en_sync0, i2c_en_sync1, i2c_en_sync2;
    logic i2c_start_sync0, i2c_start_sync1, i2c_start_sync2;
    logic i2c_stop_sync0, i2c_stop_sync1, i2c_stop_sync2;
    logic sda_sync0, sda_sync1, sda_sync2;
    logic sda_rising, sda_falling;

    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            i2c_en_sync0    <= 1'b0;
            i2c_en_sync1    <= 1'b0;
            i2c_en_sync2    <= 1'b0;
            i2c_start_sync0 <= 1'b0;
            i2c_start_sync1 <= 1'b0;
            i2c_start_sync2 <= 1'b0;
            i2c_stop_sync0  <= 1'b0;
            i2c_stop_sync1  <= 1'b0;
            i2c_stop_sync2  <= 1'b0;
            sda_sync0 <= 1'b1;
            sda_sync1 <= 1'b1;
            sda_sync2 <= 1'b1;
        end else begin
            i2c_en_sync0    <= i2c_en;
            i2c_en_sync1    <= i2c_en_sync0;
            i2c_en_sync2    <= i2c_en_sync1;
            i2c_start_sync0 <= i2c_start;
            i2c_start_sync1 <= i2c_start_sync0;
            i2c_start_sync2 <= i2c_start_sync1;
            i2c_stop_sync0  <= i2c_stop;
            i2c_stop_sync1  <= i2c_stop_sync0;
            i2c_stop_sync2  <= i2c_stop_sync1;
            sda_sync0 <= sda_rd;
            sda_sync1 <= sda_sync0;
            sda_sync2 <= sda_sync1;
        end
    end
    assign i2c_en_re    = i2c_en_sync1 & ~(i2c_en_sync2);
    assign i2c_start_re = i2c_start_sync1 & ~(i2c_start_sync2);
    assign i2c_stop_re  = i2c_stop_sync1 & ~(i2c_stop_sync2);
    assign sda_rising   = sda_sync1 & ~(sda_sync2);
    assign sda_falling  = ~(sda_sync1) & sda_sync2;

    // state declaration
    typedef enum {
        IDLE,  // 0
        START1,  // 1
        START2,  // 2
        WRITE1,  // 3
        WRITE2,  // 4
        WRITE3,  // 5
        WRITE4,  // 6
        READ1,  // 7
        READ2,  // 8
        READ3,  // 9
        READ4,  // 10
        ACK_WRITE1,  // 11
        ACK_WRITE2,  // 12
        ACK_WRITE3,  // 13
        ACK_WRITE4,  // 14
        ACK_READ1,  // 15
        ACK_READ2,  // 16
        ACK_READ3,  // 17
        ACK_READ4,  // 18
        NACK_READ1,  // 19
        NACK_READ2,  // 20
        NACK_READ3,  // 21
        NACK_READ4,  // 22
        HOLD,  //23
        STOP1,  // 24
        STOP2  // 25
    } state_i2c_master;
    state_i2c_master state, state_next;
    assign i2c_master_state_debug = state;



    // tx_data
    logic [8:0] clk_counter_reg, clk_counter_next;  // for 499 count
    logic [2:0] bit_counter_reg, bit_counter_next;  // for 7 count
    logic [7:0] tx_data_reg, tx_data_next;
    logic [7:0] rx_data_reg, rx_data_next;

    // SR output
    logic tx_ready_reg, tx_ready_next;
    logic tx_done_reg, tx_done_next;
    logic rx_done_reg, rx_done_next;

    assign tx_ready = tx_ready_reg;
    assign tx_done  = tx_done_reg;
    assign rx_done  = rx_done_reg;
    assign rx_data  = rx_data_reg;

    // scl register and output
    logic scl_reg, scl_next;
    assign scl = scl_reg;


    // READ ACK or READ NACK
    logic is_nack_write_reg, is_nack_write_next;
    logic is_ack_read_reg, is_ack_read_next;



    // SL
    always_ff @(posedge clk, posedge reset) begin
        if (reset) begin
            state             <= IDLE;
            clk_counter_reg   <= 9'd0;
            bit_counter_reg   <= 3'd0;
            tx_data_reg       <= 8'd0;
            rx_data_reg       <= 8'd0;
            tx_ready_reg      <= 1'b1;
            tx_done_reg       <= 1'b0;
            rx_done_reg       <= 1'b0;
            scl_reg           <= 1'b1;
            is_nack_write_reg <= 1'b0;
            is_ack_read_reg   <= 1'b1;
        end else begin
            state             <= state_next;
            clk_counter_reg   <= clk_counter_next;
            bit_counter_reg   <= bit_counter_next;
            tx_data_reg       <= tx_data_next;
            rx_data_reg       <= rx_data_next;
            tx_ready_reg      <= tx_ready_next;
            tx_done_reg       <= tx_done_next;
            rx_done_reg       <= rx_done_next;
            scl_reg           <= scl_next;
            is_nack_write_reg <= is_nack_write_next;
            is_ack_read_reg   <= is_ack_read_next;
        end
    end

    // CL
    always_comb begin
        state_next         = state;
        clk_counter_next   = clk_counter_reg;
        bit_counter_next   = bit_counter_reg;
        tx_data_next       = tx_data_reg;
        rx_data_next       = rx_data_reg;
        tx_ready_next      = 1'b0;
        tx_done_next       = 1'b0;
        rx_done_next       = 1'b0;
        scl_next           = scl_reg;
        sda_en             = 1'b1;
        sda_wr             = 1'b0;
        is_nack_write_next = is_nack_write_reg;
        is_ack_read_next   = is_ack_read_reg;
        case (state)
            IDLE: begin
                clk_counter_next = 9'd0;
                bit_counter_next = 3'd0;
                tx_ready_next    = 1'b1;
                tx_done_next     = 1'b0;
                rx_done_next     = 1'b0;
                sda_en           = 1'b1;
                sda_wr           = 1'b1;
                scl_next         = 1'b1;
                if (i2c_start) begin
                    tx_data_next = tx_data; // AXI에서 보내주는 tx_data를 sampling 한다.
                    state_next = START1;
                end
            end
            START1: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b0;
                scl_next = 1'b1;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 9'd0;
                    state_next = START2;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end

            START2: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b0;
                scl_next = 1'b0;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 9'd0;
                    state_next = WRITE1;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end

            // WRITE 
            WRITE1: begin
                sda_en   = 1'b1;
                sda_wr   = tx_data_reg[7];
                scl_next = 1'b0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = WRITE2;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            WRITE2: begin
                sda_en   = 1'b1;
                sda_wr   = tx_data_reg[7];
                scl_next = 1'b1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = WRITE3;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            WRITE3: begin
                sda_en   = 1'b1;
                sda_wr   = tx_data_reg[7];
                scl_next = 1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = WRITE4;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            WRITE4: begin
                sda_en   = 1'b1;
                sda_wr   = tx_data_reg[7];
                scl_next = 0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    if (bit_counter_reg == 7) begin
                        bit_counter_next = 3'b0;
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        state_next = ACK_WRITE1;
                    end else begin
                        bit_counter_next = bit_counter_reg + 1;
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        state_next = WRITE1;
                    end
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end


            /////////////////////////
            /// ACK_WRITE 1_bit receive
            /////////////////////////


            ACK_WRITE1: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    state_next = ACK_WRITE2;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ACK_WRITE2: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    state_next = ACK_WRITE3;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ACK_WRITE3: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 1;
                is_nack_write_next = sda_sync2;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    state_next = ACK_WRITE4;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ACK_WRITE4: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    tx_done_next = 1'b1;
                    state_next = HOLD;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end

            /////////////////////////
            /// HOLD  판단 영역
            /////////////////////////

            HOLD: begin
                sda_en = 1'b1;
                sda_wr    = 1'b0;
                scl_next  = 0;
                tx_ready_next = 1'b1;
                if (i2c_en) begin
                    if (i2c_start == 1'b0 & i2c_stop == 1'b0) begin  // DATA // ADDR WRITE하고 첫 DATA WRITE 할 때 or WRITE에서 WRITE로 유지될 때
                        tx_data_next = tx_data; // AXI에서 보내주는 tx_data(ADDR or DATA)를 sampling 한다.
                        if (is_nack_write_reg == 0) begin
                            state_next = WRITE1;
                        end else begin
                            state_next = STOP1;
                        end
                    end else if (i2c_start == 1'b1 & i2c_stop == 1'b0) begin // START     // ADDR WRITE하고 첫 DATA READ 할 때
                        state_next = READ1;
                    end else if (i2c_start == 1'b0 & i2c_stop == 1'b1) begin // STOP MODE   // WRITE 끝나고 READ 할 때 or READ  끝나고 STOP할 때
                        tx_data_next = tx_data; // AXI에서 보내주는 tx_data(ADDR)를 sampling 한다.
                        state_next = STOP1;
                    end else if (i2c_start == 1'b1 & i2c_stop == 1'b1) begin // READ ACK MODE
                        is_ack_read_next = 1;
                        state_next = READ1;
                    end
                end else begin
                    if (i2c_start == 1'b1 & i2c_stop == 1'b1) begin // READ NACK MODE
                        is_ack_read_next = 0;
                        state_next = READ1;
                    end 
                end
            end

            /////////////////////////
            /// STOP 
            /////////////////////////
            STOP1: begin
                sda_en = 1'b1;
                sda_wr = 1'b0;
                scl_next = 1'b1;
                tx_ready_next = 1'b0;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 0;
                    state_next = STOP2;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            STOP2: begin
                sda_en = 1'b1;
                sda_wr = 1'b1;
                scl_next = 1'b1;
                tx_ready_next = 1'b0;
                if (clk_counter_reg == 499) begin
                    clk_counter_next = 0;
                    state_next = IDLE;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end

            /////////////////////////
            /// READ  8_bit send
            /////////////////////////
            READ1: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    state_next = READ2;
                    rx_data_next = {
                        rx_data_reg[6:0], sda_sync2
                    };  // rx_data를 sampling 한다.
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            READ2: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    state_next = READ3;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            READ3: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    state_next = READ4;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            READ4: begin
                sda_en = 1'b0; // SDA를 input모드로 바꿔서 SLAVE가 ACK했으면 0으로 당겨주는 신호를 받는다.
                scl_next = 0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 0;
                    if (bit_counter_reg == 7) begin
                        bit_counter_next = 0;
                        if (is_ack_read_reg == 1) begin
                            state_next = ACK_READ1;
                        end else begin
                            state_next = NACK_READ1;
                        end
                    end else begin
                        bit_counter_next = bit_counter_reg + 1;
                        state_next = READ1;
                    end
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end

            /////////////////////////
            /// ACK_READ  1_bit send   // S_ACK_READ state receive
            /////////////////////////

            ACK_READ1: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b0;
                scl_next = 1'b0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = ACK_READ2;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ACK_READ2: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b0;
                scl_next = 1'b1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = ACK_READ3;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ACK_READ3: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b0;
                scl_next = 1'b1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = ACK_READ4;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            ACK_READ4: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b0;
                scl_next = 1'b0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    rx_done_next = 1'b1;
                    state_next = HOLD;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end

            /////////////////////////
            /// NACK_READ  1_bit send
            /////////////////////////

            NACK_READ1: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b1;
                scl_next = 1'b0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = NACK_READ2;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            NACK_READ2: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b1;
                scl_next = 1'b1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = NACK_READ3;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            NACK_READ3: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b1;
                scl_next = 1'b1;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    state_next = NACK_READ4;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
            NACK_READ4: begin
                sda_en   = 1'b1;
                sda_wr   = 1'b1;
                scl_next = 1'b0;
                if (clk_counter_reg == 249) begin
                    clk_counter_next = 9'd0;
                    rx_done_next = 1'b1;
                    state_next = HOLD;
                end else begin
                    clk_counter_next = clk_counter_reg + 1;
                end
            end
        endcase
    end
endmodule
