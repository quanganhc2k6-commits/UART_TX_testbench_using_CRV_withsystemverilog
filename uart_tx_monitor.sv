// UART TX Monitor Class
// ------------------------------------------------------------
class uart_tx_monitor;
    // Virtual interface handle
    virtual uart_tx_if vif;
    // Mailbox to send captured transactions to scoreboard
    mailbox mon2scb_mbx;
    // Mailbox to send captured transactions to coverage
    mailbox mon2cov_mbx;

    // Constructor
    function new(virtual uart_tx_if vif, mailbox mon2scb, mailbox mon2cov);
        this.vif = vif;
        this.mon2scb_mbx = mon2scb;
        this.mon2cov_mbx = mon2cov;
    endfunction

    // Capture a single transmitted frame
    task capture_one(output uart_tx_transaction tr);
        tr = new();
        // Wait for line to be idle (tx = 1) and reset deasserted
        wait (vif.rst_n == 1 && vif.tx == 1);
        // Detect start bit (0) or reset
        fork
            begin : wait_start
                wait (vif.tx == 0);
            end
            begin : wait_rst
                wait (vif.rst_n == 0);
            end
        join_any
        disable fork;

        // If reset occurred before start bit, mark reset injection for this frame
        if (vif.rst_n == 0) begin
            tr.inject_reset = 1;
            // Determine reset cycle offset (approximate count from start of frame)
            int unsigned cnt = 0;
            // Wait until reset is released then resume normal capture
            wait (vif.rst_n == 1);
            // Continue without capturing data (frame considered aborted)
            tr.tx_data = '0;
            tr.delay_cycles = 0;
            tr.reset_cycle_offset = 0;
            return;
        end else begin
            tr.inject_reset = 0;
        end

        // Capture start bit (already 0)
        @(vif.cb);
        // Capture data bits (LSB first)
        foreach (tr.tx_data[i]) begin
            @(vif.cb);
            tr.tx_data[i] = vif.tx;
        end
        // Capture stop bit (should be 1)
        @(vif.cb);
        // No need to store stop bit; just verify it is 1 if desired
        // Delay cycles before next frame – optional, set to 0 for now
        tr.delay_cycles = 0;
        // No reset injection in this captured frame
        tr.reset_cycle_offset = 0;
    endtask

    // Main monitor loop
    task run();
        uart_tx_transaction tr;
        forever begin
            capture_one(tr);
            // Send captured transaction to scoreboard and coverage components
            mon2scb_mbx.put(tr);
            mon2cov_mbx.put(tr);
        end
    endtask
endclass

