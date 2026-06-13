/*
 * a2065_ddr3_test.v — Writes a magic pattern to DDR3 via Avalon master.
 * Used to verify f2sdram2 path and find ARM-side physical address mapping.
 *
 * DDR3 layout (64KB region at DDR3_TEST_BASE):
 *   0x00: Magic value (64-bit) = {32'hA2065A20, 32'h65A20650}
 *   0x08: Counter incrementing every ~1ms
 *   0x10: Status register
 */

module a2065_ddr3_test (
    input  wire         clk,
    input  wire         rst,

    // Avalon-MM master to DDR3
    output reg  [28:0]  avl_address,
    output reg  [7:0]   avl_burstcount,
    output reg          avl_read,
    input  wire [63:0]  avl_readdata,
    input  wire         avl_readdatavalid,
    output reg  [63:0]  avl_writedata,
    output reg  [7:0]   avl_byteenable,
    output reg          avl_write,
    input  wire         avl_waitrequest,

    // Debug output
    output reg  [63:0]  debug_readback,
    output reg          debug_done
);

    localparam DDR3_TEST_BASE = 29'h0;

    reg [2:0] state;
    reg [31:0] counter;
    reg [63:0] heartbeat_val;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= 0;
            avl_address    <= 0;
            avl_burstcount <= 1;
            avl_read       <= 0;
            avl_writedata  <= 0;
            avl_byteenable <= 8'hFF;
            avl_write      <= 0;
            counter        <= 0;
            heartbeat_val  <= 0;
            debug_readback <= 0;
            debug_done     <= 0;
        end else begin
            avl_read  <= 0;
            avl_write <= 0;

            case (state)
            0: begin
                avl_address    <= DDR3_TEST_BASE;
                avl_writedata  <= {32'hA2065A20, 32'h65A20650};
                avl_byteenable <= 8'hFF;
                avl_burstcount <= 1;
                avl_write      <= 1;
                state          <= 1;
            end
            1: begin
                if (!avl_waitrequest) begin
                    avl_write <= 0;
                    state     <= 2;
                end else begin
                    avl_write <= 1;
                end
            end
            2: begin
                avl_address    <= DDR3_TEST_BASE;
                avl_burstcount <= 1;
                avl_read       <= 1;
                state          <= 3;
            end
            3: begin
                if (avl_readdatavalid) begin
                    debug_readback <= avl_readdata;
                    debug_done     <= 1;
                    state          <= 4;
                end
            end
            4: begin
                counter <= counter + 1;
                if (counter == 32'd5_000_000) begin
                    counter       <= 0;
                    heartbeat_val <= heartbeat_val + 1;
                    avl_address   <= DDR3_TEST_BASE + 29'h8;
                    avl_writedata <= {32'd0, heartbeat_val[31:0]};
                    avl_byteenable <= 8'hFF;
                    avl_burstcount <= 1;
                    avl_write      <= 1;
                    state          <= 5;
                end
            end
            5: begin
                if (!avl_waitrequest) begin
                    avl_write <= 0;
                    state     <= 4;
                end else begin
                    avl_write <= 1;
                end
            end
            endcase
        end
    end

endmodule
