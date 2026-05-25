module a2065_ddram #(
	parameter [28:0] DDR3_BASE = 29'h60000000
) (
	input  wire        clk,
	input  wire        rst_n,

	input  wire [7:0]  card_base,
	input  wire        card_configured,

	input  wire [23:1] cpu_addr,
	input  wire        cpu_rw,
	input  wire        cpu_as_n,
	input  wire        cpu_uds_n,
	input  wire        cpu_lds_n,
	input  wire [15:0] cpu_data_in,
	output wire [15:0] cpu_data_out,
	output reg         nrdy,

	input  wire        bus_avail,
	output reg  [28:0] ddram_addr,
	output reg  [63:0] ddram_din,
	output reg  [7:0]  ddram_be,
	output reg         ddram_rd,
	output reg         ddram_we,
	input  wire [63:0] ddram_dout,
	input  wire        ddram_dout_ready
);

	localparam ST_IDLE   = 3'd0;
	localparam ST_WAIT   = 3'd1;
	localparam ST_READ   = 3'd2;
	localparam ST_WRITE  = 3'd3;
	localparam ST_DONE   = 3'd4;

	reg [2:0] state;
	reg [23:1] saved_addr;
	reg [15:0] saved_data;
	reg        saved_rw;
	reg        saved_uds;
	reg        saved_lds;
	reg [15:0] read_data;
	reg        read_valid;

	wire sel_boardram = card_configured &&
	                    (cpu_addr[23:16] == card_base) &&
	                    cpu_addr[15] &&
	                    !cpu_as_n &&
	                    (!cpu_uds_n || !cpu_lds_n);

	wire [15:3] word_addr = saved_addr[15:3];
	wire [1:0]  word_off  = saved_addr[2:1];
	wire [1:0]  byte_sel  = {~saved_uds, ~saved_lds};

	assign cpu_data_out = read_valid ? read_data : 16'd0;

	always @(posedge clk) begin
		if (!rst_n) begin
			state      <= ST_IDLE;
			nrdy       <= 1'b0;
			read_valid <= 1'b0;
			read_data  <= 16'd0;
			ddram_rd   <= 1'b0;
			ddram_we   <= 1'b0;
		end else begin
			case (state)
			ST_IDLE: begin
				ddram_rd   <= 1'b0;
				ddram_we   <= 1'b0;
				read_valid <= 1'b0;
				if (sel_boardram) begin
					saved_addr <= cpu_addr;
					saved_data <= cpu_data_in;
					saved_rw   <= cpu_rw;
					saved_uds  <= cpu_uds_n;
					saved_lds  <= cpu_lds_n;
					nrdy       <= 1'b1;
					state      <= ST_WAIT;
				end
			end

			ST_WAIT: begin
				if (bus_avail) begin
					ddram_addr <= DDR3_BASE + {16'd0, word_addr, 3'd0};
					if (saved_rw) begin
						ddram_rd <= 1'b1;
						state    <= ST_READ;
					end else begin
						ddram_din <= {saved_data, saved_data, saved_data, saved_data};
						ddram_be  <= {6'd0, byte_sel} << {word_off, 1'b0};
						ddram_we  <= 1'b1;
						state     <= ST_WRITE;
					end
				end
			end

			ST_READ: begin
				if (ddram_dout_ready) begin
					ddram_rd    <= 1'b0;
					read_data  <= ddram_dout[{word_off, 4'd0} +: 16];
					read_valid <= 1'b1;
					nrdy       <= 1'b0;
					state      <= ST_DONE;
				end
			end

			ST_WRITE: begin
				ddram_we <= 1'b0;
				nrdy     <= 1'b0;
				state    <= ST_DONE;
			end

			ST_DONE: begin
				if (cpu_as_n) begin
					read_valid <= 1'b0;
					nrdy       <= 1'b0;
					state      <= ST_IDLE;
				end
			end
			endcase
		end
	end

endmodule
