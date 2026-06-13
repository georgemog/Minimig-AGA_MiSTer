module avalon_arbiter #(
    parameter ADDR_W  = 29,
    parameter DATA_W  = 64,
    parameter BURST_W = 8,
    parameter BYTE_W  = 8
)(
    input  wire                          clk,
    input  wire                          rst,

    input  wire [ADDR_W-1:0]             m0_address,
    input  wire [BURST_W-1:0]            m0_burstcount,
    input  wire                          m0_read,
    output wire [DATA_W-1:0]             m0_readdata,
    output wire                          m0_readdatavalid,
    input  wire [DATA_W-1:0]             m0_writedata,
    input  wire [BYTE_W-1:0]            m0_byteenable,
    input  wire                          m0_write,
    output wire                          m0_waitrequest,

    input  wire [ADDR_W-1:0]             m1_address,
    input  wire [BURST_W-1:0]            m1_burstcount,
    input  wire                          m1_read,
    output wire [DATA_W-1:0]             m1_readdata,
    output wire                          m1_readdatavalid,
    input  wire [DATA_W-1:0]             m1_writedata,
    input  wire [BYTE_W-1:0]            m1_byteenable,
    input  wire                          m1_write,
    output wire                          m1_waitrequest,

    output reg  [ADDR_W-1:0]             s_address,
    output reg  [BURST_W-1:0]            s_burstcount,
    output reg                           s_read,
    input  wire [DATA_W-1:0]             s_readdata,
    input  wire                          s_readdatavalid,
    output reg  [DATA_W-1:0]             s_writedata,
    output reg  [BYTE_W-1:0]            s_byteenable,
    output reg                           s_write,
    input  wire                          s_waitrequest
);

    reg burst_active;
    reg burst_is_read;
    reg [BURST_W-1:0] burst_count;
    reg last_grant;
    reg rd_grant;

    wire m0_req = m0_read || m0_write;
    wire m1_req = m1_read || m1_write;

    wire grant;
    assign grant = burst_active ? last_grant :
                   (m0_req && m1_req) ? ~last_grant :
                   m1_req ? 1'b1 :
                   1'b0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            burst_active  <= 1'b0;
            burst_is_read <= 1'b0;
            burst_count   <= 0;
            last_grant    <= 1'b0;
            rd_grant      <= 1'b0;
        end else begin
            if (!burst_active && grant == 1'b0 && m0_req && !s_waitrequest) begin
                burst_active  <= 1'b1;
                burst_is_read <= m0_read;
                burst_count   <= m0_burstcount;
                last_grant    <= 1'b0;
                if (m0_read) rd_grant <= 1'b0;
            end
            else if (!burst_active && grant == 1'b1 && m1_req && !s_waitrequest) begin
                burst_active  <= 1'b1;
                burst_is_read <= m1_read;
                burst_count   <= m1_burstcount;
                last_grant    <= 1'b1;
                if (m1_read) rd_grant <= 1'b1;
            end

            if (burst_active) begin
                if (burst_is_read) begin
                    if (s_readdatavalid) begin
                        burst_count <= burst_count - 1'b1;
                        if (burst_count == 8'd1)
                            burst_active <= 1'b0;
                    end
                end else begin
                    if ((grant == 1'b0 && m0_write) || (grant == 1'b1 && m1_write)) begin
                        if (!s_waitrequest) begin
                            burst_count <= burst_count - 1'b1;
                            if (burst_count == 8'd1)
                                burst_active <= 1'b0;
                        end
                    end
                end
            end

            if (s_read && !s_waitrequest) begin
                rd_grant <= grant;
            end
        end
    end

    always @(*) begin
        if (grant == 1'b0) begin
            s_address    = m0_address;
            s_burstcount = m0_burstcount;
            s_read       = m0_read;
            s_writedata  = m0_writedata;
            s_byteenable = m0_byteenable;
            s_write      = m0_write;
        end else begin
            s_address    = m1_address;
            s_burstcount = m1_burstcount;
            s_read       = m1_read;
            s_writedata  = m1_writedata;
            s_byteenable = m1_byteenable;
            s_write      = m1_write;
        end
    end

    assign m0_waitrequest   = (grant == 1'b0) ? s_waitrequest : 1'b1;
    assign m0_readdata      = s_readdata;
    assign m0_readdatavalid = (rd_grant == 1'b0) ? s_readdatavalid : 1'b0;

    assign m1_waitrequest   = (grant == 1'b1) ? s_waitrequest : 1'b1;
    assign m1_readdata      = s_readdata;
    assign m1_readdatavalid = (rd_grant == 1'b1) ? s_readdatavalid : 1'b0;

endmodule
