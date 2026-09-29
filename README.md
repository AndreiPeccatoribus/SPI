# SPI Interface Implementation

## Overview
This project implements an SPI master/slave interface based on a looped shift register architecture. It supports full-duplex communication, multiple slave selection (with different quartz frequencies), and synchronization for reliable data exchange.  
At first I made a very simple but unreliable scheme, but later managed to get closer to OpenTitan features.

## Features
- 16-bit shift register (parameter `B`, default 16; 16 bits is sufficient to represent fixed-point numbers with adequate precision for this application.)
- Master and slave modes
- Multiple slave select lines implemented via numeric `slave_id` (not individual CS wires)
- Built-in synchronizers (2‑FF) for clock domain crossing
- Configurable clock prescaler (`PRESCALLER`, default 31)
- Configurable lead and trail delays (`T_LEAD`, `T_TRAIL`)
- Full‑duplex operation: separate TX and RX shift registers
- Finite State Machine (FSM) in the master for robust control
- Tri‑state MISO output on the slave
- Testbench with two slaves running on different clocks (71 MHz and 83 MHz) and master at 100 MHz

## Architecture / Design
The design consists of three main modules:

1. **SPI (Master)** – `SPI.sv`  
   - Contains an FSM with states: `IDLE`, `DELAY`, `ACTIVE`, `TRAIL`.  
   - In `IDLE` waits for `start_pulse`, loads `master_put` into `tx`.  
   - `DELAY` asserts `cs_out` and waits `T_LEAD` cycles.  
   - `ACTIVE` generates `sck_b` using `PRESCALLER`, shifts out `tx` on MOSI (falling edge), samples MISO into `rx` (rising edge).  
   - `TRAIL` waits `T_TRAIL` cycles, then outputs `rx` to `master_get` and returns to `IDLE`.  
   - Synchronizes `miso_inp` with two flip‑flops.
<img width="1233" height="695" alt="image" src="https://github.com/user-attachments/assets/21c98709-1519-4deb-a0d4-74e073308130" />

2. **Slave** – `slave.sv`  
   - Synchronizes `sck_b_inp`, `mosi_inp`, `cs_inp` with two flip‑flops each.  
   - Detects when `cs == SLAVE_ID` (`active`).  
   - On rising edge of `active` (`exchange_start`) loads `slave_put` into `tx`.  
   - Uses internal `clk` to detect `sck_b` edges (`sck_b_rising`, `sck_b_falling`) for shifting `tx` and sampling `rx`.  
   - After 16 bits (`B`) sets `exchange_done` and latches `rx` into `slave_get`.  
   - Drives `miso` with `tx[B-1]` when active, otherwise high‑Z.

3. **Testbench** – `tb_spi.sv`  
   - Instantiates one master and two slaves with different clock frequencies.  
   - Provides four test packets, checking correct data exchange and error conditions.  
   - Includes timeout and VCD dump.

## Interface

### Master (`SPI`)
| Signal        | Direction | Width                     | Description                       |
|---------------|-----------|---------------------------|-----------------------------------|
| `clk`         | input     | 1                         | Master clock                      |
| `reset`       | input     | 1                         | Synchronous reset (active high)   |
| `slave_id`    | input     | `$clog2(N_SLAVES)`        | Slave address to select           |
| `master_put`  | input     | `B`                       | Data to transmit                  |
| `start`       | input     | 1                         | Start transmission pulse          |
| `idle`        | output    | 1                         | High when master is idle          |
| `master_get`  | output    | `B`                       | Received data                     |
| `miso_inp`    | input     | 1                         | MISO line from slaves             |
| `mosi`        | output    | 1                         | MOSI line to slaves               |
| `cs_out`      | output    | `$clog2(N_SLAVES)`        | Chip select (numeric slave ID)    |
| `sck_b`       | output    | 1                         | SPI clock                         |

### Slave (`slave`)
| Signal             | Direction | Width                | Description                       |
|--------------------|-----------|----------------------|-----------------------------------|
| `clk`              | input     | 1                    | Slave clock                       |
| `reset`            | input     | 1                    | Synchronous reset (active high)   |
| `slave_put`        | input     | `B`                  | Data to transmit                  |
| `exchange_done`    | output    | 1                    | Pulses when exchange completes    |
| `slave_get`        | output    | `B`                  | Received data                     |
| `sck_b_inp`        | input     | 1                    | SPI clock from master             |
| `mosi_inp`         | input     | 1                    | MOSI from master                  |
| `cs_inp`           | input     | `$clog2(N_SLAVES)`   | Chip select from master           |
| `miso`             | output    | 1                    | MISO to master (tri‑state)        |

## Usage
Instantiate the master and slave modules with desired parameters. Connect `sck_b`, `mosi`, `miso`, and `cs_out`/`cs_inp` appropriately.  
Example for master:

