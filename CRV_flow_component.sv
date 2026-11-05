//-------------------Interface----------------------
interface uart_tx_if(input logic clk);
  logic rst_n;
  logic tx_start;
  logic [7:0] tx_data;
  logic tx_busy;
  logic tx;

  clocking driver_cb @(posedge clk);
    default input #1step output #1;
    output tx_start;
    output tx_data;
    input  tx_busy;
  endclocking

  clocking monitor_cb @(posedge clk);
    default input #1step;
    input tx;
    input tx_busy;
  endclocking
endinterface

//-----------------Transaction-------------------
class uart_tx_transaction;
  rand bit [7:0] tx_data;
  rand int       delay_cycles;
  rand bit       inject_reset;        // 1: kích hoạt reset giữa frame, 0: frame bình thường
  rand int       reset_cycle_offset;  // vị trí chu kỳ clock kích hoạt reset trong frame

  constraint delay_c {
    delay_cycles dist {0 := 20, [1:10] :/ 50, [11:50] :/ 30};
    // dist = distribution (phân phối) 
    // ':=' trọng lượng cho từng giá trị
    // ':/' trọng lượng cho tổng các giá trị
  }

  // Constraint cho dữ liệu: tăng trọng số cho các corner case toàn bit 0, toàn bit 1 và các mẫu kiểm thử
  constraint data_c {
    tx_data dist {
      8'h00 := 20,          // Toàn bit 0 (8'b0000_0000)
      8'hFF := 20,          // Toàn bit 1 (8'b1111_1111)
      8'h55 := 10,          // Mẫu xen kẽ 01010101
      8'hAA := 10,          // Mẫu xen kẽ 10101010
      [8'h01:8'hFE] :/ 40   // Các giá trị ngẫu nhiên khác
    };
  }

  // Constraint cho kịch bản Reset giữa frame:
  // ~15% gói tin bị reset giữa chừng, ~85% gói tin bình thường
  // 1 frame 10 bit @ baud 115200 chiếm 4340 chu kỳ clock
  constraint reset_c {
    inject_reset dist {0 := 85, 1 := 15};
    reset_cycle_offset inside {[20 : 4000]};
  }

  function uart_tx_transaction clone();
    uart_tx_transaction t = new();
    t.tx_data            = this.tx_data;
    t.delay_cycles       = this.delay_cycles;
    t.inject_reset       = this.inject_reset;
    t.reset_cycle_offset = this.reset_cycle_offset;
    return t;
  endfunction

  function void print(string name = "TRANSACTION");
    $display("[%s] Data: 8'h%0h | Delay: %0d | InjectReset: %0b (offset: %0d)",
             name, tx_data, delay_cycles, inject_reset, reset_cycle_offset);
  endfunction
endclass

//------------------Generator-----------------
class uart_tx_generator;
  mailbox gen2drv_mbx;
  mailbox gen2scb_mbx;
  mailbox gen2cov_mbx;
  int num_transaction = 60;
  event gen_done;

  function new(mailbox gen2drv_mbx, mailbox gen2scb_mbx, mailbox gen2cov_mbx);
    this.gen2drv_mbx = gen2drv_mbx;
    this.gen2scb_mbx = gen2scb_mbx;
    this.gen2cov_mbx = gen2cov_mbx;
  endfunction

  task run();
    uart_tx_transaction trans;
    for (int i = 0; i < num_transaction; i++) begin
      trans = new();
      if (!trans.randomize())
        $fatal(1, "Generator: Randomization failed!");
      gen2drv_mbx.put(trans.clone());
      gen2scb_mbx.put(trans.clone());
      gen2cov_mbx.put(trans.clone());
    end
    ->gen_done;
  endtask
endclass

