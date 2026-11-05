`timescale 1ns/1ps

// Include mã nguồn DUT và testbench components
`include "../uart_tx.v"
`include "CRV_flow_component.sv"

module tb_top;
  bit clk;

  // Clock 50MHz (chu kỳ 20ns)
  always #10 clk = ~clk;

  // Khởi tạo Interface (vif.rst_n do Interface quản lý để Driver có thể điều khiển trực tiếp)
  uart_tx_if vif(clk);

  // Khởi tạo DUT với baudrate 115200 (khớp bit_period = 434)
  uart_tx #(
    .CLK_FREQ(50_000_000),
    .BAUD_RATE(115200)
  ) dut (
    .clk(vif.clk),
    .rst_n(vif.rst_n),
    .tx_start(vif.tx_start),
    .tx_data(vif.tx_data),
    .tx(vif.tx),
    .tx_busy(vif.tx_busy)
  );

  uart_tx_evn evn;

  initial begin
    clk = 0;
    vif.rst_n = 0;
    #40;
    vif.rst_n = 1;

    evn = new(vif);
    evn.run(); // chạy mô phỏng CRV có tích hợp ngắt Reset giữa frame

    // Kết thúc mô phỏng
    $display("TB_TOP hoàn thành mô phỏng UART TX Verification!");
    $finish;
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end
endmodule
