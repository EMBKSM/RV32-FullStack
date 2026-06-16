# RV32-FullStack

검증된 **RV32I 소프트코어 CPU**(5-stage 파이프라인 + I$/D$ + AXI4 + Zicsr/트랩/FENCE.I)를
Zynq-7000(Zybo Z7-20) FPGA에 올리고, **PC에서 RISC-V 어셈블리를 입력하면 UART로 전송 →
CPU가 실행 → 결과(레지스터 변화)를 회신**하는 완전한 시스템.

```
[PC] host_app/rv32_console.py   (어셈블러 + UART 콘솔)
   │  "add x3,x1,x2" → 기계어 → 프로토콜
   ▼ USB-UART 115200 8N1
[Zynq PS / ARM]  ps_firmware/rv32_monitor.c   (명령 파서 + AXI-Lite 드라이버)
   │  AXI4-Lite @ 0x4000_0000
   ▼
[Zynq PL]  rv32_platform   =   RV32 CPU + I$/D$ + 데이터/명령 RAM + MMIO(LED/SW/BTN)
   ▲  레지스터 / PC / 커밋 / 데이터 회신
   └──────────────────────────────────────────────────────────────────┘
```

---

## 1. 저장소 구조
```
ip_workspace/          RTL (블록별) + 단위 TB(tb_*.sv) + acceptance_tests.md
  0_IF 1_ID 2_EX 3_Mem 4_WB common 5_Platform
  rv32_core.vhd        CPU 코어(파이프라인)
  rv32_soc.vhd         시뮬용 SoC(코어+I$/D$+거동메모리)
  5_Platform/          mmio_bridge, rv32_ctrl_axi, rv32_platform (합성용 PL 탑)
bd_assembly/           BD 손배선용 glue RTL(mux2_32 등)
verification/          통합 TB(tb_rv32_soc/ tb_rv32_platform/ tb_ps_regress ...) + Python 모델
constraints/           zybo_z7_20_gpio.xdc  (LED/SW/BTN 핀)
scripts/               IP 패키징 / BD 빌드 / 비트스트림 / 회귀 tcl·bat (+ README)
ps_firmware/           Zynq PS 베어메탈 모니터(C) + 빌드 안내
host_app/              PC 콘솔(어셈블러+UART, Python) + 안내
docs/                  VERIFICATION.md(통합 검증) + 설계 문서(SOC_PLATFORM/BD_*)
ip_repo/               패키징된 user IP
(gitignored)           rv_pl/ vivado_zynq/ ip_build/  (스크립트로 재생성)
```

---

## 2. 빠른 시작 (4단계)
1. **시뮬 검증** — §3
2. **비트스트림 생성** — §4
3. **PS 펌웨어** (Vitis) — §5
4. **PC 콘솔로 실행** — §6

---

## 3. 시뮬레이션 / 검증
### 3.1 Python 모델 회귀 (보드·Vivado 불필요)
```
cd verification
python run_ifwb_core.py --programs 4000     # 파이프라인 모델 vs ISS (AT-01..30 + 랜덤)
python run_pipeline50.py                    # 50-iter 회귀
python test_rv32.py                         # 10-iter 회귀
python run_alu_at.py ; python run_id_wb_at.py
python verify_spec.py ; python verify_docs.py
# 검증 유효성(결함 검출) 확인:
python run_ifwb_core.py --bug forward       # forward|hazard|branch|x0 → "FAULT CAUGHT"
```
### 3.2 HDL(xsim) 회귀
- 일괄: Vivado tools PATH 잡힌 cmd에서 `scripts\run_all_xsim.bat` (전 VHDL 컴파일 후 모든 SV TB 실행).
- 개별: Vivado 프로젝트에서 sim top 지정 후 `launch_simulation; run all`.
  - `tb_rv32_soc`     — 풀 SoC(데이터패스+D$+CSR/트랩+FENCE.I+AT-30 랜덤)
  - `tb_rv32_platform`— 플랫폼(PS 방식 load/run/step + MMIO)
  - **`tb_ps_regress`** — **PS 제어경로 회귀: 25개 랜덤 프로그램을 PS와 동일한 AXI 시퀀스로
    적재·실행·레지스터회신, ISS와 비트단위 대조**. (프로그램 수 조정: `-testplusarg PROGRAMS=40`)
  - 기대: 각 TB 끝에 `RESULT: ALL PASS`.

상세 검증 과정·결과는 **`docs/VERIFICATION.md`** 참조.

---