```systemverilog
SPI #(
    .B(16),
    .PRESCALLER(31),
    .N_SLAVES(8),
    .T_LEAD(16),
    .T_TRAIL(16)
) master (
    .clk(master_clk),
    .reset(reset),
    .slave_id(slave_id),
    .master_put(master_put),
    .start(start),
    .idle(master_idle),
    .master_get(master_get),
    .miso_inp(miso),
    .mosi(mosi),
    .cs_out(cs),
    .sck_b(sck_b)
);
```

For a slave:

```systemverilog
slave #(
    .B(16),
    .N_SLAVES(8),
    .SLAVE_ID(1)
) slave_1 (
    .clk(slave_1_clk),
    .reset(reset),
    .slave_put(slave_1_put),
    .exchange_done(slave_1_exchange_done),
    .slave_get(slave_1_get),
    .sck_b_inp(sck_b),
    .mosi_inp(mosi),
    .cs_inp(cs),
    .miso(miso)
);
```

## Code Description
- **SPI.sv** – Master module with FSM, clock prescaler, shift registers, and synchronizer for MISO.  
- **slave.sv** – Slave module with input synchronizers, edge detectors, shift registers, and tri‑state MISO.  
- **tb_spi.sv** – Testbench that verifies data exchange between one master and two slaves with different clock frequencies. It runs four test packets and checks expected values.

## Testing
The testbench (`tb_spi.sv`) performs the following checks:
- Packet 1: master sends `0xAAAA` to slave 1, expects `0x1111` back.
- Packet 2: master sends `0xAAAA` to slave 2, expects `0x2222` back.
- Packet 3: master sends `0xABCD` to slave 1 (slave 1 now sends `0x1234`), expects `0x1234` back.
- Packet 4: master sends `0xABCD` to slave 2 (slave 2 now sends `0x5678`), expects `0x5678` back.

Waveform screenshot:  
<img width="1036" height="506" alt="изображение" src="https://github.com/user-attachments/assets/2d13d66b-1fa6-4e42-b0c4-7900e09aeffd" />

## License
“For academic use only”.

## Author
Andrei Vladimirovich Bodeev, 25.09.2026, krjekovichav@gmail.com.

---

# Реализация SPI интерфейса

## Обзор
Проект реализует интерфейс SPI «мастер – слейв» на основе архитектуры сдвиговых регистров, замкнутых в кольцо. Поддерживается полнодуплексный обмен, выбор нескольких слейвов (с разными частотами кварца) и синхронизация для надёжной передачи данных.  
Сначала была сделана очень простая, но ненадёжная схема, но позже удалось приблизиться к возможностям OpenTitan.

## Возможности
- 16‑битный сдвиговый регистр (параметр `B`, по умолчанию 16; достаточно для точного представления чисел с плавающей точкой)
- Режимы мастера и слейва
- Выбор нескольких слейвов через числовой `slave_id` (вместо отдельных линий CS)
- Встроенные синхронизаторы (2‑триггерные) для пересечения тактовых доменов
- Настраиваемый делитель частоты (`PRESCALLER`, по умолчанию 31)
- Настраиваемые задержки `T_LEAD` и `T_TRAIL`
- Полнодуплексный режим: отдельные сдвиговые регистры для передачи и приёма
- Конечный автомат (FSM) в мастере для надёжного управления
- Трёхстабильный выход MISO у слейва
- Тестбенч с двумя слейвами на разных частотах (71 МГц и 83 МГц) и мастером на 100 МГц

## Архитектура / Проектирование
Проект состоит из трёх основных модулей:

1. **SPI (Мастер)** – `SPI.sv`  
   - Содержит FSM с состояниями: `IDLE`, `DELAY`, `ACTIVE`, `TRAIL`.  
   - В `IDLE` ждёт `start_pulse`, загружает `master_put` в `tx`.  
   - `DELAY` выставляет `cs_out` и ждёт `T_LEAD` тактов.  
   - `ACTIVE` генерирует `sck_b` с помощью `PRESCALLER`, сдвигает `tx` на MOSI (по спаду), сэмплирует MISO в `rx` (по фронту).  
   - `TRAIL` ждёт `T_TRAIL` тактов, затем выдаёт `rx` на `master_get` и возвращается в `IDLE`.  
   - Синхронизирует `miso_inp` двумя триггерами.
<img width="1233" height="695" alt="image" src="https://github.com/user-attachments/assets/21c98709-1519-4deb-a0d4-74e073308130" />

2. **Слейв** – `slave.sv`  
   - Синхронизирует `sck_b_inp`, `mosi_inp`, `cs_inp` двумя триггерами каждый.  
   - Определяет активность, когда `cs == SLAVE_ID` (`active`).  
   - По переднему фронту `active` (`exchange_start`) загружает `slave_put` в `tx`.  
   - Использует внутренний `clk` для детекции фронтов `sck_b` (`sck_b_rising`, `sck_b_falling`) для сдвига `tx` и приёма `rx`.  
   - После 16 бит (`B`) устанавливает `exchange_done` и защёлкивает `rx` в `slave_get`.  
   - Управляет `miso` значением `tx[B-1]`, когда активен, иначе высокий импеданс.