//---------------Driver--------------------
class uart_tx_driver;
  mailbox mbx;
  virtual uart_tx_if vif;

  function new(mailbox mbx, virtual uart_tx_if vif);
    this.mbx = mbx;
    this.vif = vif;
  endfunction

  task run();
    uart_tx_transaction trans;
    vif.driver_cb.tx_start <= 0;
    vif.driver_cb.tx_data  <= 8'h00; // đặt trạng thái ban đầu tránh X

    forever begin
      mbx.get(trans); // mở hòm thư và lấy gói tin
      wait(vif.rst_n == 1);  // đợi thoat khỏi reset = 1
      wait(vif.driver_cb.tx_busy == 0); // đợi DUT  rảnh rỗi
      @(vif.driver_cb);
      vif.driver_cb.tx_data  <= trans.tx_data;
      vif.driver_cb.tx_start <= 1;

      @(vif.driver_cb);
      vif.driver_cb.tx_start <= 0;

      if (trans.inject_reset) begin
        // KỊCH BẢN KÍCH HOẠT RESET GIỮA FRAME
        repeat(trans.reset_cycle_offset) @(vif.driver_cb); // đợi n lần lệnh clock
        $display("[%0t ns] [DRIVER] >> KÍCH HOẠT RESET GIỮA FRAME! (Data: 8'h%0h, Offset: %0d cycles)",
                 $time, trans.tx_data, trans.reset_cycle_offset);

        // Kéo Reset bất đồng bộ
        vif.rst_n <= 1'b0;

        // Kiểm tra phản ứng tức thời của DUT khi reset
        #1;
        if (vif.tx === 1'b1 && vif.tx_busy === 1'b0) begin
          $display("[%0t ns] [DRIVER] [PASS] DUT lập tức IDLE (tx=1, tx_busy=0) khi nhận Reset!", $time);
        end else begin
          $error("[%0t ns] [DRIVER] [FAIL] DUT phản ứng sai khi Reset! tx=%b, tx_busy=%b", 
                 $time, vif.tx, vif.tx_busy);
        end

        // Giữ reset trong 10 chu kỳ clock
        repeat(10) @(vif.driver_cb);
        vif.rst_n <= 1'b1;
        $display("[%0t ns] [DRIVER] >> NHẢ RESET (rst_n = 1)", $time);

        // Chờ DUT ổn định sau khi nhả reset
        repeat(20) @(vif.driver_cb);
      end else begin
        // FRAME BÌNH THƯỜNG: Chờ DUT truyền xong và delay ngẫu nhiên
        wait(vif.driver_cb.tx_busy == 1);
        wait(vif.driver_cb.tx_busy == 0);
        repeat(trans.delay_cycles) @(vif.driver_cb);
      end
    end
  endtask
endclass

//---------------Monitor------------------
class uart_tx_monitor;
  mailbox mbx;
  virtual uart_tx_if vif;
  // clock 50Mhz, baudrate 115200 -> bit_period = 434
  int bit_period = 434;

  function new(mailbox mbx, virtual uart_tx_if vif);
    this.mbx = mbx;
    this.vif = vif;
  endfunction

  task run();
    uart_tx_transaction trans;
    logic [7:0] captured_data;
    bit frame_aborted;

    forever begin
      // Đợi đường truyền IDLE và rst_n không tích cực
      wait(vif.rst_n == 1 && vif.monitor_cb.tx == 1);

      // Chờ phát hiện cạnh xuống (start bit) hoặc bị reset
      fork
        begin : wait_start
          wait(vif.monitor_cb.tx == 0); // Nhánh 1 đợi start
        end
        begin : wait_rst
          wait(vif.rst_n == 0);  // Nhánh 2 đợi reset
        end
      join_any  // cho chạy cả 2 nhánh đồng thời, nhánh nào xảy ra trước thì kết thúc
      disable fork; // khi 1 trong 2 nhánh hoàn thành, lệnh này sẽ hủy bỏ nhánh còn lại để dọn dẹp bộ nhớ
      // tránh tiến trình chạy ngầm gây lỗi

      if (vif.rst_n == 0) begin
        wait(vif.rst_n == 1);
        continue;
      end

      // Bắt đầu lấy mẫu dữ liệu, đồng thời giám sát reset song song
      frame_aborted = 0;
      fork
        begin : sample_frame
          // Lấy mẫu giữa Start bit
          repeat(bit_period/2) @(vif.monitor_cb);
          if (vif.monitor_cb.tx !== 0) begin
            frame_aborted = 1;
            return;
          end

          // Lấy mẫu 8 bit dữ liệu
          for (int i = 0; i < 8; i++) begin
            repeat(bit_period) @(vif.monitor_cb);
            captured_data[i] = vif.monitor_cb.tx;
          end

          // Kiểm tra Stop bit
          repeat(bit_period) @(vif.monitor_cb);
          if (vif.monitor_cb.tx !== 1) begin
            $display("[%0t ns] [MONITOR] Cảnh báo lỗi stop bit hoặc frame bị gián đoạn!", $time);
            frame_aborted = 1;
            return;
          end
        end

        begin : monitor_reset
          wait(vif.rst_n == 0);
          frame_aborted = 1;
          $display("[%0t ns] [MONITOR] Phát hiện Reset (rst_n = 0) giữa frame -> Hủy bắt gói!", $time);
        end
      join_any
      disable fork;

      // Nếu frame không bị gián đoạn bởi reset, đẩy vào Mailbox cho Scoreboard
      if (!frame_aborted && vif.rst_n == 1) begin
        trans = new();
        trans.tx_data = captured_data;
        mbx.put(trans);
        $display("[%0t ns] [MONITOR] Đã bắt thành công byte: 8'h%0h", $time, captured_data);
      end else begin
        // Nếu frame bị hủy, chờ nhả reset để sẵn sàng cho frame kế tiếp
        wait(vif.rst_n == 1);
      end
    end
  endtask