## 4. 비트스트림 생성 (Vivado, cmd 배치)
```
"C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source scripts\package_platform_ip.tcl
"C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source scripts\build_zynq_project.tcl
"C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source scripts\run_bitstream.tcl
```
- 1: `rv32_platform`을 IP로 패키징(S_AXI 슬레이브).
- 2: 새 프로젝트 `vivado_zynq` + Zynq PS(Zybo 프리셋) + IP를 AXI 연결한 BD + wrapper.
- 3: GPIO XDC 추가 → 합성→구현→비트스트림. 결과: `vivado_zynq/.../impl_1/rv32_top_wrapper.bit`.
- (메모리는 BRAM으로 추론, LUT~47%, 타이밍 만족.)

---

## 5. PS 펌웨어 (Vitis)
1. Vivado `vivado_zynq` → **Export Hardware (Include bitstream)** → `.xsa`.
2. Vitis: `.xsa`로 Platform(standalone, `ps7_cortexa9_0`) → Empty C App.
3. `ps_firmware/rv32_monitor.c`를 app `src/`에 추가 → Build.
4. 보드 연결 → Program FPGA → app Run.
- 제어 슬레이브 주소가 다르면 `rv32_monitor.c`의 `RV32_BASE` 수정(기본 `0x40000000`).
- 자세히: `ps_firmware/README.md`.

---

## 6. PC에서 실행 (GUI 또는 콘솔)

### 6.1 GUI 앱 (권장) — `host_app/rv32_gui.py`
```
pip install pyserial PySide6
python host_app/rv32_gui.py
```
창 상단에서 보드 COM 포트 선택 → **Connect**. 패널 4개:
- **Assembly** — 어셈블리 입력 + `Run ▶ / Step / Reset / Assemble`, 하단 기계어 미리보기.
- **Registers** — x0~x31 표, 실행으로 **바뀐 레지스터를 노란색으로 강조**(signed/hex 전환).
- **Data memory** — 주소·워드 수 지정 후 데이터 RAM 덤프(PS dump 포트).
- **Peripherals** — LED/SW/BTN 4비트 인디케이터. 펌웨어가 지원하면(L/W/N) `auto-poll`로
  라이브 표시, 아니면 `Refresh/Probe`(micro-program)로 읽음.
- 하단 **Serial log** — PS와 주고받는 모든 UART 라인.

### 6.2 콘솔(CLI) — `host_app/rv32_console.py`
```
pip install pyserial
python host_app/rv32_console.py --port COM5      # 보드 COM 포트
```
```
rv32> addi x1, x0, 7
rv32> addi x2, x0, 11
rv32> add  x3, x1, x2
rv32> run
  x1 = 0x00000007 (7)
  x2 = 0x0000000b (11)
  x3 = 0x00000012 (18)
```
명령: `<asm>`(추가) `run` `step` `reg` `mem <a>` `list` `clear` `asm <i>` `quit`.
지원 명령어/예제(루프·LED)는 `host_app/README.md`.

### 6.3 Pmod 주변장치 구동 예제 — SPI (JA)
모든 Pmod 헤더(JA~JE, 40핀)가 MMIO 주변장치로 매핑돼 있어, 어셈블리에서 `sw`/`lw`로
직접 제어한다(`0x1000_0000` 윈도우, PS 펌웨어/GUI 수정 불필요).
아래는 **SPI0(JA)로 1바이트(0x55) 전송**. JA의 **2번(MOSI)↔3번(MISO)** 핀을 점프선으로
묶으면 루프백되어 수신값이 송신값과 같아진다(`x4 = 0x55`). GUI Assembly 패널에 붙여넣거나
콘솔에 한 줄씩 입력한 뒤 `Run`/`run`.

```asm
    li    x1, 0x10000040    # SPI0 base (JA)
    li    x2, 24
    sw    x2, 8(x1)         # DIV  -> ~1 MHz SCLK
    sw    x0, 0(x1)         # CTRL -> mode 0, auto-SS
    li    x2, 0x55
    sw    x2, 12(x1)        # TX = 0x55  -> 전송 시작
wait:
    lw    x3, 4(x1)         # STATUS
    andi  x3, x3, 1         # busy 비트
    bnez  x3, wait          # 전송 끝까지 대기
    lw    x4, 16(x1)        # RX  (점프선 루프백 시 0x55)
```
실행 결과 Registers 패널에 `x4 = 0x00000055`(노란색 강조). 점프선 없이 실제 Pmod SPI
모듈을 꽂으면 같은 패턴으로 그 장치와 통신한다.
나머지 주변장치(I2C/UART/PWM/GPIO)의 레지스터맵·핀맵·예제는 **`PMOD_PERIPHERALS_DESIGN.md`** 참조.

---

