`timescale 1ns/1ps

module tb_spi;
    localparam B          = 16;
    localparam PRESCALLER = 31;
    localparam N_SLAVES   = 8;

    // Такты
    logic master_clk, slave_1_clk, slave_2_clk;
    logic reset;

    // Интерфейс мастера
    logic [$clog2(N_SLAVES)-1:0] slave_id;
    logic [B-1:0] master_put;
    logic [B-1:0] master_get;
    logic         start;
    logic         master_idle;

    // Интерфейс слейвов
    logic [B-1:0] slave_1_put, slave_1_get;
    logic [B-1:0] slave_2_put, slave_2_get;
    logic         slave_1_exchange_done, slave_2_exchange_done;

    // Линии SPI
    wire miso;
    wire mosi;                        //
    wire [$clog2(N_SLAVES)-1:0] cs;   // линией  управляет мастер
    wire sck_b;                       // 

    // --- Мастер ---
    SPI #(
        .B(B), .PRESCALLER(PRESCALLER), .N_SLAVES(N_SLAVES),
        .T_LEAD(16), .T_TRAIL(16)
    ) master (
        .clk        (master_clk),
        .reset      (reset),
        .slave_id   (slave_id),
        .master_put (master_put),
        .start      (start),
        .idle       (master_idle),
        .master_get (master_get),
        .miso_inp   (miso),
        .mosi       (mosi),
        .cs_out     (cs),
        .sck_b      (sck_b)
    );

    // --- Слейв 1 ---
    slave #(.B(B), .N_SLAVES(N_SLAVES), .SLAVE_ID(1)) slave_1 (
        .clk           (slave_1_clk),
        .reset         (reset),
        .slave_put     (slave_1_put),
        .exchange_done (slave_1_exchange_done),
        .slave_get     (slave_1_get),
        .sck_b_inp     (sck_b),
        .mosi_inp      (mosi),
        .cs_inp        (cs),
        .miso          (miso)
    );

    // --- Слейв 2 ---
    slave #(.B(B), .N_SLAVES(N_SLAVES), .SLAVE_ID(2)) slave_2 (
        .clk           (slave_2_clk),
        .reset         (reset),
        .slave_put     (slave_2_put),
        .exchange_done (slave_2_exchange_done),
        .slave_get     (slave_2_get),
        .sck_b_inp     (sck_b),
        .mosi_inp      (mosi),
        .cs_inp        (cs),
        .miso          (miso)
    );

    /* Такты (согласно стандарту у разных устройств на линии может отличаться частота кварца
	 это учитывается  задержками tT и tL а также частотой sck_b) */
    initial master_clk  = 0; always #5 master_clk  = ~master_clk;   // 100 МГц
    initial slave_1_clk = 0; always #7 slave_1_clk = ~slave_1_clk;  // 71 МГц
    initial slave_2_clk = 0; always #6 slave_2_clk = ~slave_2_clk;  // 83 МГц

    // Задача: подать start на 1 такт
    task automatic pulse_start();
        start = 1;
        @(posedge master_clk);
        start = 0;
    endtask

    // Задача: дождаться возврата мастера в IDLE и дать master_get защёлкнуться
    task automatic wait_idle();
        @(posedge master_idle);          // ждём фронта idle
        repeat(4) @(posedge master_clk); // как-то так и должна действовать внешняя логика
    endtask

    initial begin
        $dumpfile("tb_spi.vcd");
        $dumpvars(0, tb_spi);

        // Начальные значения
        reset       = 1;
        start       = 0;
        slave_id    = 0;
        master_put  = 16'h0000;
        slave_1_put = 16'h1111;
        slave_2_put = 16'h2222;

        repeat(20) @(posedge master_clk);
        reset = 0;
        repeat(20) @(posedge master_clk);

        // === Пакет 1: слейв 1 ===
        slave_id   = 1;
        master_put = 16'hAAAA;
        pulse_start();
        wait_idle();
        $display("[%0t] Pkg 1: m_get=%h s1_get=%h s2_get=%h (expect 1111/AAAA/0000)",
                 $time, master_get, slave_1_get, slave_2_get);
        if (master_get !== 16'h1111) $error("FAIL m_get, got %h", master_get);
        if (slave_1_get !== 16'hAAAA) $error("FAIL s1_get, got %h", slave_1_get);
        if (slave_2_get !== 16'h0000) $error("FAIL s2_get, got %h", slave_2_get);

        // === Пакет 2: слейв 2 ===
        slave_id   = 2;
        master_put = 16'hAAAA;
        pulse_start();
        wait_idle();
        $display("[%0t] Pkg 2: m_get=%h s1_get=%h s2_get=%h (expect 2222/AAAA/AAAA)",
                 $time, master_get, slave_1_get, slave_2_get);
        if (master_get !== 16'h2222) $error("FAIL m_get, got %h", master_get);
        if (slave_2_get !== 16'hAAAA) $error("FAIL s2_get, got %h", slave_2_get);

        // === Пакет 3: слейв 1, новые данные ===
        slave_id    = 1;
        master_put  = 16'hABCD;
        slave_1_put = 16'h1234;
        pulse_start();
        wait_idle();
        $display("[%0t] Pkg 3: m_get=%h s1_get=%h s2_get=%h (expect 1234/ABCD/AAAA)",
                 $time, master_get, slave_1_get, slave_2_get);
        if (master_get !== 16'h1234) $error("FAIL m_get, got %h", master_get);
        if (slave_1_get !== 16'hABCD) $error("FAIL s1_get, got %h", slave_1_get);

        // === Пакет 4: слейв 2, новые данные ===
        slave_id    = 2;
        master_put  = 16'hABCD;
        slave_2_put = 16'h5678;
        pulse_start();
        wait_idle();
        $display("[%0t] Pkg 4: m_get=%h s1_get=%h s2_get=%h (expect 5678/ABCD/ABCD)",
                 $time, master_get, slave_1_get, slave_2_get);
        if (master_get !== 16'h5678) $error("FAIL m_get, got %h", master_get);
        if (slave_2_get !== 16'hABCD) $error("FAIL s2_get, got %h", slave_2_get);

        $display("=== Simulation finished OK ===");
        $finish;
    end

    initial begin
        #1_000_000;
        $error("TIMEOUT");
        $finish;
    end
endmodule