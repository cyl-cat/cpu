`timescale 1ns / 1ps
// =============================================================================
// Module   : csr_top_reg
// Function : CSR register file with cycle/instret/time counters and timer
// Origin   : Converted from csr_top_reg.sv (SystemVerilog -> Verilog-2001)
// Changes  : logic->reg/wire, always_ff->always@(posedge), always_comb->always@(*)
// =============================================================================

module csr_top_reg #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [AW-1:0]     rd_addr,
    output reg  [DW-1:0]     rd_data,
    input  wire              wr_en,
    input  wire [AW-1:0]     wr_addr,
    input  wire [DW-1:0]     wr_data,
    // Machine mode CSR outputs
    output wire [DW-1:0]     mstatus_out,
    output wire [DW-1:0]     mie_out,
    output wire [DW-1:0]     mtvec_out,
    output wire [DW-1:0]     mepc_out,
    // Machine mode CSR inputs (from clint)
    input  wire [DW-1:0]     mstatus_in,
    input  wire [DW-1:0]     mcause_in,
    input  wire [DW-1:0]     mepc_in,
    input  wire [DW-1:0]     mip_in,
    input  wire [DW-1:0]     mtval_in,
    // User mode CSR outputs
    output wire [DW-1:0]     ustatus_out,
    output wire [DW-1:0]     uie_out,
    output wire [DW-1:0]     utvec_out,
    output wire [DW-1:0]     uepc_out,
    // User mode CSR inputs (from clint)
    input  wire [DW-1:0]     ustatus_in,
    input  wire [DW-1:0]     ucause_in,
    input  wire [DW-1:0]     uepc_in,
    input  wire [DW-1:0]     uip_in,
    input  wire [DW-1:0]     utval_in,
    // Control
    input  wire              set_csr_reg,
    output reg               timer_int,
    output reg               external_int_clear,
    output reg               software_int_clear,
    output reg               timer_int_clear
);

// Machine mode CSR registers
reg [DW-1:0] mstatus;
reg [DW-1:0] misa;
reg [DW-1:0] medeleg;
reg [DW-1:0] mideleg;
reg [DW-1:0] mie;
reg [DW-1:0] mtvec;
reg [DW-1:0] mcounteren;
reg [DW-1:0] mcountinhibit;
reg [DW-1:0] mstatush;
reg [DW-1:0] mscratch;
reg [DW-1:0] mepc;
reg [DW-1:0] mcause;
reg [DW-1:0] mtval;
reg [DW-1:0] mip;
reg [DW-1:0] mtinst;
reg [DW-1:0] mtval2;

// User mode CSR registers
reg [DW-1:0] ustatus;
reg [DW-1:0] uie;
reg [DW-1:0] utvec;
reg [DW-1:0] uscratch;
reg [DW-1:0] uepc;
reg [DW-1:0] ucause;
reg [DW-1:0] utval;
reg [DW-1:0] uip;

// Counters
reg [2*DW-1:0] cycle;
reg [2*DW-1:0] times;
reg [2*DW-1:0] instret;
reg [2*DW-1:0] time_num;

// Timer compare
reg [DW-1:0] mtimecmp;
reg [DW-1:0] mtimecmph;

// Control flags
reg          mtimecmp_set;
reg          mcycle_clear;
reg          minstret_clear;
reg          mtimecmp_clear;

// Output assignments
assign mstatus_out = mstatus;
assign mie_out     = mie;
assign mtvec_out   = mtvec;
assign mepc_out    = mepc;
assign ustatus_out = ustatus;
assign uie_out     = uie;
assign utvec_out   = utvec;
assign uepc_out    = uepc;

// CSR write logic
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        mstatus            <= {DW{1'b0}};
        misa               <= {DW{1'b0}};
        medeleg            <= {DW{1'b0}};
        mideleg            <= {DW{1'b0}};
        mie                <= {DW{1'b0}};
        mtvec              <= {DW{1'b0}};
        mcounteren         <= {DW{1'b0}};
        mstatush           <= {DW{1'b0}};
        mscratch           <= {DW{1'b0}};
        mepc               <= {DW{1'b0}};
        mcause             <= {DW{1'b0}};
        mtval              <= {DW{1'b0}};
        mip                <= {DW{1'b0}};
        mtinst             <= {DW{1'b0}};
        mtval2             <= {DW{1'b0}};
        mtimecmp           <= {DW{1'b0}};
        mtimecmph          <= {DW{1'b0}};
        mtimecmp_set       <= 1'b0;
        mcycle_clear       <= 1'b0;
        minstret_clear     <= 1'b0;
        mtimecmp_clear     <= 1'b0;
        external_int_clear <= 1'b0;
        software_int_clear <= 1'b0;
        timer_int_clear    <= 1'b0;
        ustatus            <= {DW{1'b0}};
        uie                <= {DW{1'b0}};
        utvec              <= {DW{1'b0}};
        uscratch           <= {DW{1'b0}};
        uepc               <= {DW{1'b0}};
        ucause             <= {DW{1'b0}};
        utval              <= {DW{1'b0}};
        uip                <= {DW{1'b0}};
    end
    else if (wr_en) begin
        case (wr_addr[11:0])
            12'h300: mstatus       <= wr_data;
            12'h301: misa          <= wr_data;
            12'h302: medeleg       <= wr_data;
            12'h303: mideleg       <= wr_data;
            12'h304: mie           <= wr_data;
            12'h305: mtvec         <= wr_data;
            12'h306: mcounteren    <= wr_data;
            12'h320: mcountinhibit <= wr_data;
            12'h310: mstatush      <= wr_data;
            12'h340: mscratch      <= wr_data;
            12'h341: mepc          <= wr_data;
            12'h342: mcause        <= wr_data;
            12'h343: mtval         <= wr_data;
            12'h344: mip           <= wr_data;
            12'h34a: mtinst        <= wr_data;
            12'h34b: mtval2        <= wr_data;
            12'hbc0: mtimecmp      <= wr_data;
            12'hbc1: mtimecmph     <= wr_data;
            12'hbc4: begin
                mtimecmp_set       <= wr_data[0];
            end
            12'hbc5: begin
                mtimecmp_clear     <= wr_data[0];
                mcycle_clear       <= wr_data[1];
                minstret_clear     <= wr_data[2];
            end
            12'hbc6: begin
                timer_int_clear    <= wr_data[0];
                software_int_clear <= wr_data[1];
                external_int_clear <= wr_data[2];
            end
            12'h000: ustatus       <= wr_data;
            12'h004: uie           <= wr_data;
            12'h005: utvec         <= wr_data;
            12'h040: uscratch      <= wr_data;
            12'h041: uepc          <= wr_data;
            12'h042: ucause        <= wr_data;
            12'h043: utval         <= wr_data;
            12'h044: uip           <= wr_data;
            default: ;
        endcase
    end
    else if (set_csr_reg) begin
        mstatus <= mstatus_in;
        mcause  <= mcause_in;
        mepc    <= mepc_in;
        mtval   <= mtval_in;
        mip     <= mip_in;
        ustatus <= ustatus_in;
        ucause  <= ucause_in;
        uepc    <= uepc_in;
        utval   <= utval_in;
        uip     <= uip_in;
    end
    else begin
        mip                <= mip_in;
        uip                <= uip_in;
        mtimecmp_set       <= 1'b0;
        mcycle_clear       <= 1'b0;
        minstret_clear     <= 1'b0;
        mtimecmp_clear     <= 1'b0;
        external_int_clear <= 1'b0;
        software_int_clear <= 1'b0;
        timer_int_clear    <= 1'b0;
    end

// CSR read logic
always @(*) begin
    if (!rst_n)
        rd_data = {DW{1'b0}};
    else begin
        case (rd_addr[11:0])
            12'h300: rd_data = mstatus;
            12'h301: rd_data = misa;
            12'h302: rd_data = medeleg;
            12'h303: rd_data = mideleg;
            12'h304: rd_data = mie;
            12'h305: rd_data = mtvec;
            12'h306: rd_data = mcounteren;
            12'h310: rd_data = mstatush;
            12'h340: rd_data = mscratch;
            12'h341: rd_data = mepc;
            12'h342: rd_data = mcause;
            12'h343: rd_data = mtval;
            12'h344: rd_data = mip;
            12'h34a: rd_data = mtinst;
            12'h34b: rd_data = mtval2;
            12'hb00: rd_data = cycle[31:0];
            12'hb80: rd_data = cycle[63:32];
            12'hb02: rd_data = instret[31:0];
            12'hb82: rd_data = instret[63:32];
            12'hbc0: rd_data = mtimecmp;
            12'hbc1: rd_data = mtimecmph;
            12'hbc2: rd_data = times[31:0];
            12'hbc3: rd_data = times[63:32];
            12'h000: rd_data = ustatus;
            12'h004: rd_data = uie;
            12'h005: rd_data = utvec;
            12'h040: rd_data = uscratch;
            12'h041: rd_data = uepc;
            12'h042: rd_data = ucause;
            12'h043: rd_data = utval;
            12'h044: rd_data = uip;
            12'hc00: rd_data = cycle[31:0];
            12'hc80: rd_data = cycle[63:32];
            12'hc01: rd_data = times[31:0];
            12'hc81: rd_data = times[63:32];
            12'hc02: rd_data = instret[31:0];
            12'hc82: rd_data = instret[63:32];
            default: rd_data = {DW{1'b0}};
        endcase
    end
end

// Timer compare value register
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        time_num <= {2*DW{1'b0}};
    else if (mtimecmp_set)
        time_num <= {mtimecmph, mtimecmp};

// Cycle counter
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        cycle <= {2*DW{1'b0}};
    else if (mcycle_clear)
        cycle <= {2*DW{1'b0}};
    else if (mcountinhibit[0])
        cycle <= cycle;
    else
        cycle <= cycle + 64'h1;

// Instruction retired counter
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        instret <= {2*DW{1'b0}};
    else if (minstret_clear)
        instret <= {2*DW{1'b0}};
    else if (mcountinhibit[2])
        instret <= instret;
    else
        instret <= instret + 64'h1;

// Time counter
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        times <= {2*DW{1'b0}};
    else if (mtimecmp_clear)
        times <= {2*DW{1'b0}};
    else if (times >= time_num)
        times <= times;
    else
        times <= times + 64'h1;

// Timer interrupt generation
always @(posedge clk or negedge rst_n)
    if (!rst_n)
        timer_int <= 1'b0;
    else if (mtimecmp_clear)
        timer_int <= 1'b0;
    else if (~|times)
        timer_int <= 1'b0;
    else if (times >= time_num)
        timer_int <= 1'b1;

endmodule
