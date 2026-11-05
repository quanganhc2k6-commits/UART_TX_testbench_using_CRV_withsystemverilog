// UART TX Driver Class with reset injection handling
// ------------------------------------------------------------
class uart_tx_driver;
    // Virtual interface handle
    virtual uart_tx_if vif;
    // Mailbox to receive transactions from generator
    mailbox gen2drv_mbx;
    // Mailbox to send completed transactions to scoreboard
    mailbox drv2scb_mbx;
    // Mailbox to send coverage data to coverage component
    mailbox drv2cov_mbx;

    function new(virtual uart_tx_if vif, mailbox gen2drv, mailbox drv2scb, mailbox drv2cov);
        this.vif = vif;
        this.gen2drv_mbx = gen2drv;
        this.drv2scb_mbx = drv2scb;
        this.drv2cov_mbx = drv2cov;
    endfunction

    // Drive a single transaction
    task drive_one(uart_tx_transaction tr);
        // Apply optional delay before transmission
        repeat (tr.delay_cycles) @(vif.cb);
        // Drive start bit (0)
        vif.cb.tx <= 0;
        // Drive data bits (LSB first)
        foreach (tr.tx_data[i]) begin
            @(vif.cb);
            vif.cb.tx <= tr.tx_data[i];
        end
        // Drive stop bit (1)
        @(vif.cb);
        vif.cb.tx <= 1;
        // Capture reset injection if requested
        if (tr.inject_reset) begin
            // Wait for specified cycle offset within the frame
            int unsigned cnt = 0;
            while (cnt < tr.reset_cycle_offset) begin
                @(vif.cb);
                cnt++;
            end
            // Assert reset (active low)
            vif.cb.rst_n <= 0;
            // Hold reset for one cycle then release
            @(vif.cb);
            vif.cb.rst_n <= 1;
        end
        // Notify scoreboard that frame is complete
        drv2scb_mbx.put(tr);
        // Send transaction to coverage collector
        drv2cov_mbx.put(tr);
    endtask

    // Main driver loop
    task run();
        uart_tx_transaction tr;
        forever begin
            // Wait for a transaction from generator
            gen2drv_mbx.get(tr);
            // Drive the transaction
            drive_one(tr);
        end
    endtask
endclass

