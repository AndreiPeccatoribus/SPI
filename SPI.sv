/* ---МАСТЕР---
эта реализация не так уж далека от стандарта OpenTitan*/
module SPI #(
	parameter B          = 16, // ширина слова
	parameter PRESCALLER = 31, // делитель частоты передачи
	parameter N_SLAVES   = 8,  // число слейвов
	parameter T_LEAD     = 8,  // пауза между выбором слейва и первым фронтом sck_b
	parameter T_TRAIL    = 8   // пауза между последним спадом sck_b и снятием выбора слейва
)(
	/* технические вводы и выводы мастера для внешней логики */
	input logic           clk,
	input logic           reset,
	
	input logic [$clog2(N_SLAVES)-1:0] slave_id, // кому: номер слейва, от логики
	input logic [B-1:0] master_put,              // что: B-битное число 
	input logic start,                           // (команда) передать
	output logic idle,                           // сигнал для внешней логики, что мастер простаивает (передача выполнена), и можно подавать команду
	output logic [B-1:0] master_get,             // поле, откуда можно забирать ответ слейва

	
	/* стандартные вводы SPI мастера */
	input logic miso_inp,
	
	/* стандартные выводы SPI мастера */
	output logic mosi,
	output logic [$clog2(N_SLAVES)-1:0] cs_out,
	output logic sck_b                           // clk редуцированный в PRESCALLER+1 раз
	);
	
	
	// ---Синхронизаторы для всех входов извне устройства---
	// Задержка чтения MISO мастером на 2 такта clk мастера
	(* ASYNC_REG = "TRUE" *) logic miso_d1, miso_d2;
	logic miso;
	always_ff @(posedge clk or posedge reset) begin
		 if (reset) begin
			  miso_d1 <= 1'b0; miso_d2 <= 1'b0;
		 end
		 else begin
			  miso_d1 <= miso_inp; 
			  miso_d2 <= miso_d1;  // 2 триггера на miso
		 end
	end
	assign miso = miso_d2;       // спустя 2 такта clk мастера мы получаем правильное значение MISO
	
	
	// ---Детекция фронта start (команды на начало передачи)---
	logic start_last;
	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			start_last <= 1'b0;
		end
		else begin
			start_last <= start;              // неблокирующее присваивание даёт результат на следующем такте
		end
	end
	wire start_pulse = start & ~start_last; // здесь нам нужен не регистр, а провод, сигнал которого держится 1 такт и выставляется сразу
	
	
	/* ---Конечный автомат Мастера (FSM)---
	Принято использовать логику конечного автомата в SPI, так как это более строгий
	способ управлять передачей данных, позволяющий разделить работу с железом на изолированные
	логические блоки и управлять задержками между ними */
	
	// классический способ задать состояния через enum специальный тип
	typedef enum logic [1:0] {
		IDLE,    // ждём start_pulse, sck_b = 0, cs = 0
		DELAY,   // cs выставлен, выжидаем паузу равную tL перед первым sck_b
		ACTIVE,  // генерим 16 фронтов sck_b
		TRAIL    // sck_b = 0, выжидаем паузу равную tT перед снятием cs
	} state_t;
	state_t state;
	
	// ---Счётчики---
	logic [$clog2(PRESCALLER+1)-1:0] cnt_b;   // счётчик задающий частоту sck_b
	logic [$clog2(B)-1:0]         cnt_p;      // счётчик битов в пакете
	logic [$clog2(T_LEAD+1)-1:0]  cnt_lead;   // счётчик паузы tL
	logic [$clog2(T_TRAIL+1)-1:0] cnt_trail;  // счётчик паузы tT
	logic last_bit;   // флаг 1 после 16-го сэмплирования
	
	// ---Регистры чтения и записи---
	logic [B-1:0] tx; // сюда данные загружаются с master_put и выходят на MOSI
	logic [B-1:0] rx; // сюда данные приходят с MISO и потом уходят master_get
	
	assign mosi   = tx[B-1];
	assign idle   = (state == IDLE);
	assign cs_out = (state == IDLE) ? '0 : slave_id; // если ждём, то не выбираем слейва, а если работаем, то берём из задания
	
	// ---Основной FSM---
	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			state         <= IDLE;
			cnt_b         <= '0;
			cnt_p         <= '0;
			cnt_lead      <= '0;
			cnt_trail     <= '0;
			last_bit      <= 1'b0;
			tx            <= '0;
			rx            <= '0;
			sck_b         <= 1'b0;
			master_get    <= '0;
		end
		else begin
			case (state)
				IDLE: begin                  // ОЖИДАНИЕ, счётчики обнулены, низкое состояние sck_b
					cnt_b     <= '0;
					cnt_p     <= '0;
					cnt_lead  <= '0;
					cnt_trail <= '0;
					last_bit  <= 1'b0;
					sck_b     <= 1'b0;
					rx        <= '0;
					
					if (start_pulse) begin
						tx <= master_put;    // если ОЖИДАНИЕ и пришёл сигнал начала, то читаем из ввода, что передаём
						state <= DELAY;      // и меняем состояние
					end
				end
				
				DELAY: begin                 /* ЗАДЕРЖКА cs уже выставлен (выше), sck_b стоит ждём tL тактов
				это нужно, чтобы у слейва прошла стадия принятия, ну то есть он бы понял, что с ним сейчас будут общаться и забрал данные из slave_put */
					sck_b <= 1'b0;
					if (cnt_lead == T_LEAD - 1) begin
						cnt_lead <= '0;
						state <= ACTIVE;     // когда досчитали, то начинаем передачу
					end
					else begin
						cnt_lead <= cnt_lead + 1'b1;
					end
				end
				
				ACTIVE: begin                // АКТИВНОСТЬ в этом состоянии мы просто тактируем передачу и осуществляем сдвиг
					if (cnt_b == PRESCALLER) begin
						cnt_b <= '0;
					end
					else begin
						cnt_b <= cnt_b + 1'b1;
					end
					
					// генерация sck_b: 0 в первой половине периода, где период это (PRESCALLER+1)/ν_clk, 1 во второй
					if (cnt_b == ((PRESCALLER + 1) / 2) - 1) begin
						sck_b <= 1'b1;       // передний фронт (для считывания он установится ровно посередине PRESCALLER + 1 по clk мастера)
					end
					else if (cnt_b == PRESCALLER) begin
						sck_b <= 1'b0;       // задний фронт (для считывания он установится как раз на PRESCALLER + 1 такте clk мастера)
					end
					
					// обработка передниго фронта: считываем MISO
					if (cnt_b == ((PRESCALLER + 1) / 2) - 1) begin
						rx <= {rx[B-2:0], miso}; // склейка сдвинутго rx с новым битом от miso
						if (cnt_p == B-1) begin 
							last_bit <= 1'b1;    // на всякий случай, это я так флаг окончания пакета назвал
						end
						else begin
							cnt_p <= cnt_p + 1'b1; 
						end
					end
					
					// обработка заднего фронта: сдвигаем TX и выставляем новый бит на MOSI
					if (cnt_b == PRESCALLER) begin
						if (last_bit) begin
							state    <= TRAIL;
							last_bit <= 1'b0;
							cnt_p    <= '0;
						end
						else begin
							tx <= {tx[B-2:0], 1'b0};
						end
					end
				end
				
				TRAIL: begin // выставляем sck_b в 0, cs ещё выставлен. Ждём tT тактов clk.
					sck_b <= 1'b0;
					if (cnt_trail == T_TRAIL - 1) begin
						cnt_trail     <= '0;
						master_get    <= rx;      // выгрузка принятого
						state         <= IDLE;
					end
					else begin
						cnt_trail <= cnt_trail + 1'b1;
					end
				end
			endcase
		end
	end
	
endmodule