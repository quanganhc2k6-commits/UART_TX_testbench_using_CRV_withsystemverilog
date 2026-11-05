// UART TX Interface
// ------------------------------------------------------------
// This interface groups the signals needed by the UART transmitter
// testbench components (driver, monitor, etc.).
// ------------------------------------------------------------
interface uart_tx_if (input bit clk);
    // Active‑low reset (asserted when rst_n == 0)
    bit rst_n;
    // Serial transmit line from the DUT
    bit tx;
    // Clocking block for synchronous stimulus/checking
    clocking cb @(posedge clk);
        default input #1step output #1step;
        output rst_n;
        output tx;
    endclocking
endinterface

