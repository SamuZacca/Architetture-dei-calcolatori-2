`timescale 1ns/1ps
// tb_smart_gate.v

module tb_smart_gate;

  // Clock/Reset
  reg clk_i;
  reg reset_ni;

  // Inputs
  reg car_i;
  reg pay_ok_i;
  reg clear_i;
  reg cnt_reset_i;

  // Outputs
  wire gate_open_o;
  wire gate_close_o;
  wire red_o;
  wire yellow_o;
  wire green_o;
  wire [7:0] car_count_o;

  // Test variables - moved to module level
  integer expected_count;
  integer i;
  integer lights;

  // DUT
  smart_gate_controller dut (
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .car_i(car_i),
    .pay_ok_i(pay_ok_i),
    .clear_i(clear_i),
    .cnt_reset_i(cnt_reset_i),
    .gate_open_o(gate_open_o),
    .gate_close_o(gate_close_o),
    .red_o(red_o),
    .yellow_o(yellow_o),
    .green_o(green_o),
    .car_count_o(car_count_o)
  );

  // Clock: 10ns period
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  // Generate waveform file
  initial begin
    $dumpfile("smart_gate.vcd");
    $dumpvars(0, tb_smart_gate);
  end

  // ----------------------
  // Helpers (Verilog tasks)
  // ----------------------
  task drive_request_one_cycle;
    begin
      @(negedge clk_i);
      car_i    = 1'b1;
      pay_ok_i = 1'b1;
      @(negedge clk_i);
      car_i    = 1'b0;
      pay_ok_i = 1'b0;
    end
  endtask

  task expect_lights;
    input r;
    input y;
    input g;
    input [8*32-1:0] tag; // fixed-size ASCII tag (Verilog-2001 trick)
    begin
      @(posedge clk_i);
      if (red_o !== r || yellow_o !== y || green_o !== g) begin
        $display("ERRORE luci (%0s): atteso R=%0d Y=%0d G=%0d ottenuto R=%0d Y=%0d G=%0d t=%0t",
                 tag, r,y,g, red_o,yellow_o,green_o, $time);
        $fatal;
      end
    end
  endtask

  task expect_motor_now;
    input open_pulse;
    input close_pulse;
    input [8*32-1:0] tag;
    begin
      if (gate_open_o !== open_pulse || gate_close_o !== close_pulse) begin
        $display("ERRORE motore (%0s): atteso open=%0d close=%0d ottenuto open=%0d close=%0d t=%0t",
                 tag, open_pulse, close_pulse, gate_open_o, gate_close_o, $time);
        $fatal;
      end
    end
  endtask

  // Invariants checked every cycle after reset release:
  // - exactly one light on
  // - motor commands mutually exclusive
  // - no open when clear_i is 0
  always @(posedge clk_i) begin
    if (reset_ni) begin
      lights = (red_o ? 1 : 0) + (yellow_o ? 1 : 0) + (green_o ? 1 : 0);
      if (lights != 1) begin
        $display("ERRORE invariante: luci non one-hot a t=%0t (R=%0d Y=%0d G=%0d)",
                 $time, red_o, yellow_o, green_o);
        $fatal;
      end
      if (gate_open_o && gate_close_o) begin
        $display("ERRORE invariante: open e close entrambi alti a t=%0t", $time);
        $fatal;
      end
      if (gate_open_o && !clear_i) begin
        $display("ERRORE invariante: gate_open_o alto mentre clear_i=0 a t=%0t", $time);
        $fatal;
      end
    end
  end

  // ----------------------
  // Main test sequence
  // ----------------------
  initial begin
    // init
    car_i = 0; pay_ok_i = 0; clear_i = 1; cnt_reset_i = 0;
    reset_ni = 0;

    // reset sequence
    repeat (3) @(posedge clk_i);
    reset_ni = 0;
    repeat (2) @(posedge clk_i);
    reset_ni = 1;

    // After reset -> IDLE (red), motors 0, count 0
    expect_lights(1,0,0, "after reset");
    expect_motor_now(0,0, "after reset");
    if (car_count_o !== 8'd0) begin
      $display("ERRORE conteggio dopo reset: ottenuto %0d", car_count_o);
      $fatal;
    end

    // ------------------------------------------------------------
    // TEST 1: basic sequence with clear_i = 1
    // ------------------------------------------------------------
    expected_count = 0;

    drive_request_one_cycle;

    // YELLOW_PRE for 2 cycles
    expect_lights(0,1,0, "T1 YELLOW_PRE 0"); expect_motor_now(0,0, "T1 YELLOW_PRE 0");
    expect_lights(0,1,0, "T1 YELLOW_PRE 1"); expect_motor_now(0,0, "T1 YELLOW_PRE 1");

    // WAIT_CLEAR (clear_i=1)
    expect_lights(0,1,0, "T1 WAIT_CLEAR");   expect_motor_now(0,0, "T1 WAIT_CLEAR");

    // OPEN (1 cycle): green + gate_open_o
    expect_lights(0,0,1, "T1 OPEN");   expect_motor_now(1,0, "T1 OPEN");
    expected_count = expected_count + 1;

    // GREEN 3 cycles
    expect_lights(0,0,1, "T1 GREEN 0");   expect_motor_now(0,0, "T1 GREEN 0");
    expect_lights(0,0,1, "T1 GREEN 1");   expect_motor_now(0,0, "T1 GREEN 1");
    expect_lights(0,0,1, "T1 GREEN 2");   expect_motor_now(0,0, "T1 GREEN 2");

    // YELLOW 1 cycle
    expect_lights(0,1,0, "T1 YELLOW");  expect_motor_now(0,0, "T1 YELLOW");

    // CLOSE 1 cycle
    expect_lights(1,0,0, "T1 CLOSE");  expect_motor_now(0,1, "T1 CLOSE");

    // Back to IDLE next cycle
    expect_lights(1,0,0, "T1 IDLE");   expect_motor_now(0,0, "T1 IDLE");

    if (car_count_o !== expected_count[7:0]) begin
      $display("ERRORE conteggio dopo T1: atteso %0d ottenuto %0d", expected_count, car_count_o);
      $fatal;
    end
    $display("TEST 1 SUPERATO");

    // ------------------------------------------------------------
    // TEST 2: clear_i holds low in WAIT_CLEAR; must not open until clear_i=1
    // ------------------------------------------------------------
    clear_i = 1'b1;
    drive_request_one_cycle;

    // YELLOW_PRE 2 cycles
    expect_lights(0,1,0, "T2 YELLOW_PRE 0"); expect_motor_now(0,0, "T2 YELLOW_PRE 0");
    expect_lights(0,1,0, "T2 YELLOW_PRE 1"); expect_motor_now(0,0, "T2 YELLOW_PRE 1");

    // Enter WAIT_CLEAR then force clear_i low for several cycles
    clear_i = 1'b0;
    expect_lights(0,1,0, "T2 WAIT_CLEAR 0"); expect_motor_now(0,0, "T2 WAIT_CLEAR 0");

    repeat (4) begin
      @(posedge clk_i);
      if (yellow_o !== 1'b1 || gate_open_o !== 1'b0) begin
        $display("ERRORE T2 hold: atteso giallo e non aperto mentre clear_i=0 a t=%0t", $time);
        $fatal;
      end
    end

    // Release clear_i
    @(negedge clk_i);
    clear_i = 1'b1;

    // still WAIT_CLEAR (yellow) on next posedge, then OPEN
    expect_lights(0,1,0, "T2 WAIT_CLEAR rel"); expect_motor_now(0,0, "T2 WAIT_CLEAR rel");
    expect_lights(0,0,1, "T2 OPEN");     expect_motor_now(1,0, "T2 OPEN");
    expected_count = expected_count + 1;

    // Finish sequence
    expect_lights(0,0,1, "T2 GREEN 0"); expect_motor_now(0,0, "T2 GREEN 0");
    expect_lights(0,0,1, "T2 GREEN 1"); expect_motor_now(0,0, "T2 GREEN 1");
    expect_lights(0,0,1, "T2 GREEN 2"); expect_motor_now(0,0, "T2 GREEN 2");
    expect_lights(0,1,0, "T2 YELLOW"); expect_motor_now(0,0, "T2 YELLOW");
    expect_lights(1,0,0, "T2 CLOSE"); expect_motor_now(0,1, "T2 CLOSE");
    expect_lights(1,0,0, "T2 IDLE");  expect_motor_now(0,0, "T2 IDLE");

    if (car_count_o !== expected_count[7:0]) begin
      $display("ERRORE conteggio dopo T2: atteso %0d ottenuto %0d", expected_count, car_count_o);
      $fatal;
    end
    $display("TEST 2 SUPERATO");

    // ------------------------------------------------------------
    // TEST 3: Counter Tests (Reset & Saturation)
    // ------------------------------------------------------------
    
    // Part A: Counter Reset during operation
    drive_request_one_cycle;

    // up to OPEN
    expect_lights(0,1,0, "T3A YELLOW_PRE 0"); expect_motor_now(0,0, "T3A YELLOW_PRE 0");
    expect_lights(0,1,0, "T3A YELLOW_PRE 1"); expect_motor_now(0,0, "T3A YELLOW_PRE 1");
    expect_lights(0,1,0, "T3A WAIT_CLEAR");   expect_motor_now(0,0, "T3A WAIT_CLEAR");
    expect_lights(0,0,1, "T3A OPEN");   expect_motor_now(1,0, "T3A OPEN");
    // Counter incremented here

    // GREEN 0
    expect_lights(0,0,1, "T3A GREEN 0");   expect_motor_now(0,0, "T3A GREEN 0");

    // Assert cnt_reset_i for 1 cycle during GREEN 1
    @(negedge clk_i);
    cnt_reset_i = 1'b1;
    @(posedge clk_i);
    if (green_o !== 1'b1 || gate_open_o !== 1'b0 || gate_close_o !== 1'b0) begin
      $display("ERRORE T3A: FSM disturbata da cnt_reset_i a t=%0t", $time);
      $fatal;
    end
    @(negedge clk_i);
    if (car_count_o !== 8'd0) begin
      $display("ERRORE T3A: contatore non resettato a 0, ottenuto %0d", car_count_o);
      $fatal;
    end
    cnt_reset_i = 1'b0;

    // remaining cycles and finish
    expect_lights(0,0,1, "T3A GREEN 2");   expect_motor_now(0,0, "T3A GREEN 2");
    expect_lights(0,1,0, "T3A YELLOW");  expect_motor_now(0,0, "T3A YELLOW");
    expect_lights(1,0,0, "T3A CLOSE");  expect_motor_now(0,1, "T3A CLOSE");
    expect_lights(1,0,0, "T3A IDLE");   expect_motor_now(0,0, "T3A IDLE");


    // Part B: Saturation to 255
    clear_i = 1'b1;
    // We loop enough times to overflow 8 bits if it wasn't saturating
    for (i = 0; i < 260; i = i + 1) begin
      drive_request_one_cycle;

      // Check key states just to be safe, but use abbreviated checks
      expect_lights(0,1,0, "T3B YELLOW_PRE"); expect_motor_now(0,0, "T3B YELLOW_PRE"); // cycle 1
      @(posedge clk_i); // cycle 2
      expect_lights(0,1,0, "T3B WAIT_CLEAR");  expect_motor_now(0,0, "T3B WAIT_CLEAR");
      expect_lights(0,0,1, "T3B OPEN");  expect_motor_now(1,0, "T3B OPEN");
      expect_lights(0,0,1, "T3B GREEN");    expect_motor_now(0,0, "T3B GREEN");  // cycle 1
      repeat(2) @(posedge clk_i); // GREEN 2,3
      expect_lights(0,1,0, "T3B YELLOW"); expect_motor_now(0,0, "T3B YELLOW");
      expect_lights(1,0,0, "T3B CLOSE"); expect_motor_now(0,1, "T3B CLOSE");
      expect_lights(1,0,0, "T3B IDLE");  expect_motor_now(0,0, "T3B IDLE");
    end

    if (car_count_o !== 8'hFF) begin
      $display("ERRORE T3B (saturazione): atteso 255 ottenuto %0d", car_count_o);
      $fatal;
    end
    $display("TEST 3 SUPERATO");

    $display("TUTTI I TEST SUPERATI ✅  car_count_o=%0d", car_count_o);
    $finish;
  end

endmodule
