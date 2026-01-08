module line_buffer #(
    parameter ACTIVE_PIXEL = 10,
    parameter ACTIVE_LINE  = 4,
    parameter ADDR_WIDTH   = 6,
    parameter DATA_WIDTH   = 30
) (
    input            clk,
    input            rstn,
    input            i_vsync,
    input            i_hsync,
    input            i_de,
    input      [9:0] i_r_data,
    input      [9:0] i_g_data,
    input      [9:0] i_b_data,
    
    output           o_vsync,
    output           o_hsync,
    output reg       o_de,       // FSM에서 직접 제어 (Combinational)
    output     [9:0] o_r_data,
    output     [9:0] o_g_data,
    output     [9:0] o_b_data
);

    reg sram1_cs, sram2_cs;
    reg sram1_we, sram2_we;
    wire [ADDR_WIDTH-1:0] sram1_addr, sram2_addr;
    wire [DATA_WIDTH-1:0] sram1_dout, sram2_dout;

    single_port_ram u_ram1 (
        .clk(clk),
        .i_cs(sram1_cs),
        .i_we(sram1_we),
        .i_addr(sram1_addr),
        .i_din({i_r_data, i_g_data, i_b_data}),
        .o_dout(sram1_dout)
    );

    single_port_ram u_ram2 (
        .clk(clk),
        .i_cs(sram2_cs),
        .i_we(sram2_we),
        .i_addr(sram2_addr),
        .i_din({i_r_data, i_g_data, i_b_data}),
        .o_dout(sram2_dout)
    );

    localparam IDLE  = 3'b000;
    localparam FIRST = 3'b001;
    localparam EVEN  = 3'b010;
    localparam ODD   = 3'b011;
    localparam LAST  = 3'b100;

    reg [2:0] state, state_next;

    // --- Sync Edge Detector ---
    reg  r_hsync_delayed;
    reg  r_vsync_delayed;
    wire w_hsync_pe;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r_hsync_delayed <= 0;
            r_vsync_delayed <= 0;
        end else begin
            r_hsync_delayed <= i_hsync;
            r_vsync_delayed <= i_vsync;
        end
    end
    assign w_hsync_pe = i_hsync && ~r_hsync_delayed;

    // --- Sync Delay Logic ---
    reg r_hsync_enable;
    reg r_vsync_enable;
    reg r_vsync_buffer;

    // RAM 데이터 지연을 없앴으므로(Distributed RAM), Sync 신호도 추가 지연 없이 사용
    assign o_hsync = (i_hsync) ? r_hsync_enable : 1'b0;
    assign o_vsync = (i_hsync) ? r_vsync_enable : r_vsync_buffer;
    
    // [FIX] o_de 지연 제거. FSM 출력 그대로 사용.
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r_hsync_enable <= 0;
            r_vsync_enable <= 0;
            r_vsync_buffer <= 0;
        end else begin
            if (w_hsync_pe) begin
                r_vsync_enable <= i_vsync;
                r_vsync_buffer <= r_vsync_enable;
                r_hsync_enable <= i_hsync;
            end
        end
    end

    reg [$clog2(ACTIVE_PIXEL)-1:0] pixel_count_reg, pixel_count_next;
    reg [$clog2(ACTIVE_LINE)-1:0]  line_count_reg, line_count_next;
  reg [3:0] clk_count_reg, clk_count_next;

    assign sram1_addr = pixel_count_reg;
    assign sram2_addr = pixel_count_reg;

    // [FIX] MUX Logic: LAST 상태에서도 SRAM2를 읽어야 하므로 조건 추가
    // Distributed RAM을 쓰므로 데이터가 즉시 나옴 -> Combinational MUX OK
    wire use_sram2_out = (state == ODD) || (state == LAST);

    assign o_r_data = (use_sram2_out) ? sram2_dout[29:20] : sram1_dout[29:20];
    assign o_g_data = (use_sram2_out) ? sram2_dout[19:10] : sram1_dout[19:10];
    assign o_b_data = (use_sram2_out) ? sram2_dout[9:0]   : sram1_dout[9:0];

    // --- FSM Sequential ---
    always @(posedge clk, negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            pixel_count_reg <= 0;
            line_count_reg <= 0;
          clk_count_reg <= 0;
        end else begin
            state <= state_next;
            pixel_count_reg <= pixel_count_next;
            line_count_reg <= line_count_next;
          clk_count_reg <= clk_count_next;
        end
    end

    // --- FSM Combinational ---
    always @(*) begin
        state_next = state;
        pixel_count_next = pixel_count_reg;
        line_count_next = line_count_reg;
      clk_count_next = clk_count_reg;
        sram1_cs = 0; sram2_cs = 0;
        sram1_we = 0; sram2_we = 0;
        o_de = 0; // 즉시 출력

        case (state)
            IDLE: begin
                if (w_hsync_pe) state_next = FIRST;
            end

            FIRST: begin
                if (i_de) begin
                    sram1_cs = 1; sram1_we = 1;
                    sram2_cs = 0; sram2_we = 0;
                    o_de = 0; 
                    
                    if (pixel_count_reg == (ACTIVE_PIXEL - 1)) begin
                        pixel_count_next = 0;
                        line_count_next = line_count_reg + 1;
                        state_next = EVEN;
                    end else begin
                        pixel_count_next = pixel_count_reg + 1;
                    end
                end
            end

            EVEN: begin
                if (i_de) begin
                    sram1_cs = 1; sram1_we = 0; // Read SRAM1
                    sram2_cs = 1; sram2_we = 1; // Write SRAM2
                    o_de = 1; 

                    if (pixel_count_reg == (ACTIVE_PIXEL - 1)) begin
                        pixel_count_next = 0;
                        if (line_count_reg == (ACTIVE_LINE - 1)) begin
                            line_count_next = 0;
                            state_next = LAST;
                        end else begin
                            line_count_next = line_count_reg + 1;
                            state_next = ODD;
                        end
                    end else begin
                        pixel_count_next = pixel_count_reg + 1;
                    end
                end
            end

            ODD: begin
                if (i_de) begin
                    sram1_cs = 1; sram1_we = 1; // Write SRAM1
                    sram2_cs = 1; sram2_we = 0; // Read SRAM2
                    o_de = 1; 

                    if (pixel_count_reg == (ACTIVE_PIXEL - 1)) begin
                        pixel_count_next = 0;
                        if (line_count_reg == (ACTIVE_LINE - 1)) begin
                            line_count_next = 0;
                            state_next = LAST;
                        end else begin
                            line_count_next = line_count_reg + 1;
                            state_next = EVEN;
                        end
                    end else begin
                        pixel_count_next = pixel_count_reg + 1;
                    end
                end
            end

            LAST: begin 
              if (clk_count_reg == 5) begin
                    sram1_cs = 0; 
                    sram2_cs = 1; // Read SRAM2
                    sram1_we = 0; 
                    sram2_we = 0;
                    o_de = 1;

                    if (pixel_count_reg == (ACTIVE_PIXEL - 1)) begin
                        pixel_count_next = 0;
                  		clk_count_next = 0;
                        state_next = IDLE;
                    end else begin
                        pixel_count_next = pixel_count_reg + 1;
                    end
              end else begin
                clk_count_next = clk_count_reg + 1;
              end
            end
        endcase
    end
endmodule



module single_port_ram #(
  parameter					ADDR_WIDTH = 6,
  parameter					DATA_WIDTH = 30,
  parameter					RAM_DEPTH = 1 << ADDR_WIDTH
)
  (
    input						clk,
    input						i_cs,
    input						i_we,	
    input	[ADDR_WIDTH-1:0]	i_addr, // 64 bit
    input	[DATA_WIDTH-1:0]	i_din,  // 30 bit
    output	[DATA_WIDTH-1:0]	o_dout  // 30 bit
  );

  
    reg [DATA_WIDTH-1:0]    r_mem   [0:RAM_DEPTH-1];
//  reg [DATA_WIDTH-1:0]    r_tmp_data;

    // Memory read output
    // cs=1, we=0 
//  assign o_dout = (i_cs && !i_we) ? r_tmp_data : 'b0;
  assign o_dout = (i_cs && !i_we) ? r_mem[i_addr] : 'b0;

    // Memory write input
    // cs=1, we=1 
    always @(posedge clk) begin
        if (i_cs && i_we) 
            r_mem[i_addr] <= i_din;
    end

//    // Memory read input
//    // cs=1, we=0
//    always @(posedge clk) begin
//        if (i_cs && !i_we)
//            r_tmp_data <= r_mem[i_addr];
//    end
  
endmodule