# host_app/ — PC(윈도우) 앱: 어셈블 → FPGA 실행 → 결과 표시

PC에서 RISC-V 어셈블리를 입력하면 **기계어로 변환 → UART로 FPGA의 RV32 CPU에 적재 →
실행 → 바뀐 레지스터·메모리·주변장치 표시**. 두 가지 프런트엔드 제공:
- **`rv32_gui.py`** — PySide6 데스크톱 GUI (권장).
- **`rv32_console.py`** — 명령줄 REPL.

둘 다 동일한 어셈블러와 PS UART 프로토콜을 쓴다. 보드 쪽은 `ps_firmware/rv32_monitor.c`가
돌고 있어야 함(115200 8N1).

## A. GUI — `rv32_gui.py` (권장)
```
pip install pyserial PySide6
python rv32_gui.py
```
창 상단에서 포트 선택 → **Connect**. 패널:
- **Assembly** — 편집기 + `Run ▶ / Step / Reset / Assemble`, 하단 기계어 미리보기.
- **Registers** — x0~x31, 바뀐 레지스터 노란색 강조, signed/hex 토글.
- **Data memory** — 시작주소·워드 수 지정 후 데이터 RAM 덤프.
- **Peripherals** — LED/SW/BTN 4비트 인디케이터.
  - 펌웨어가 `L/W/N`(0x38/0x3C/0x40 readback)을 지원하면 `auto-poll`로 **라이브** 표시.
  - 미지원(구 비트스트림)이면 `Refresh/Probe` 버튼이 작은 MMIO-read 프로그램을 실행해
    값을 읽음(이때 CPU의 적재 프로그램을 덮어쓰므로, 이후 `Run`으로 다시 적재).
- **Serial log** — 주고받는 모든 UART 라인.

> 라이브 주변장치 표시를 쓰려면 `rv32_ctrl_axi.vhd`/`rv32_platform.vhd`의 LED/SW/BTN
> readback 레지스터가 포함된 비트스트림 + `L/W/N`이 추가된 `rv32_monitor.c`가 필요.
> (없어도 GUI는 자동 감지해 프로브 방식으로 동작.)

## B. 콘솔 — `rv32_console.py`
```
pip install pyserial
python rv32_console.py --port COM5         # Windows (장치관리자에서 보드 COM 확인)
python rv32_console.py --port /dev/ttyUSB1 # Linux
python rv32_console.py                     # 포트 생략 = 오프라인(어셈블만)
```

## 사용 (REPL)
```
rv32> addi x1, x0, 7        # 한 줄씩 입력 -> 프로그램 버퍼에 누적(+기계어 표시)
rv32> addi x2, x0, 11
rv32> add  x3, x1, x2
rv32> run                  # reset -> 적재(+halt) -> 실행 -> 바뀐 레지스터 출력
  x1 = 0x00000007 (7)
  x2 = 0x0000000b (11)
  x3 = 0x00000012 (18)
```
명령:
- `<asm>` 한 줄 = 프로그램에 추가          - `run` 실행 후 변화 표시
- `step` 1스텝(마지막 커밋 표시)           - `reg` 전체 레지스터 덤프
- `mem <addr>` 데이터메모리 읽기           - `list`/`clear` 버퍼 보기/비우기
- `asm <instr>` 전송 없이 기계어만 확인    - `quit`

## 지원 명령어 (RV32I)
- 산술/논리: add sub and or xor sll srl sra slt sltu, addi andi ori xori slti sltiu slli srli srai
- 메모리: lw lh lhu lb lbu, sw sh sb        (형식: `lw x5, 0(x4)`)
- 분기/점프: beq bne blt bge bltu bgeu, jal jalr   (라벨 또는 수치 오프셋)
- U형: lui auipc
- 의사명령: nop, mv, li(12비트), j, ret, halt
- 라벨: `loop:` 형태, 2-pass 어셈블 (예: 카운트 루프)

예 — 루프로 1..N 합:
```
li  x2, 5
loop:
  add  x1, x1, x2
  addi x2, x2, -1
  bne  x2, x0, loop
halt
run        # -> x1 = 0xf (15)
```

## 전체 흐름 (end-to-end)
```
[PC: rv32_console.py]  --어셈블-->  기계어 워드
        | UART (PS 모니터 프로토콜: r / i A D / g / D ...)
        v
[Zynq PS: rv32_monitor.c]  --AXI-Lite @0x40000000-->  [PL: rv32_platform = RV32 CPU + I$/D$ + MMIO]
        ^                                                       |
        +------------------ 레지스터/PC/커밋 회신 <-------------+
```
LED를 켜보려면(예): `li x1,0xf` / `lui x2,0x10000` / `sw x1,0(x2)` / `halt` → `run` →
보드 LED 4개 점등(MMIO 0x10000000). 스위치 읽기: `lui x2,0x10000`/`lw x3,4(x2)`.

## 참고
- 어셈블러 인코딩은 검증된 테스트벤치/모델과 동일 로직.
- 정밀 1명령 스텝은 파이프라인 특성상 한 명령 더 진행될 수 있음 → 정확한 단발 결과는
  "명령 + halt 적재 후 run"(=이 앱의 `run`) 방식 권장.
```
```
