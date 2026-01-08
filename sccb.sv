`timescale 1ns / 1ps

module sccb (
    input  clk,
    input  reset,
    output SIO_D,
    output SIO_C

);
    logic [15:0] sccb_data;
    logic [ 7:0] sccb_addr;
    tick_gen_800kHz U_TICK_GEN_800kHz (
        .clk        (clk),
        .reset      (reset),
        .tick_800kHz(tick_800kHz)
    );

    sccb_controller U_SCCB_CONTROLLER (
        .clk        (clk),
        .reset      (reset),
        .tick_800kHz(tick_800kHz),
        .sccb_data  (sccb_data),
        .sccb_addr  (sccb_addr),
        .SIO_D      (SIO_D),
        .SIO_C      (SIO_C)
    );

    sccb_rom U_SCCB_ROM (
        .clk(clk),
        .sccb_addr(sccb_addr),
        .sccb_data(sccb_data)
    );
endmodule

module tick_gen_800kHz (
    input  logic clk,
    input  logic reset,
    output logic tick_800kHz
);

    logic [$clog2(125)-1 : 0] tick_count;

    always_ff @(posedge clk) begin
        if (reset) begin
            tick_800kHz <= 1'b0;
            tick_count  <= 0;
        end else begin
            if (tick_count == 125) begin
                tick_800kHz <= 1'b1;
                tick_count  <= 0;
            end else begin
                tick_800kHz <= 1'b0;
                tick_count  <= tick_count + 1;
            end
        end
    end
endmodule


module sccb_controller (
    input logic clk,
    input logic reset,
    input logic tick_800kHz,
    input logic [15:0] sccb_data,
    output logic [7:0] sccb_addr,
    output logic SIO_D,
    output logic SIO_C
);

    // slave address (OV7670)
    localparam logic [7:0] SLAVE_ADDR_WRITE = 8'h42;
    localparam logic [7:0] SLAVE_ADDR_READ = 8'h43;

    typedef enum {
        IDLE,
        START1,
        START2,
        SLV_ADDR1,
        SLV_ADDR2,
        SLV_ADDR3,
        SLV_ADDR4,
        SA_ACK1,
        SA_ACK2,
        SA_ACK3,
        SA_ACK4,
        REG_ADDR1,
        REG_ADDR2,
        REG_ADDR3,
        REG_ADDR4,
        RA_ACK1,
        RA_ACK2,
        RA_ACK3,
        RA_ACK4,
        REG_DATA1,
        REG_DATA2,
        REG_DATA3,
        REG_DATA4,
        RD_ACK1,
        RD_ACK2,
        RD_ACK3,
        RD_ACK4,
        RESTART1,
        RESTART2,
        RESTART3,
        RESTART4,
        STOP1,
        STOP2,
        STOP3,
        STOP4
    } state_t;


    state_t state, state_next;

    // reset edge detector + reset syncronizer

    logic reset_delayed;
    logic reset_delayed_delayed;
    logic reset_delayed_delayed_delayed;
    logic reset_ne;

    always_ff @(posedge clk) begin
        reset_delayed <= reset;
        reset_delayed_delayed <= reset_delayed;
        reset_delayed_delayed_delayed <= reset_delayed_delayed;
    end

    assign reset_ne = (~reset_delayed_delayed) && reset_delayed_delayed_delayed;


    // reg next declaration

    logic [7:0] sccb_addr_reg, sccb_addr_next;
    assign sccb_addr = sccb_addr_reg;

    logic [1:0] tick_count_reg, tick_count_next;
    logic [3:0] data_bit_count_reg, data_bit_count_next;
    logic [7:0] tx_data_reg, tx_data_next;

    logic SIO_C_REG, SIO_C_NEXT;
    assign SIO_C = SIO_C_REG;

    // SDA 

    logic SIO_D_EN, SIO_D_EN_NEXT;
    logic SIO_D_REG, SIO_D_NEXT;
    assign SIO_D = (SIO_D_EN) ? SIO_D_REG : 1'bz;


    // SL
    always_ff @(posedge clk) begin
        if (reset) begin
            state              <= IDLE;
            sccb_addr_reg      <= 8'h0;
            tick_count_reg     <= 2'b00;
            data_bit_count_reg <= 4'h0;
            tx_data_reg        <= 8'h00;
            SIO_D_EN           <= 1'b1;
            SIO_C_REG          <= 1'b0;
            SIO_D_REG          <= 1'b1;
        end else begin
            state              <= state_next;
            sccb_addr_reg      <= sccb_addr_next;
            tick_count_reg     <= tick_count_next;
            data_bit_count_reg <= data_bit_count_next;
            tx_data_reg        <= tx_data_next;
            SIO_D_EN           <= SIO_D_EN_NEXT;
            SIO_C_REG          <= SIO_C_NEXT;
            SIO_D_REG          <= SIO_D_NEXT;
        end

    end

    // CL
    always_comb begin
        state_next          = state;
        sccb_addr_next      = sccb_addr_reg;
        tick_count_next     = tick_count_reg;
        data_bit_count_next = data_bit_count_reg;
        tx_data_next        = tx_data_reg;
        SIO_D_EN_NEXT       = SIO_D_EN;
        SIO_C_NEXT          = SIO_C_REG;
        SIO_D_NEXT          = SIO_D_REG;
        case (state)
            IDLE: begin
                SIO_D_EN_NEXT = 1'b1;
                SIO_C_NEXT = 1'b1;
                SIO_D_NEXT = 1'b1;
                if (reset_ne) begin
                    state_next = START1;
                end
            end

            //////////////////////////////////////////
            //// START CONDITION
            //////////////////////////////////////////

            START1: begin
                SIO_D_EN_NEXT = 1'b1;
                SIO_C_NEXT = 1'b1;
                SIO_D_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = START2;
                end
            end
            START2: begin
                SIO_C_NEXT = 1'b0;
                SIO_D_NEXT = 1'b0;
                if (tick_800kHz) begin
                    tx_data_next = SLAVE_ADDR_WRITE;  // 0x42 장전
                    data_bit_count_next = 0;
                    state_next = SLV_ADDR1;
                end
            end

            //////////////////////////////////////////
            //// SLAVE_ADDRESS SEND
            //////////////////////////////////////////
            SLV_ADDR1: begin
                SIO_D_EN_NEXT = 1'b1;
                SIO_C_NEXT = 1'b0;
                SIO_D_NEXT = tx_data_reg[7];
                if (tick_800kHz) begin
                    state_next = SLV_ADDR2;
                end
            end
            SLV_ADDR2: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = SLV_ADDR3;
                end
            end
            SLV_ADDR3: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = SLV_ADDR4;
                end
            end
            SLV_ADDR4: begin
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    if (data_bit_count_reg == 7) begin
                        data_bit_count_next = 0;
                        state_next = SA_ACK1;
                    end else begin
                        data_bit_count_next = data_bit_count_reg + 1;
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        state_next = SLV_ADDR1;
                    end
                end
            end
            //////////////////////////////////////////
            //// SLAVE_ADDRESS ACK
            //////////////////////////////////////////
            SA_ACK1: begin
                SIO_D_EN_NEXT = 1'b0;
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = SA_ACK2;
                end
            end
            SA_ACK2: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = SA_ACK3;
                end
            end
            SA_ACK3: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = SA_ACK4;
                end
            end
            SA_ACK4: begin
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    tx_data_next = sccb_data[15:8]; // Register Address (MSB 8 bit) Sampling
                    state_next = REG_ADDR1;
                end
            end

            //////////////////////////////////////////
            //// REGISTER_ADDRESS SEND
            //////////////////////////////////////////
            REG_ADDR1: begin
                SIO_D_EN_NEXT = 1'b1;
                SIO_C_NEXT = 1'b0;
                SIO_D_NEXT = tx_data_reg[7];
                if (tick_800kHz) begin
                    state_next = REG_ADDR2;
                end
            end
            REG_ADDR2: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = REG_ADDR3;
                end
            end
            REG_ADDR3: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = REG_ADDR4;
                end
            end
            REG_ADDR4: begin
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    if (data_bit_count_reg == 7) begin
                        data_bit_count_next = 0;
                        state_next = RA_ACK1;
                    end else begin
                        data_bit_count_next = data_bit_count_reg + 1;
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        state_next = REG_ADDR1;
                    end
                end
            end
            //////////////////////////////////////////
            //// REGISTER_ADDRESS ACK
            //////////////////////////////////////////
            RA_ACK1: begin
                SIO_D_EN_NEXT = 1'b0;
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = RA_ACK2;
                end
            end
            RA_ACK2: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = RA_ACK3;
                end
            end
            RA_ACK3: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = RA_ACK4;
                end
            end
            RA_ACK4: begin
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    tx_data_next = sccb_data[7:0]; // Register Data (LSB 8 bit) Sampling
                    state_next = REG_DATA1;
                end
            end

            //////////////////////////////////////////
            //// REGISTER_DATA SEND
            //////////////////////////////////////////
            REG_DATA1: begin
                SIO_D_EN_NEXT = 1'b1;
                SIO_C_NEXT = 1'b0;
                SIO_D_NEXT = tx_data_reg[7];
                if (tick_800kHz) begin
                    state_next = REG_DATA2;
                end
            end
            REG_DATA2: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = REG_DATA3;
                end
            end
            REG_DATA3: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = REG_DATA4;
                end
            end
            REG_DATA4: begin
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    if (data_bit_count_reg == 7) begin
                        data_bit_count_next = 0;
                        state_next = RD_ACK1;
                    end else begin
                        data_bit_count_next = data_bit_count_reg + 1;
                        tx_data_next = {tx_data_reg[6:0], 1'b0};
                        state_next = REG_DATA1;
                    end
                end
            end

            //////////////////////////////////////////
            //// REGISTER_DATA ACK
            //////////////////////////////////////////
            RD_ACK1: begin
                SIO_D_EN_NEXT = 1'b0;
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = RD_ACK2;
                end
            end
            RD_ACK2: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = RD_ACK3;
                end
            end
            RD_ACK3: begin
                SIO_C_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = RD_ACK4;
                end
            end
            RD_ACK4: begin
                SIO_C_NEXT = 1'b0;
                if (tick_800kHz) begin
                    if (sccb_addr_reg == 8'hff) begin
                        state_next = STOP1;
                    end else begin
                        state_next     = RESTART1;
                        sccb_addr_next = sccb_addr_reg + 1;
                    end
                end
            end
            //////////////////////////////////////////
            //// RESTART CYCLE
            //////////////////////////////////////////

            RESTART1: begin
                SIO_D_EN_NEXT = 1'b1;
                SIO_C_NEXT = 1'b0;
                SIO_D_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = RESTART2;
                end
            end
            RESTART2: begin
                SIO_C_NEXT = 1'b1;
                SIO_D_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = RESTART3;
                end
            end
            RESTART3: begin
                SIO_C_NEXT = 1'b1;
                SIO_D_NEXT = 1'b1;
                if (tick_800kHz) begin
                    state_next = START1;
                end
            end
            //////////////////////////////////////////
            //// STOP CYCLE
            //////////////////////////////////////////

            STOP1: begin
                SIO_D_EN_NEXT = 1'b1;
                SIO_C_NEXT = 1'b0;
                SIO_D_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = STOP2;
                end
            end
            STOP2: begin
                SIO_C_NEXT = 1'b1;
                SIO_D_NEXT = 1'b0;
                if (tick_800kHz) begin
                    state_next = IDLE;
                end
            end
        endcase
    end
endmodule


module sccb_rom (
    input  logic        clk,
    input  logic [ 7:0] sccb_addr,
    output logic [15:0] sccb_data
);

    //FFFF is end of rom, FFF0 is delay
    always @(posedge clk) begin
        case (sccb_addr)
            0: sccb_data <= 16'h12_80;  //reset
            1: sccb_data <= 16'hFF_F0;  //delay
            2:
            sccb_data <= 16'h12_14;  // COM7,     set RGB color output and set QVGA
            3: sccb_data <= 16'h11_80;  // CLKRC     internal PLL matches input clock
            4: sccb_data <= 16'h0C_04;  // COM3,     default settings
            5: sccb_data <= 16'h3E_19;  // COM14,    no scaling, normal pclock
            6: sccb_data <= 16'h04_00;  // COM1,     disable CCIR656
            7: sccb_data <= 16'h40_d0;  //COM15,     RGB565, full output range
            8: sccb_data <= 16'h3a_04;  //TSLB       
            9: sccb_data <= 16'h14_18;  //COM9       MAX AGC value x4
            10: sccb_data <= 16'h4F_B3;  //MTX1       
            11: sccb_data <= 16'h50_B3;  //MTX2
            12: sccb_data <= 16'h51_00;  //MTX3
            13: sccb_data <= 16'h52_3d;  //MTX4
            14: sccb_data <= 16'h53_A7;  //MTX5
            15: sccb_data <= 16'h54_E4;  //MTX6
            16: sccb_data <= 16'h58_9E;  //MTXS
            17:
            sccb_data <= 16'h3D_C0; //COM13      sets gamma enable, does not preserve reserved bits, may be wrong?
            18: sccb_data <= 16'h17_15;  //HSTART     start high 8 bits 
            19:
            sccb_data <= 16'h18_03; //HSTOP      stop high 8 bits //these kill the odd colored line
            20: sccb_data <= 16'h32_00;  //91  //HREF       edge offset
            21: sccb_data <= 16'h19_03;  //VSTART     start high 8 bits
            22: sccb_data <= 16'h1A_7B;  //VSTOP      stop high 8 bits
            23: sccb_data <= 16'h03_00;  // 00 //VREF       vsync edge offset
            24: sccb_data <= 16'h0F_41;  //COM6       reset timings
            25:
            sccb_data <= 16'h1E_00; //MVFP       disable mirror / flip //might have magic value of 03
            26: sccb_data <= 16'h33_0B;  //CHLF       //magic value from the internet
            27: sccb_data <= 16'h3C_78;  //COM12      no HREF when VSYNC low
            28: sccb_data <= 16'h69_00;  //GFIX       fix gain control
            29: sccb_data <= 16'h74_00;  //REG74      Digital gain control
            30:
            sccb_data <= 16'hB0_84; //RSVD       magic value from the internet *required* for good color
            31: sccb_data <= 16'hB1_0c;  //ABLC1
            32: sccb_data <= 16'hB2_0e;  //RSVD       more magic internet values
            33: sccb_data <= 16'hB3_80;  //THL_ST
            //begin mystery scaling numbers
            34: sccb_data <= 16'h70_3a;
            35: sccb_data <= 16'h71_35;
            36: sccb_data <= 16'h72_11;
            37: sccb_data <= 16'h73_f1;
            38: sccb_data <= 16'ha2_02;
            //gamma curve values
            39: sccb_data <= 16'h7a_20;
            40: sccb_data <= 16'h7b_10;
            41: sccb_data <= 16'h7c_1e;
            42: sccb_data <= 16'h7d_35;
            43: sccb_data <= 16'h7e_5a;
            44: sccb_data <= 16'h7f_69;
            45: sccb_data <= 16'h80_76;
            46: sccb_data <= 16'h81_80;
            47: sccb_data <= 16'h82_88;
            48: sccb_data <= 16'h83_8f;
            49: sccb_data <= 16'h84_96;
            50: sccb_data <= 16'h85_a3;
            51: sccb_data <= 16'h86_af;
            52: sccb_data <= 16'h87_c4;
            53: sccb_data <= 16'h88_d7;
            54: sccb_data <= 16'h89_e8;
            //AGC and AEC
            55: sccb_data <= 16'h13_e0;  //COM8, disable AGC / AEC
            56: sccb_data <= 16'h00_00;  //set gain reg to 0 for AGC
            57: sccb_data <= 16'h10_00;  //set ARCJ reg to 0
            58: sccb_data <= 16'h0d_40;  //magic reserved bit for COM4
            59: sccb_data <= 16'h14_18;  //COM9, 4x gain + magic bit
            60: sccb_data <= 16'ha5_05;  // BD50MAX
            61: sccb_data <= 16'hab_07;  //DB60MAX
            62: sccb_data <= 16'h24_95;  //AGC upper limit
            63: sccb_data <= 16'h25_33;  //AGC lower limit
            64: sccb_data <= 16'h26_e3;  //AGC/AEC fast mode op region
            65: sccb_data <= 16'h9f_78;  //HAECC1
            66: sccb_data <= 16'ha0_68;  //HAECC2
            67: sccb_data <= 16'ha1_03;  //magic
            68: sccb_data <= 16'ha6_d8;  //HAECC3
            69: sccb_data <= 16'ha7_d8;  //HAECC4
            70: sccb_data <= 16'ha8_f0;  //HAECC5
            71: sccb_data <= 16'ha9_90;  //HAECC6
            72: sccb_data <= 16'haa_94;  //HAECC7
            73: sccb_data <= 16'h13_e7;  //COM8, enable AGC / AEC
            74: sccb_data <= 16'h69_07;
            default: sccb_data <= 16'hFF_FF;  //mark end of ROM
        endcase
    end
endmodule

//module sccb_rom (
//    input  logic        clk,
//    input  logic [ 7:0] sccb_addr,
//    output logic [15:0] sccb_data
//);
//
//    always_ff @(posedge clk) begin
//        case (sccb_addr)
//            //         [0] Software Reset (필수!)
//            0: sccb_data = 16'h1280;
//
//            // [1] Delay용 더미 데이터 (실제 전송은 안 하고 FSM에서 딜레이 처리)
//            // STM32 코드의 1번지(Delay)에 해당
//            // FSM이 0번 전송 후 딜레이를 주므로, 여기는 다음 설정(COM7)을 바로 넣어도 되지만
//            // 인덱스 순서를 맞추기 위해 아래부터 1씩 밀어서 배치합니다.
//
//            // [2] COM7 (QVGA, RGB) - 여기서부터 실제 설정 시작
//
//            1: sccb_data = 16'h1214;
//            2: sccb_data = 16'hFFF0;
//            3: sccb_data = 16'h1180;
//            4: sccb_data = 16'h0C04;
//            5: sccb_data = 16'h3E19;
//            6: sccb_data = 16'h0400;
//            7: sccb_data = 16'h40D0;
//            8: sccb_data = 16'h3A04;
//            9: sccb_data = 16'h1418;
//            10: sccb_data = 16'h4FB3;
//            11: sccb_data = 16'h50B3;
//            12: sccb_data = 16'h5100;
//            13: sccb_data = 16'h523D;
//            14: sccb_data = 16'h53A7;
//            15: sccb_data = 16'h54E4;
//            16: sccb_data = 16'h589E;
//            17: sccb_data = 16'h3DC0;
//            18: sccb_data = 16'h1715;  // HSTART (Ref: 15)
//            19: sccb_data = 16'h1803;  // HSTOP (Ref: 03)
//            20: sccb_data = 16'h3200;  // HREF (Ref: 00)
//            21: sccb_data = 16'h1903;
//            22: sccb_data = 16'h1A7B;
//            23: sccb_data = 16'h0300;  // VREF (Ref: 00)
//            24: sccb_data = 16'h0F41;
//            25: sccb_data = 16'h1E00;
//            26: sccb_data = 16'h330B;
//            27: sccb_data = 16'h3C78;
//            28: sccb_data = 16'h6900;
//            29: sccb_data = 16'h7400;
//            30: sccb_data = 16'hB084;
//            31: sccb_data = 16'hB10C;
//            32: sccb_data = 16'hB20E;
//            33: sccb_data = 16'hB380;
//            34: sccb_data = 16'h703A;
//            35: sccb_data = 16'h7135;
//            36: sccb_data = 16'h7211;
//            37: sccb_data = 16'h73F1;  // PCLK DIV (Ref: F1)
//            38: sccb_data = 16'hA202;
//            39: sccb_data = 16'h7A20;
//            40: sccb_data = 16'h7B10;
//            41: sccb_data = 16'h7C1E;
//            42: sccb_data = 16'h7D35;
//            43: sccb_data = 16'h7E5A;
//            44: sccb_data = 16'h7F69;
//            45: sccb_data = 16'h8076;
//            46: sccb_data = 16'h8180;
//            47: sccb_data = 16'h8288;
//            48: sccb_data = 16'h838F;
//            49: sccb_data = 16'h8496;
//            50: sccb_data = 16'h85A3;
//            51: sccb_data = 16'h86AF;
//            52: sccb_data = 16'h87C4;
//            53: sccb_data = 16'h88D7;
//            54: sccb_data = 16'h89E8;
//            55: sccb_data = 16'h13E0;
//            56: sccb_data = 16'h0000;
//            57: sccb_data = 16'h1000;
//            58: sccb_data = 16'h0D40;
//            59: sccb_data = 16'h1418;
//            60: sccb_data = 16'hA505;
//            61: sccb_data = 16'hAB07;
//            62: sccb_data = 16'h2495;
//            63: sccb_data = 16'h2533;
//            64: sccb_data = 16'h26E3;
//            65: sccb_data = 16'h9F78;
//            66: sccb_data = 16'hA068;
//            67: sccb_data = 16'hA103;
//            68: sccb_data = 16'hA6D8;
//            69: sccb_data = 16'hA7D8;
//            70: sccb_data = 16'hA8F0;
//            71: sccb_data = 16'hA990;
//            72: sccb_data = 16'hAA94;
//            73: sccb_data = 16'h13E7;
//            74: sccb_data = 16'h6907;
//            default: sccb_data <= 16'hFF_FF;  // mark end of ROM
//        endcase
//    end
//endmodule



/*  REGISTER LIST
 // -----------------------------------------------------
            // Address 0x00 ~ 0x09
            // -----------------------------------------------------
            0: sccb_data <= 16'h00_00;  // GAIN     (AGC - Gain control)
            1: sccb_data <= 16'h01_80;  // BLUE     (AWB - Blue channel gain)
            2: sccb_data <= 16'h02_80;  // RED      (AWB - Red channel gain)
            3: sccb_data <= 16'h03_00;  // VREF     (Vertical Frame Control)
            4: sccb_data <= 16'h04_00;  // COM1     (Common Control 1)
            5: sccb_data <= 16'h05_00;  // BAVE     (U/B Average Level)
            6: sccb_data <= 16'h06_00;  // GbAVE    (Y/Gb Average Level)
            7: sccb_data <= 16'h07_00;  // AECHH    (Exposure Value - AEC MSB)
            8: sccb_data <= 16'h08_00;  // RAVE     (V/R Average Level)
            9: sccb_data <= 16'h09_01;  // COM2     (Common Control 2)

            // 0x0A (PID), 0x0B (VER) are Read Only

            // -----------------------------------------------------
            // Address 0x0C ~ 0x15
            // -----------------------------------------------------
            10: sccb_data <= 16'h0C_00;  // COM3     (Common Control 3)
            11: sccb_data <= 16'h0D_00;  // COM4     (Common Control 4)
            12: sccb_data <= 16'h0E_01;  // COM5     (Common Control 5)
            13: sccb_data <= 16'h0F_43;  // COM6     (Common Control 6)
            14: sccb_data <= 16'h10_40;  // AECH     (Exposure Value)
            15: sccb_data <= 16'h11_80;  // CLKRC    (Internal Clock)
            16: sccb_data <= 16'h12_00;  // COM7     (Reset/Format - Default 00)
            17:
            sccb_data <= 16'h13_8F;  // COM8     (AGC/AEC/AWB - User Corrected)
            18: sccb_data <= 16'h14_4A;  // COM9     (Gain Ceiling)
            19: sccb_data <= 16'h15_00;  // COM10    (PCLK/HREF options)

            // 0x16 Reserved

            // -----------------------------------------------------
            // Address 0x17 ~ 0x2D
            // -----------------------------------------------------
            20: sccb_data <= 16'h17_11;  // HSTART   (Horiz Frame Start High)
            21: sccb_data <= 16'h18_61;  // HSTOP    (Horiz Frame End High)
            22: sccb_data <= 16'h19_03;  // VSTRT    (Vert Frame Start High)
            23: sccb_data <= 16'h1A_7B;  // VSTOP    (Vert Frame End High)
            24: sccb_data <= 16'h1B_00;  // PSHFT    (Pixel Delay Select)

            // 0x1C (MIDH), 0x1D (MIDL) are Read Only

            25: sccb_data <= 16'h1E_01;  // MVFP     (Mirror/VFlip)
            26: sccb_data <= 16'h1F_00;  // LAEC     (Reserved)
            27: sccb_data <= 16'h20_04;  // ADCCTR0  (ADC Control)
            28: sccb_data <= 16'h21_02;  // ADCCTR1  (ADC Control)
            29: sccb_data <= 16'h22_01;  // ADCCTR2  (ADC Control)
            30: sccb_data <= 16'h23_00;  // ADCCTR3  (ADC Control)
            31: sccb_data <= 16'h24_75;  // AEW      (AGC/AEC Stable Upper)
            32: sccb_data <= 16'h25_63;  // AEB      (AGC/AEC Stable Lower)
            33: sccb_data <= 16'h26_D4;  // VPT      (Fast Mode Region)
            34: sccb_data <= 16'h27_80;  // BBIAS    (B Channel Bias)
            35: sccb_data <= 16'h28_80;  // GbBIAS   (Gb Channel Bias)
            // 0x29 Reserved
            36: sccb_data <= 16'h2A_00;  // EXHCH    (Dummy Pixel Insert MSB)
            37: sccb_data <= 16'h2B_00;  // EXHCL    (Dummy Pixel Insert LSB)
            38: sccb_data <= 16'h2C_80;  // RBIAS    (R Channel Bias)
            39: sccb_data <= 16'h2D_00;  // ADVFL    (Insert Dummy Lines LSB)

            // -----------------------------------------------------
            // Address 0x2E ~ 0x3E
            // -----------------------------------------------------
            40: sccb_data <= 16'h2E_00;  // ADVFH    (Insert Dummy Lines MSB)
            41: sccb_data <= 16'h2F_00;  // YAVE     (Y/G Channel Average)
            42: sccb_data <= 16'h30_08;  // HSYST    (HSYNC Rising Edge Delay)
            43: sccb_data <= 16'h31_30;  // HSYEN    (HSYNC Falling Edge Delay)
            44: sccb_data <= 16'h32_80;  // HREF     (HREF Control)
            45: sccb_data <= 16'h33_08;  // CHLF     (Array Current Control)
            46: sccb_data <= 16'h34_11;  // ARBLM    (Array Ref Control)
            // 0x35, 0x36 Reserved
            47: sccb_data <= 16'h37_3F;  // ADC      (ADC Control)
            48: sccb_data <= 16'h38_01;  // ACOM     (ADC/Analog Common Mode)
            49: sccb_data <= 16'h39_00;  // OFON     (ADC Offset Control)
            50: sccb_data <= 16'h3A_0D;  // TSLB     (Line Buffer Test)
            51:
            sccb_data <= 16'h3B_00;  // COM11    (Night Mode - User Corrected)
            52: sccb_data <= 16'h3C_68;  // COM12    (HREF option)
            53: sccb_data <= 16'h3D_88;  // COM13    (Gamma/UV Saturation)
            54: sccb_data <= 16'h3E_00;  // COM14    (PCLK/Scaling)

            // -----------------------------------------------------
            // Address 0x3F ~ 0x58 (Color & Matrix)
            // -----------------------------------------------------
            55: sccb_data <= 16'h3F_00;  // EDGE     (Edge Enhancement)
            56: sccb_data <= 16'h40_C0;  // COM15    (RGB 555/565 option)
            57: sccb_data <= 16'h41_08;  // COM16    (Edge/De-noise auto)
            58: sccb_data <= 16'h42_00;  // COM17    (AEC Window)

            // Reserved but have defaults in table
            59: sccb_data <= 16'h43_14;  // AWBC1   
            60: sccb_data <= 16'h44_F0;  // AWBC2   
            61: sccb_data <= 16'h45_45;  // AWBC3   
            62: sccb_data <= 16'h46_61;  // AWBC4   
            63: sccb_data <= 16'h47_51;  // AWBC5   
            64: sccb_data <= 16'h48_79;  // AWBC6   

            65: sccb_data <= 16'h4B_00;  // REG4B    (UV Average)
            66: sccb_data <= 16'h4C_00;  // DNSTH    (De-noise Strength)

            67: sccb_data <= 16'h4F_40;  // MTX1     (Matrix Coeff 1)
            68: sccb_data <= 16'h50_34;  // MTX2     (Matrix Coeff 2)
            69: sccb_data <= 16'h51_0C;  // MTX3     (Matrix Coeff 3)
            70: sccb_data <= 16'h52_17;  // MTX4     (Matrix Coeff 4)
            71: sccb_data <= 16'h53_29;  // MTX5     (Matrix Coeff 5)
            72: sccb_data <= 16'h54_40;  // MTX6     (Matrix Coeff 6)
            73: sccb_data <= 16'h55_00;  // BRIGHT   (Brightness)
            74: sccb_data <= 16'h56_40;  // CONTRAS  (Contrast)
            75: sccb_data <= 16'h57_80;  // CONTRAS_CENTER
            76: sccb_data <= 16'h58_1E;  // MTXS     (Matrix Sign)

            // -----------------------------------------------------
            // Address 0x62 ~ 0x76 (Lens Correction & Gain)
            // -----------------------------------------------------
            77: sccb_data <= 16'h62_00;  // LCC1     (Lens Correction)
            78: sccb_data <= 16'h63_00;  // LCC2     (Lens Correction)
            79: sccb_data <= 16'h64_50;  // LCC3     (Lens Correction)
            80: sccb_data <= 16'h65_30;  // LCC4     (Lens Correction)
            81: sccb_data <= 16'h66_00;  // LCC5     (Lens Correction)
            82: sccb_data <= 16'h67_80;  // MANU     (Manual U)
            83: sccb_data <= 16'h68_80;  // MANV     (Manual V)
            84: sccb_data <= 16'h69_00;  // GFIX     (Fix Gain)
            85: sccb_data <= 16'h6A_00;  // GGAIN    (G Channel AWB Gain)
            86: sccb_data <= 16'h6B_0A;  // DBLV     (PLL Control)
            87: sccb_data <= 16'h6C_02;  // AWBCTR3 
            88: sccb_data <= 16'h6D_55;  // AWBCTR2 
            89: sccb_data <= 16'h6E_C0;  // AWBCTR1 
            90: sccb_data <= 16'h6F_9A;  // AWBCTR0 
            91: sccb_data <= 16'h70_3A;  // SCALING_XSC     
            92: sccb_data <= 16'h71_35;  // SCALING_YSC     
            93: sccb_data <= 16'h72_11;  // SCALING_DCWCTR  
            94: sccb_data <= 16'h73_00;  // SCALING_PCLK_DIV
            95: sccb_data <= 16'h74_00;  // REG74           
            96: sccb_data <= 16'h75_0F;  // REG75    (Edge enhance lower)
            97: sccb_data <= 16'h76_01;  // REG76    (B/W pixel correction)

            // -----------------------------------------------------
            // Address 0x77 ~ 0x89 (Gamma Curve)
            // -----------------------------------------------------
            98:  sccb_data <= 16'h77_10;  // REG77    (De-noise offset)
            99:  sccb_data <= 16'h7A_24;  // SLOP     (Gamma Slope)
            100: sccb_data <= 16'h7B_04;  // GAM1     (Gamma Curve 1)
            101: sccb_data <= 16'h7C_07;  // GAM2    
            102: sccb_data <= 16'h7D_10;  // GAM3    
            103: sccb_data <= 16'h7E_28;  // GAM4    
            104: sccb_data <= 16'h7F_36;  // GAM5    
            105: sccb_data <= 16'h80_44;  // GAM6    
            106: sccb_data <= 16'h81_52;  // GAM7    
            107: sccb_data <= 16'h82_60;  // GAM8    
            108: sccb_data <= 16'h83_6C;  // GAM9    
            109: sccb_data <= 16'h84_78;  // GAM10   
            110: sccb_data <= 16'h85_8C;  // GAM11   
            111: sccb_data <= 16'h86_9E;  // GAM12   
            112: sccb_data <= 16'h87_BB;  // GAM13   
            113: sccb_data <= 16'h88_D2;  // GAM14   
            114: sccb_data <= 16'h89_E5;  // GAM15    (Gamma Curve 15)

            115: sccb_data <= 16'h8C_00;  // RGB444  

            // -----------------------------------------------------
            // Address 0x92 ~ End
            // -----------------------------------------------------
            116: sccb_data <= 16'h92_00;  // DM_LNL   (Dummy Line Low)
            117: sccb_data <= 16'h93_00;  // DM_LNH   (Dummy Line High)
            118: sccb_data <= 16'h94_50;  // LCC6    
            119: sccb_data <= 16'h95_50;  // LCC7    
            120: sccb_data <= 16'h9D_99;  // BD50ST   (50Hz Banding)
            121: sccb_data <= 16'h9E_7F;  // BD60ST   (60Hz Banding)
            122: sccb_data <= 16'h9F_C0;  // HAECC1  
            123: sccb_data <= 16'hA0_90;  // HAECC2  
            124: sccb_data <= 16'hA2_02;  // SCALING_PCLK_DELAY
            125: sccb_data <= 16'hA4_00;  // NT_CTRL 
            126: sccb_data <= 16'hA5_0F;  // BD50MAX 
            127: sccb_data <= 16'hA6_F0;  // HAECC3  
            128: sccb_data <= 16'hA7_C1;  // HAECC4  
            129: sccb_data <= 16'hA8_F0;  // HAECC5  
            130: sccb_data <= 16'hA9_C1;  // HAECC6  
            131: sccb_data <= 16'hAA_14;  // HAECC7  
            132: sccb_data <= 16'hAB_0F;  // BD60MAX 
            133: sccb_data <= 16'hAC_00;  // STR_OPT 
            134: sccb_data <= 16'hAD_80;  // STR_R   
            135: sccb_data <= 16'hAE_80;  // STR_G   
            136: sccb_data <= 16'hAF_80;  // STR_B   
            137: sccb_data <= 16'hB1_00;  // ABLC1   
            138: sccb_data <= 16'hB3_80;  // THL_ST  
            139: sccb_data <= 16'hB5_04;  // THL_DLT 
            140: sccb_data <= 16'hBE_00;  // AD_CHB   (Blue Black Level)
            141: sccb_data <= 16'hBF_00;  // AD_CHR   (Red Black Level)
            142: sccb_data <= 16'hC0_00;  // AD_CHGb  (Gb Black Level)
            143: sccb_data <= 16'hC1_00;  // AD_CHGr  (Gr Black Level)
            144: sccb_data <= 16'hC9_C0;  // SATCTR   (Saturation)
*/