endclass

//----------------Scoreboard----------------
class uart_tx_scoreboard;
  mailbox gen2scb_mbx;
  mailbox mon2scb_mbx;
  int pass_count;
  int fail_count;
  int reset_aborted_count;

  function new(mailbox gen2scb_mbx, mailbox mon2scb_mbx);
    this.gen2scb_mbx = gen2scb_mbx;
    this.mon2scb_mbx = mon2scb_mbx;
  endfunction

  // task thực thi chính
  task run();
    uart_tx_transaction exp_trans;
    uart_tx_transaction act_trans;
    forever begin
      gen2scb_mbx.get(exp_trans);

      // Nếu transaction này được chỉ định inject reset giữa frame:
      if (exp_trans.inject_reset == 1) begin
        $display("[SCOREBOARD] [RESET ABORTED] Frame Data 8'h%0h bị hủy giữa chừng do Reset đúng như kỳ vọng!", 
                 exp_trans.tx_data);
        reset_aborted_count++;
        continue; // Bỏ qua, không chờ gói từ Monitor vì frame này đã bị hủy
      end

      // Frame bình thường: Chờ gói thực tế từ Monitor để so sánh
      mon2scb_mbx.get(act_trans);
      if (exp_trans.tx_data === act_trans.tx_data) begin
        $display("[SCOREBOARD] [PASS] Datapath OK! Expected: 8'h%0h | Actual: 8'h%0h", 
                 exp_trans.tx_data, act_trans.tx_data);
        pass_count++;
      end else begin
        $error("[SCOREBOARD] [FAIL] MISMATCH DETECTED! Expected: 8'h%0h | Actual: 8'h%0h", 
               exp_trans.tx_data, act_trans.tx_data);
        fail_count++;
      end
    end
  endtask

  // Hàm tổng kết báo cáo khi bài test kết thúc
  function void report();
    $display("\n==================================================");
    $display("                FINAL VERIFICATION REPORT         ");
    $display("==================================================");
    $display(" Total Passed Packets        : %0d", pass_count);
    $display(" Total Aborted (Reset) Cases : %0d", reset_aborted_count);
    $display(" Total Failed Packets        : %0d", fail_count);
    
    if (fail_count == 0 && (pass_count + reset_aborted_count) > 0) begin
      $display(" STATUS: TEST PASSED SUCCESSFULLY! (DUPLICATED 100%% DATA ACCURACY)");
    end else begin
      $display(" STATUS: TEST FAILED! PLEASE CHECK RTL OR TIMING.");
    end
    $display("==================================================\n");
  endfunction
endclass  

