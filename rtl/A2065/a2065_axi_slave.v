/*
 * a2065_axi_slave.v — Minimal AXI4-Lite slave for A2065 bridge.
 * Delays R channel response by one cycle after AR handshake
 * to be compatible with the Cyclone V hps2fpga bridge.
 */

module a2065_axi_slave (
    input  wire        aclk,
    input  wire        arst_n,

    output reg  [1:0]  s_axi_awready,
    input  wire [1:0]  s_axi_awvalid,
    input  wire [29:0] s_axi_awaddr,
    input  wire [11:0] s_axi_awid,

    output reg         s_axi_wready,
    input  wire        s_axi_wvalid,
    input  wire [31:0] s_axi_wdata,
    input  wire [7:0]  s_axi_wstrb,

    input  wire        s_axi_bready,
    output reg         s_axi_bvalid,
    output reg  [1:0]  s_axi_bresp,
    output reg  [11:0] s_axi_bid,

    output reg         s_axi_arready,
    input  wire        s_axi_arvalid,
    input  wire [29:0] s_axi_araddr,
    input  wire [11:0] s_axi_arid,

    input  wire        s_axi_rready,
    output reg         s_axi_rvalid,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg  [11:0] s_axi_rid,

    output wire [15:0] arm_bridge_result,
    output wire        arm_bridge_done,

    input  wire [15:0] fpga_bridge_data,
    input  wire [7:0]  fpga_bridge_addr_off,
    input  wire        fpga_bridge_rw,
    input  wire        fpga_bridge_new_req,

    output reg  [14:1] arm_bram_addr,
    output reg  [15:0] arm_bram_wdata,
    output reg         arm_bram_wr,
    output reg  [1:0]  arm_bram_be,
    input  wire [15:0] arm_bram_rdata
);

    reg [15:0] reg_result;
    reg        reg_done;
    reg  [5:0] reg_mac [0:5];

    assign arm_bridge_result = reg_result;
    assign arm_bridge_done   = reg_done;

    reg [29:0] pending_rd_addr;
    reg [11:0] pending_rd_id;
    reg        rd_pending;

    reg [29:0] wr_addr;
    reg [11:0] wr_id;
    reg        wr_data_pending;

    integer i;

    always @(posedge aclk or negedge arst_n) begin
        if (!arst_n) begin
            s_axi_arready   <= 1'b0;
            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= 32'd0;
            s_axi_rresp     <= 2'b00;
            s_axi_rid       <= 12'd0;
            rd_pending      <= 1'b0;
            pending_rd_addr <= 30'd0;
            pending_rd_id   <= 12'd0;

            s_axi_awready    <= 2'b00;
            s_axi_wready     <= 1'b0;
            s_axi_bvalid     <= 1'b0;
            s_axi_bresp      <= 2'b00;
            s_axi_bid        <= 12'd0;
            wr_addr          <= 30'd0;
            wr_id            <= 12'd0;
            wr_data_pending  <= 1'b0;

            arm_bram_wr     <= 1'b0;
            arm_bram_addr   <= 14'd0;
            arm_bram_wdata  <= 16'd0;
            arm_bram_be     <= 2'b00;
            reg_result      <= 16'd0;
            reg_done        <= 1'b0;
            for (i = 0; i < 6; i = i + 1) reg_mac[i] <= 6'd0;
        end else begin
            arm_bram_wr <= 1'b0;

            // ---- AR channel: accept read address ----
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready   <= 1'b0;
                pending_rd_addr <= s_axi_araddr;
                pending_rd_id   <= s_axi_arid;
                rd_pending      <= 1'b1;
            end else if (!rd_pending && !s_axi_rvalid) begin
                s_axi_arready <= s_axi_arvalid;
            end

            // ---- R channel: respond one cycle after AR handshake ----
            if (rd_pending && !s_axi_rvalid) begin
                rd_pending   <= 1'b0;
                s_axi_rvalid <= 1'b1;
                s_axi_rid    <= pending_rd_id;
                s_axi_rresp  <= 2'b00;

                if (pending_rd_addr[15]) begin
                    arm_bram_addr <= pending_rd_addr[14:1];
                    s_axi_rdata   <= {16'd0, arm_bram_rdata};
                end else begin
                    case (pending_rd_addr[3:0])
                    4'h0: s_axi_rdata <= {16'd0, fpga_bridge_data};
                    4'h2: s_axi_rdata <= {24'd0, fpga_bridge_addr_off};
                    4'h3: s_axi_rdata <= {24'd0, {7'd0, fpga_bridge_rw}};
                    4'h4: s_axi_rdata <= {24'd0, {7'd0, fpga_bridge_new_req}};
                    4'h5: s_axi_rdata <= {24'd0, {7'd0, reg_done}};
                    4'h6: s_axi_rdata <= {16'd0, reg_result};
                    4'h8: s_axi_rdata <= {24'd0, reg_mac[0]};
                    4'h9: s_axi_rdata <= {24'd0, reg_mac[1]};
                    4'hA: s_axi_rdata <= {24'd0, reg_mac[2]};
                    4'hB: s_axi_rdata <= {24'd0, reg_mac[3]};
                    4'hC: s_axi_rdata <= {24'd0, reg_mac[4]};
                    4'hD: s_axi_rdata <= {24'd0, reg_mac[5]};
                    default: s_axi_rdata <= 32'd0;
                    endcase
                end
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end

            // ---- AW channel: accept write address ----
            if (s_axi_awvalid[0] && s_axi_awready[0]) begin
                s_axi_awready   <= 2'b00;
                wr_addr         <= s_axi_awaddr;
                wr_id           <= s_axi_awid;
                wr_data_pending <= 1'b1;
            end else if (!wr_data_pending && !s_axi_wready && !s_axi_bvalid) begin
                s_axi_awready <= s_axi_awvalid[0] ? 2'b01 : 2'b00;
            end

            // ---- W channel: accept write data ----
            if (wr_data_pending && s_axi_wvalid) begin
                wr_data_pending <= 1'b0;
                s_axi_wready    <= 1'b1;

                if (wr_addr[15]) begin
                    arm_bram_addr  <= wr_addr[14:1];
                    arm_bram_wdata <= s_axi_wdata[15:0];
                    arm_bram_wr    <= 1'b1;
                    arm_bram_be    <= s_axi_wstrb[1:0];
                end else begin
                    case (wr_addr[3:0])
                    4'h0: reg_result <= s_axi_wdata[15:0];
                    4'h5: reg_done   <= s_axi_wdata[0];
                    4'h6: reg_result <= s_axi_wdata[15:0];
                    default: ;
                    endcase
                    case (wr_addr[3:0])
                    4'h8: reg_mac[0] <= s_axi_wdata[7:0];
                    4'h9: reg_mac[1] <= s_axi_wdata[7:0];
                    4'hA: reg_mac[2] <= s_axi_wdata[7:0];
                    4'hB: reg_mac[3] <= s_axi_wdata[7:0];
                    4'hC: reg_mac[4] <= s_axi_wdata[7:0];
                    4'hD: reg_mac[5] <= s_axi_wdata[7:0];
                    default: ;
                    endcase
                end
            end else begin
                s_axi_wready <= 1'b0;
            end

            // ---- B channel: write response ----
            if (s_axi_wready && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bid    <= wr_id;
                s_axi_bresp  <= 2'b00;
            end
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule
