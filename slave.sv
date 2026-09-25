//---СЛЕЙВ---
module slave #(
	parameter B = 16,                                    // ширина слова
	parameter N_SLAVES  = 8,                             // число слейвов
	parameter logic [$clog2(N_SLAVES)-1:0] SLAVE_ID = 5  // собственный шдентификатор
)(
	/* технические вводы и выводы мастера для внешней логики */
	input logic clk,
	input logic reset,
	
	input logic [B-1:0] slave_put,              // что передать мастеру: B-битное число 
	output logic exchange_done,                 // обмен был совершён, флаг для внешней локиги
	output logic [B-1:0] slave_get,             // поле, откуда можно забирать посылку мастера

	/* стандартные вводы слейва в SPI */
	input logic sck_b_inp, 
	input logic mosi_inp,
	input logic [$clog2(N_SLAVES)-1:0] cs_inp,
	
	/* стандартные выводы слейва */
	output logic miso
);
	// ---Синхронизаторы для всех входов извне устройства---
	// Задержка чтения sck, mosi и cs слейвом на 2 такта clk слейва
	(* ASYNC_REG = "TRUE" *) logic sck_d1, sck_d2;
	(* ASYNC_REG = "TRUE" *) logic mosi_d1, mosi_d2;
	(* ASYNC_REG = "TRUE" *) logic [$clog2(N_SLAVES)-1:0] cs_d1, cs_d2;
	
	logic sck_b;
	logic mosi;
	logic [$clog2(N_SLAVES)-1:0] cs;

	always_ff @(posedge clk or posedge reset) begin
		 if (reset) begin
			  sck_d1 <= 1'b0; sck_d2 <= 1'b0;
			  mosi_d1 <= 1'b0; mosi_d2 <= 1'b0;
			  cs_d1 <= '0; cs_d2 <= '0;
		 end
		 else begin
			  sck_d1 <= sck_b_inp; sck_d2 <= sck_d1;    // 2 триггера на SCK
			  mosi_d1 <= mosi_inp; mosi_d2 <= mosi_d1;  // 2 триггера на MOSI
			  cs_d1 <= cs_inp; cs_d2 <= cs_d1;          // 2 триггера на CS
		 end
	end
	
	assign sck_b = sck_d2;
	assign mosi = mosi_d2;
	assign cs = cs_d2;
	
	// ---Селекция---
	logic active;
	assign active = (cs == SLAVE_ID);
	
	logic active_last;
	logic exchange_start;

	always_ff @(posedge clk or posedge reset) begin
		 if (reset) begin
			  active_last <= 1'b0;
			  exchange_start <= 1'b0;
		 end
		 else begin
			  active_last <= active;
			  exchange_start <= active & ~active_last;
		 end
	end
	
	// ---Тактирование---
	// сам sck_b определяется в мастере
	logic sck_b_last;    // значение sck_b на прошлом такте (для определения фронта)
	logic sck_b_rising;  // флаг фронта sck_b
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
	
	assign sck_b_rising  = active & (sck_b  & ~sck_b_last);
	assign sck_b_falling = active & (~sck_b & sck_b_last);
	
	// Флаг передачи пакетов
	logic [$clog2(B)-1:0] cnt_p; // отсчёт 16-ти тактов sck_b (передача пакета)
	
	always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
			cnt_p <= '0;
			exchange_done <= 1'b0;
		end
		else if (~active) begin
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
	
	// ---Протокол передачи данных---
	
	logic [B-1:0] tx;
	logic [B-1:0] rx;
	assign miso = active ? tx[B-1] : 1'bz; // выставляемпромежуточное состояние еслипередачаневедётся
	always_ff @(posedge clk, posedge reset) begin
		 if (reset) begin
			  tx <= '0;
			  rx <= '0;
		 end
		 else if (~active) begin
			  tx <= '0;
			  rx <= '0;
		 end
		 else if (exchange_start) begin
			  tx <= slave_put;              // загрузка в НАЧАЛЕ пакета (задержка на загрузку)
		 end
		 else if (sck_b_falling) begin
			  tx <= {tx[B-2:0], 1'b0};      // выставляем — на спаде
		 end
		 else if (sck_b_rising) begin
			  rx <= {rx[B-2:0], mosi};      // сэмплируем — на фронте
		 end
	end

	// ---Параллельное чтение---
	
	// регистры чтения
	always_ff @(posedge clk, posedge reset) begin
		if (reset) begin
			slave_get <= '0;
		end
		else if (exchange_done) begin
			slave_get <= rx;
		end
	end

endmodule