3. **Тестбенч** – `tb_spi.sv`  
   - Создаёт один мастер и два слейва с разными тактовыми частотами.  
   - Выполняет четыре тестовых пакета, проверяя правильность обмена и ошибки.  
   - Включает таймаут и дамп VCD.

## Интерфейсы

### Мастер (`SPI`)
| Сигнал        | Направление | Разрядность                | Описание                           |
|---------------|-------------|----------------------------|------------------------------------|
| `clk`         | вход        | 1                          | Тактовый сигнал мастера            |
| `reset`       | вход        | 1                          | Синхронный сброс (активный высокий)|
| `slave_id`    | вход        | `$clog2(N_SLAVES)`         | Адрес выбираемого слейва           |
| `master_put`  | вход        | `B`                        | Данные для передачи                |
| `start`       | вход        | 1                          | Импульс начала передачи            |
| `idle`        | выход       | 1                          | Высокий, когда мастер свободен     |
| `master_get`  | выход       | `B`                        | Принятые данные                    |
| `miso_inp`    | вход        | 1                          | Линия MISO от слейвов              |
| `mosi`        | выход       | 1                          | Линия MOSI к слейвам               |
| `cs_out`      | выход       | `$clog2(N_SLAVES)`         | Выбор слейва (числовой ID)         |
| `sck_b`       | выход       | 1                          | Тактовый сигнал SPI                |

### Слейв (`slave`)
| Сигнал             | Направление | Разрядность          | Описание                           |
|--------------------|-------------|----------------------|------------------------------------|
| `clk`              | вход        | 1                    | Тактовый сигнал слейва             |
| `reset`            | вход        | 1                    | Синхронный сброс (активный высокий)|
| `slave_put`        | вход        | `B`                  | Данные для передачи                |
| `exchange_done`    | выход       | 1                    | Импульс завершения обмена          |
| `slave_get`        | выход       | `B`                  | Принятые данные                    |
| `sck_b_inp`        | вход        | 1                    | Тактовый сигнал SPI от мастера     |
| `mosi_inp`         | вход        | 1                    | MOSI от мастера                    |
| `cs_inp`           | вход        | `$clog2(N_SLAVES)`   | Выбор слейва от мастера            |
| `miso`             | выход       | 1                    | MISO к мастеру (трёхстабильный)    |

## Использование
Подключите модули мастера и слейва с нужными параметрами. Соедините `sck_b`, `mosi`, `miso`, а также `cs_out`/`cs_inp` соответствующим образом.  
Пример для мастера:

```systemverilog
SPI #(
    .B(16),
    .PRESCALLER(31),
    .N_SLAVES(8),
    .T_LEAD(16),
    .T_TRAIL(16)
) master (
    .clk(master_clk),
    .reset(reset),
    .slave_id(slave_id),
    .master_put(master_put),
    .start(start),
    .idle(master_idle),
    .master_get(master_get),
    .miso_inp(miso),
    .mosi(mosi),
    .cs_out(cs),
    .sck_b(sck_b)
);
```

Для слейва:

```systemverilog
slave #(
    .B(16),
    .N_SLAVES(8),
    .SLAVE_ID(1)
) slave_1 (
    .clk(slave_1_clk),
    .reset(reset),
    .slave_put(slave_1_put),
    .exchange_done(slave_1_exchange_done),
    .slave_get(slave_1_get),
    .sck_b_inp(sck_b),
    .mosi_inp(mosi),
    .cs_inp(cs),
    .miso(miso)
);
```

## Описание кода
- **SPI.sv** – модуль мастера с FSM, делителем частоты, сдвиговыми регистрами и синхронизатором MISO.  
- **slave.sv** – модуль слейва с синхронизаторами входов, детекторами фронтов, сдвиговыми регистрами и трёхстабильным MISO.  
- **tb_spi.sv** – тестбенч, проверяющий обмен данными между одним мастером и двумя слейвами с разными тактовыми частотами. Выполняет четыре тестовых пакета и сверяет ожидаемые значения.

## Тестирование
Тестбенч (`tb_spi.sv`) выполняет следующие проверки:
- Пакет 1: мастер отправляет `0xAAAA` слейву 1, ожидает ответ `0x1111`.
- Пакет 2: мастер отправляет `0xAAAA` слейву 2, ожидает ответ `0x2222`.
- Пакет 3: мастер отправляет `0xABCD` слейву 1 (слейв 1 теперь отправляет `0x1234`), ожидает ответ `0x1234`.
- Пакет 4: мастер отправляет `0xABCD` слейву 2 (слейв 2 теперь отправляет `0x5678`), ожидает ответ `0x5678`.

Скриншот временных диаграмм:  
<img width="1036" height="506" alt="изображение" src="https://github.com/user-attachments/assets/2d13d66b-1fa6-4e42-b0c4-7900e09aeffd" />

## Лицензия
«Только для академического использования».

## Автор
Андрей Владимирович Бодеев, 25.09.2026, krjekovichav@gmail.com.