## 7. 인터페이스 레퍼런스
### 7.1 AXI-Lite 제어 레지스터 (PS 베이스 `0x4000_0000`)
| off | R/W | 이름 | 설명 |
|---|---|---|---|
|0x00|W|CTRL|b0 reset, b1 run, b2 step, b3 clr_commit|
|0x04|R|STATUS|b0 halted, b2 run|
|0x08/0x0C|W|IMEM_ADDR / IMEM_WDATA|명령 메모리 적재(주소 후 데이터)|
|0x10/0x14|W|DMEM_ADDR / DMEM_WDATA|데이터 메모리 적재|
|0x18/0x1C|W/R|REG_ADDR / REG_RDATA|레지스터 N 선택 후 값 읽기|
|0x20|R|PC|현재 PC|
|0x24/0x28|R|LAST_RD / LAST_WDATA|마지막 커밋의 rd / 기록값|
|0x2C|R|COMMIT_CNT|리타이어 명령 수|
|0x30/0x34|W/R|DMEM_RADDR / DMEM_RDATA|데이터 메모리 읽기|
|0x38/0x3C/0x40|R|LED / SW / BTN|보드 주변장치 읽기(주변장치-readback 빌드. 구 비트스트림은 0)|

### 7.2 CPU 메모리 맵 / MMIO
| 영역 | 주소 | 비고 |
|---|---|---|
|명령 RAM|0x0000_0000~|I$ 백킹(Harvard)|
|데이터 RAM|0x0000_0000~0x0000_3FFF|D$(캐시됨)|
|MMIO LED (W)|0x1000_0000|하위 4비트 → 보드 LED|
|MMIO SW (R)|0x1000_0004|스위치 4|
|MMIO BTN (R)|0x1000_0008|버튼 4|
|MMIO GPIO|0x1000_0020|DIR/OUT/IN — Pmod 잔여 22핀|
|MMIO SPI0 / SPI1|0x1000_0040 / 0x60|CTRL/STAT/DIV/TX/RX — JA / JB|
|MMIO I2C0 / I2C1|0x1000_0080 / 0xA0|CMD/STAT/DIV/TX/RX — JC / JD|
|MMIO UART|0x1000_00C0|DIV/STAT/TX/RX — JE|
|MMIO PWM|0x1000_00E0|CTRL/PERIOD/DUTY0..3 — JE|

> Pmod 주변장치(JA~JE) 블록은 `addr[7:5]`=장치, `addr[4:2]`=레지스터로 디코드된다.
> 전체 비트 정의·핀맵·예제 어셈블리는 **`PMOD_PERIPHERALS_DESIGN.md`** 참조.

### 7.3 UART 프로토콜 (PS 모니터, 한 줄=한 명령, HEX)
`r`(reset) `i A D`(imem) `d A D`(dmem) `g`(run) `s`(step) `x N`(reg) `m A`(dmem rd)
`p`(pc) `c`(commit) `t`(status) `D`(전체 레지스터) `L`(led) `W`(sw) `N`(btn) `h`(help).
`L/W/N`은 주변장치-readback 빌드에서만 실제값을 반환(구 빌드는 0).

---

## 8. 트러블슈팅
- **콘솔 응답 없음**: 보드 COM/보레이트(115200) 확인, FPGA 프로그램+app Run 상태 확인.
- **레지스터가 다 0**: `r` 후 `i`로 적재했는지, `g`로 run 했는지. (reset이 레지스터/캐시 초기화.)
- **합성에서 RAM 추론 실패**: 메모리는 동기읽기로 BRAM 추론하도록 작성됨(`axi_slave_mem`).
- **Vivado가 수정 반영 안 함("No Change in HDL")**: `close_sim; reset_simulation -mode behavioral;
  launch_simulation` 또는 sim 폴더 삭제 후 재실행. (소스가 프로젝트에 import 복사본으로 들어가면
  원본 수정이 반영 안 됨 — 원본 참조로 add.)
- **정밀 1명령 step**: 파이프라인 특성상 한 명령 더 진행될 수 있음. 정확한 단발 결과는
  "명령+halt 적재 후 run"(콘솔 `run`) 사용.

---

## 9. 현황
RV32I+Zicsr+트랩+FENCE.I CPU, I$/D$/AXI, 전 블록 IP, Zynq SoC 비트스트림(Zybo Z7-20),
PS 펌웨어, PC 콘솔/GUI까지 완성·검증. **Pmod 헤더 JA~JE(40핀)를 MMIO 주변장치
(2×SPI·2×I2C·UART·PWM·GPIO)로 노출** — 어셈블리에서 직접 제어(§6.3, `PMOD_PERIPHERALS_DESIGN.md`).
세부 검증 내역은 `docs/VERIFICATION.md`.
