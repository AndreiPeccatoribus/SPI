//---СЛЕЙВ---
module slave #(parameter B = 16, N_SLAVES = 8, SLAVE_ID = 5)(
	// служебные вводы и выводы
   input  logic           clk,
	input  logic           reset,
	input  logic [B-1:0] slave_put,
	output logic [B-1:0] slave_get,
	output logic exchange_done,

	// стандартные вводы слейва в SPI
	input logic sck_b_inp,
	input logic mosi_inp,
	input logic [$clog2(N_SLAVES)-1:0] cs_inp,
	
	// стандартные выводы слейва
	output logic miso
);
	// Синхронизаторы для всех входов извне
	(* ASYNC_REG = "TRUE" *) logic sck_d1, sck_d2;
	(* ASYNC_REG = "TRUE" *) logic mosi_d1, mosi_d2;
	(* ASYNC_REG = "TRUE" *) logic cs_d1, cs_d2;
	
	logic sck_b;
	logic mosi;
	logic [$clog2(N_SLAVES)-1:0] cs;

	always_ff @(posedge clk or posedge reset) begin
		 if (reset) begin
			  sck_d1 <= 1'b0;  sck_d2 <= 1'b0;
			  mosi_d1 <= 1'b0; mosi_d2 <= 1'b0;
			  cs_d1 <= 1'b0;   cs_d2 <= 1'b0;
		 end
		 else begin
			  sck_d1 <= sck_b_inp; sck_d2 <= sck_d1;    // 2 триггера на SCK
			  mosi_d1 <= mosi_inp; mosi_d2 <= mosi_d1;  // 2 триггера на MOSI
			  cs_d1 <= cs_inp;     cs_d2 <= cs_d1;      // 2 триггера на CS
		 end
	end
	
	assign sck_b = sck_d2;
	assign mosi = mosi_d2;
	assign cs = cs_d2;
	
	// ---Тактирование---
	// сам sck_b определяется в мастере
	logic sck_b_last; // значение sck_b на прошлом такте (для определения фронта)
	logic sck_b_rising; // флаг фронта sck_b
	logic sck_b_falling; // флаг спада sck_b
			
	// Детекция фронта и спада
	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			sck_b_last <= '0;
		end
		else begin
			sck_b_last <= sck_b; // неблокирующее присваивание даёт результат на следующем такте
		end
	end
	
	assign sck_b_rising  = sck_b  & ~sck_b_last;
	assign sck_b_falling = ~sck_b & sck_b_last;
	
	// Флаг передачи пакетов
	logic [$clog2(B)-1:0] cnt_p; // отсчёт 16-ти тактов sck_b (передача пакета)
	
	always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
			cnt_p <= '0;
			exchange_done <= 1'b0;
		end
		else if (sck_b_rising) begin
				if (cnt_p == B-1) begin
					cnt_p <= '0;
					exchange_done <= 1'b1;
				end
				else begin
					cnt_p <= cnt_p + 1'b1;
				end
		end
		else begin
			exchange_done <= 1'b0;
		end
	end
	
		// ---Протокол передачи данных----
	
	logic [B-1:0] d; // триггеры (шина длиной 16 шириной 16)

	assign miso = d[B-1];
	always_ff @(posedge clk, posedge reset) begin
		if (reset) d <= '0;
		else if (sck_b_rising) begin
			d <= {d[B-2:0], mosi};
		end
		else if (exchange_done) d <= slave_put;
	end

	// ---Параллельное чтение и запись---
	
	// регистры чтения
	always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
			slave_get <= '0;
		end
		else if (exchange_done) begin
			slave_get <= d;
		end
	end

endmodule
