`timescale 1ns / 1ps

module btb #(
    parameter AW     = 32,
    parameter BTB_AW = 5
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [AW-1:0]     if_pc,
    output wire              btb_hit,
    output wire [AW-1:0]     btb_target,
    input  wire              update_en,
    input  wire [AW-1:0]     update_pc,
    input  wire [AW-1:0]     update_target,
    input  wire              update_taken
);

localparam NUM_ENTRIES = 1 << BTB_AW;
localparam TAG_W       = AW - BTB_AW - 2;
localparam ENTRY_W     = 1 + TAG_W + AW;   // {valid, tag, target}

(* ram_style = "distributed" *)
reg [ENTRY_W-1:0] btb_mem [0:NUM_ENTRIES-1];

wire [BTB_AW-1:0] if_index     = if_pc[BTB_AW+1:2];
wire [TAG_W-1:0]  if_tag       = if_pc[AW-1:BTB_AW+2];
wire [BTB_AW-1:0] update_index = update_pc[BTB_AW+1:2];
wire [TAG_W-1:0]  update_tag   = update_pc[AW-1:BTB_AW+2];

wire [ENTRY_W-1:0] if_entry = btb_mem[if_index];
wire               if_valid = if_entry[ENTRY_W-1];
wire [TAG_W-1:0]   if_stag  = if_entry[AW+TAG_W-1:AW];
wire [AW-1:0]      if_tgt   = if_entry[AW-1:0];

assign btb_hit    = if_valid && (if_stag == if_tag);
assign btb_target = if_tgt;

integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < NUM_ENTRIES; i = i + 1)
            btb_mem[i] <= {ENTRY_W{1'b0}};
    end
    else if (update_en) begin
        if (update_taken)
            btb_mem[update_index] <= {1'b1, update_tag, update_target};
        else
            btb_mem[update_index] <= {1'b0, update_tag, update_target};
    end
end

endmodule