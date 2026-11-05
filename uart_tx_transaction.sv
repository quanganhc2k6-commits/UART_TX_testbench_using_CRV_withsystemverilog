// UART TX Transaction Class with constraints and reset injection
// ------------------------------------------------------------
class uart_tx_transaction;
    // Data to be transmitted (8‑bit)
    rand bit [7:0] tx_data;
    // Number of clock cycles to delay before transmitting this frame
    rand int unsigned delay_cycles;
    // Flag indicating whether a reset should be injected during this frame
    rand bit inject_reset;
    // If inject_reset == 1, the cycle offset within the frame where reset occurs
    rand int unsigned reset_cycle_offset;

    // Random constraints for realistic stimulus
    constraint tx_data_c {
        // All possible data values are allowed
    }
    constraint delay_c {
        delay_cycles inside {[0:50]}; // match coverage bins
    }
    constraint inject_reset_c {
        inject_reset inside {0,1};
    }
    constraint reset_offset_c {
        // Only constrain when reset is injected
        if (inject_reset) {
            // Frame = 10 bits = 4340 cycles (approx)
            reset_cycle_offset inside {[20:4000]};
        } else {
            reset_cycle_offset == 0;
        }
    }
endclass

