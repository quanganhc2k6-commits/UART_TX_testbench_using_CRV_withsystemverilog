// UART TX Coverage Class with covergroup
// ------------------------------------------------------------
class uart_tx_coverage;
    // Mailbox to receive transactions for coverage collection
    mailbox cov_mbx;
    // Instance of the covergroup
    covergroup tx_cg;
        // Coverpoint 1: transmitted data values
        data_cp: coverpoint tx_data {
            bins zero_val    = {8'h00};
            bins all_ones    = {8'hFF};
            bins alt_01      = {8'h55}; // 01010101
            bins alt_10      = {8'hAA}; // 10101010
            bins low_range   = {[8'h01:8'h3F]};
            bins mid_low     = {[8'h40:8'h7F]};
            bins mid_high    = {[8'h80:8'hBF]};
            bins high_range  = {[8'hC0:8'hFE]};
        }
        // Coverpoint 2: inter‑frame delay cycles
        delay_cp: coverpoint delay_cycles {
            bins zero_delay  = {0};
            bins short_delay = {[1:10]};
            bins med_delay   = {[11:30]};
            bins long_delay  = {[31:50]};
        }
        // Coverpoint 3: reset injection flag
        reset_cp: coverpoint inject_reset {
            bins normal_frame = {0};
            bins reset_frame  = {1};
        }
        // Coverpoint 4: reset cycle offset (only when reset is injected)
        reset_stage_cp: coverpoint reset_cycle_offset iff (inject_reset == 1) {
            bins start_bit_reset = {[20:433]};
            bins data_bit_reset  = {[434:3905]};
            bins stop_bit_reset  = {[3906:4000]};
        }
        // Cross coverage example (data vs reset flag)
        cross_data_reset: cross data_cp, reset_cp;
    endgroup

    // Constructor
    function new(mailbox mbx);
        this.cov_mbx = mbx;
        tx_cg = new();
    endfunction

    // Collect coverage from a transaction
    task collect(uart_tx_transaction tr);
        // Sample the covergroup with the transaction fields
        tx_cg.sample();
    endtask

    // Main coverage loop
    task run();
        uart_tx_transaction tr;
        forever begin
            cov_mbx.get(tr);
            // Populate temporary variables used by covergroup sampling
            // (covergroup samples directly from class members; we assign them here)
            tx_cg.tx_data = tr.tx_data;
            tx_cg.delay_cycles = tr.delay_cycles;
            tx_cg.inject_reset = tr.inject_reset;
            tx_cg.reset_cycle_offset = tr.reset_cycle_offset;
            // Sample
            tx_cg.sample();
        end
    endtask
endclass

