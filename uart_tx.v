// =====================================================================
// UART Transmitter
// Format: 1 start bit - 8 data bits - no parity - 1 stop bit (8N1)
// =====================================================================
module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,   // Tần số clock hệ thống (Hz)
    parameter BAUD_RATE = 9600          // Tốc độ baud mong muốn
)(
    input  wire       clk,
    input  wire       rst_n,      // reset tích cực mức thấp
    input  wire        tx_start,   // xung 1 chu kỳ để bắt đầu truyền
    input  wire [7:0]  tx_data,    // dữ liệu 8-bit cần gửi
    output reg          tx,         // đường dây truyền UART (nối ra chân TX)
    output reg          tx_busy     // báo hiệu đang bận truyền
);

    // Số chu kỳ clock cho 1 bit UART
    localparam integer BIT_PERIOD = CLK_FREQ / BAUD_RATE; // 5208
    // Các trạng thái của FSM
    localparam [1:0]
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11;

    reg [1:0]  state;
    reg [15:0] clk_cnt;   // đếm chu kỳ clock trong 1 bit
    reg [2:0]  bit_idx;   // đếm 8 bit dữ liệu (0-7)
    reg [7:0]  data_reg;  // thanh ghi giữ dữ liệu đang truyền

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx       <= 1'b1;   // đường truyền idle ở mức cao
            tx_busy  <= 1'b0;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            data_reg <= 8'd0;
        end else begin
            case (state)
                // ---------------------------------------------------
                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy  <= 1'b1;
                        state    <= START;
                    end
                end

                // ---------------------------------------------------
                START: begin
                    tx <= 1'b0;   // start bit = 0
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        state   <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ---------------------------------------------------
                DATA: begin
                    tx <= data_reg[bit_idx];  // gửi LSB trước
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // ---------------------------------------------------
                STOP: begin
                    tx <= 1'b1;   // stop bit = 1
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
