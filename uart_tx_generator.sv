// UART TX Generator Class
// ------------------------------------------------------------
class uart_tx_generator;
    // Mailbox to send transactions to drivers
    mailbox gen2drv_mbx;
    // Handle to the transaction type
    uart_tx_transaction trans;

    function new(mailbox mbx);
        this.gen2drv_mbx = mbx;
    endfunction

    // Random transaction generation
    task run();
        forever begin
            trans = new();
            // Randomize transaction fields
            if (!trans.randomize()) begin
                $display("[GEN] Randomization failed");
                continue;
            end
            // Send transaction to driver mailbox
            gen2drv_mbx.put(trans);
        end
    endtask
endclass

