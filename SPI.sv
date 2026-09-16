// ---МАСТЕР---
module SPI #(parameter B = 16, PRESCALLER = 31, N_SLAVES = 8)(
	input  logic           clk,
	input  logic           reset,
	input  logic [B-1:0] master_put,
	output logic [B-1:0] master_get,
	output logic exchange_done, // сигнал для внешней логики, что пакет передан и можно читать и записывать
	
	// стандартные вводы SPI мастера
	input logic miso_inp,
	
	// стандартные выводы SPI мастера
	output logic mosi,
	output logic [$clog2(N_SLAVES)-1:0] cs,
	output logic sck_b // clk редуцированный в PRESCALLER+1 раз
	);
	
	// Синхронизаторы для всех входов извне
	(* ASYNC_REG = "TRUE" *) logic miso_d1, miso_d2;

	logic miso;
	
	always_ff @(posedge clk or posedge reset) begin
		 if (reset) begin
			  miso_d1 <= 1'b0; miso_d2 <= 1'b0;
		 end
		 else begin
			  miso_d1 <= miso_inp; miso_d2 <= miso_d1;  // 2 триггера на miso
		 end
	end
	
	assign miso = miso_d2;
	
	// ---Тактирование---
	logic sck_b_last; // значение sck_b на прошлом такте (для определения фронта)
	logic sck_b_rising; // флаг фронта sck_b
	logic sck_b_falling; // флаг спада sck_b
	logic [$clog2(PRESCALLER+1)-1:0] cnt_b; // делитель частоты передачи бит
			
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
	
	// Счётчик тактов передачи битов. Реализация частоты sck_b
	always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
			cnt_b <= '0;
			sck_b <= '0;
		end
		else if (cnt_b == PRESCALLER) begin
			cnt_b <= '0;
			sck_b <= ~sck_b;
		end
		else begin
			cnt_b <= cnt_b + 1'b1;
		end
	end
	
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

	assign mosi = d[B-1];
	always_ff @(posedge clk, posedge reset) begin
		if (reset) d <= '0;
		else if (sck_b_rising) begin
			d <= {d[B-2:0], miso};
		end
		else if (exchange_done) d <= master_put;
	end

	// ---Параллельное чтение и запись---
	
	// регистры чтения
	always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
			master_get <= '0;
		end
		else if (exchange_done) begin
			master_get <= d;
		end
	end
	
endmodule
	