//----------------Coverage----------------
class uart_tx_coverage;
  mailbox mbx;
  uart_tx_transaction trans;

  // Khai báo Covergroup đo Functional Coverage
  covergroup tx_cg;
    // Coverpoint 1: Kiểm tra các giá trị dữ liệu truyền 8-bit (Corner case & Range)
    data_cp: coverpoint trans.tx_data {
      bins zero_val    = {8'h00};
      bins all_ones    = {8'hFF};
      bins alt_01      = {8'h55}; // 01010101
      bins alt_10      = {8'hAA}; // 10101010
      bins low_range   = {[8'h01:8'h3F]};
      bins mid_low     = {[8'h40:8'h7F]};
      bins mid_high    = {[8'h80:8'hBF]};
      bins high_range  = {[8'hC0:8'hFE]};
    }

    // Coverpoint 2: Kiểm tra các giá trị chu kỳ delay giữa các frame
    delay_cp: coverpoint trans.delay_cycles {
      bins zero_delay  = {0};          // Truyền liên tục back-to-back
      bins short_delay = {[1:10]};     // Delay ngắn
      bins med_delay   = {[11:30]};    // Delay vừa
      bins long_delay  = {[31:50]};    // Delay dài
    }

    // Coverpoint 3: Kiểm tra sự kiện Reset ngẫu nhiên
    reset_cp: coverpoint trans.inject_reset {
      bins normal_frame = {0};
      bins reset_frame  = {1};
    }

    // Coverpoint 4: Vị trí kích hoạt Reset trong frame
    // 1 frame = 10 bits = 4340 chu kỳ clock
    reset_stage_cp: coverpoint trans.reset_cycle_offset iff (trans.inject_reset == 1) {
      bins start_bit_reset = {[20 : 433]};     // Reset trúng Start bit
      bins data_bit_reset  = {[434 : 3905]};   // Reset trúng Data bits (0-7)
      bins stop_bit_reset  = {[3906 : 4000]};  // Reset trúng Stop bit
    }

    // Cross Coverage: Tương quan giữa Data và Delay, Reset và vị trí ngắt
    data_x_delay: cross data_cp, delay_cp;
    reset_x_stage: cross reset_cp, reset_stage_cp;
  endgroup

  function new(mailbox mbx);
    this.mbx = mbx;
    tx_cg = new();
  endfunction

  task run();
    forever begin
      mbx.get(trans);
      tx_cg.sample();
    end
  endtask

  // Báo cáo độ bao phủ chức năng
  function void report();
    $display("\n==================================================");
    $display("             FUNCTIONAL COVERAGE REPORT           ");
    $display("==================================================");
    $display(" Total Functional Coverage : %0.2f%%", tx_cg.get_coverage());
    $display("   - Data Coverage         : %0.2f%%", tx_cg.data_cp.get_coverage());
    $display("   - Delay Coverage        : %0.2f%%", tx_cg.delay_cp.get_coverage());
    $display("   - Reset Injected Cov    : %0.2f%%", tx_cg.reset_cp.get_coverage());
    $display("   - Reset Stage Cov       : %0.2f%%", tx_cg.reset_stage_cp.get_coverage());
    $display("   - Data x Delay Coverage : %0.2f%%", tx_cg.data_x_delay.get_coverage());
    $display("==================================================\n");
  endfunction
endclass

//---------------Environment---------------
class uart_tx_evn;
  uart_tx_generator  gen;
  uart_tx_driver     drv;
  uart_tx_monitor    mon;
  uart_tx_scoreboard scb;
  uart_tx_coverage   cov;

  // khai báo các mailbox trung gian
  mailbox gen2drv_mbx;
  mailbox gen2scb_mbx;
  mailbox gen2cov_mbx;
  mailbox mon2scb_mbx;

  virtual uart_tx_if vif;

  function new(virtual uart_tx_if vif);
    this.vif = vif;
    // cấp vùng nhớ cho các hòm thư
    gen2drv_mbx = new();
    gen2scb_mbx = new();
    gen2cov_mbx = new();
    mon2scb_mbx = new();

    gen = new(gen2drv_mbx, gen2scb_mbx, gen2cov_mbx);
    drv = new(gen2drv_mbx, vif);
    mon = new(mon2scb_mbx, vif);
    scb = new(gen2scb_mbx, mon2scb_mbx);
    cov = new(gen2cov_mbx);
  endfunction

  task pre_run();
    $display("EVN đang khởi tạo môi trường mô phỏng...");
  endtask

  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
      cov.run();
    join_none
  endtask

  task post_run();
    @(gen.gen_done); // chờ generator sinh xong dữ liệu
    wait((scb.pass_count + scb.fail_count + scb.reset_aborted_count) == gen.num_transaction); // chờ scoreboard xử lý đủ số gói
    repeat(500) @(vif.driver_cb);
    scb.report();
    cov.report();
  endtask

  task run(); // task run chính 
    pre_run();
    test();
    post_run();
  endtask
endclass
