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
