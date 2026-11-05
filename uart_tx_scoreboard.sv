// UART TX Scoreboard Class
// ------------------------------------------------------------
class uart_tx_scoreboard;
    // Mailbox to receive transactions from driver (completed frames)
    mailbox drv2scb_mbx;
    // Mailbox to receive transactions from monitor (captured frames)
    mailbox mon2scb_mbx;
    // Counters for statistics
    int unsigned total_drv_frames = 0;
    int unsigned total_mon_frames = 0;
    int unsigned mismatched_frames = 0;

    function new(mailbox drv2scb, mailbox mon2scb);
        this.drv2scb_mbx = drv2scb;
        this.mon2scb_mbx = mon2scb;
    endfunction

    // Compare a driver‑generated transaction with a monitor‑captured transaction
    function void compare(uart_tx_transaction drv_tr, uart_tx_transaction mon_tr);
        if (drv_tr.tx_data !== mon_tr.tx_data ||
            drv_tr.inject_reset !== mon_tr.inject_reset) begin
            mismatched_frames++;
            $display("[SCB] Mismatch detected: drv_tx=%h mon_tx=%h", drv_tr.tx_data, mon_tr.tx_data);
        end else begin
            // No mismatch – optional success message
        end
    endfunction

    // Main scoreboard loop
    task run();
        uart_tx_transaction drv_tr;
        uart_tx_transaction mon_tr;
        forever begin
            // Receive a driver frame
            drv2scb_mbx.get(drv_tr);
            total_drv_frames++;
            // Receive the corresponding monitor frame (blocking order)
            mon2scb_mbx.get(mon_tr);
            total_mon_frames++;
            // Compare the two
            compare(drv_tr, mon_tr);
        end
    endtask
endclass

