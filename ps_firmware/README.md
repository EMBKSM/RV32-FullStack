# ps_firmware/ — Zynq PS 베어메탈 모니터

`rv32_monitor.c` = ARM(PS)에서 도는 베어메탈 프로그램. PC와 UART로 통신하며
PL의 `rv32_platform` AXI-Lite 슬레이브(BD 주소 `0x4000_0000`)를 제어해 RV32 CPU에
프로그램을 적재·실행·관찰한다.

## Vitis 빌드/실행 순서
1. **Vivado에서 하드웨어 export**: `vivado_zynq` 프로젝트 열기 → File → Export →
   Export Hardware → **Include bitstream** → `rv32_top_wrapper.xsa` 생성.
2. **Vitis**: New Application Project →
   - Platform: 위 `.xsa`에서 생성, CPU `ps7_cortexa9_0`, OS `standalone`.
   - Template: **Empty Application (C)**.
3. `rv32_monitor.c`를 app의 `src/`에 추가(드래그) → Build.
   - (제어 슬레이브 주소가 다르면 `-DRV32_BASE=0x...` 또는 파일 상단 매크로 수정.
     `xparameters.h`의 `XPAR_*_S_AXI_BASEADDR`로 대체해도 됨.)
4. 보드 연결 → **Program FPGA**(비트스트림) → app을 **Run/Debug**.
5. PC에서 시리얼 터미널(115200 8N1, 보드 COM 포트) 열면 `=== RV32 PS monitor ===` 배너.

## 프로토콜 (한 줄 = 한 명령, 숫자는 HEX)
| 명령 | 동작 | 응답 |
|---|---|---|
| `r` | CPU reset+hold (적재 준비, 커밋카운터 0) | `OK` |
| `i A D` | imem[A]=D (명령어 워드 적재) | `OK` |
| `d A D` | dmem[A]=D (데이터 적재) | `OK` |
| `g` | reset 해제 + run | `OK` |
| `s` | 1스텝 (정지 상태에서) | `OK rd=.. wd=.. cc=..` |
| `x N` | 레지스터 N 읽기 | `xN=........` |
| `m A` | 데이터메모리 워드 읽기 | `mA=........` |
| `p` | PC 읽기 | `pc=........` |
| `c` | 커밋 수 | `cc=..` |
| `t` | 상태(b0=halted) | `st=........` |
| `D` | x0..x31 전체 덤프 | 32줄 |

## 예시 세션 — `addi x1,x0,7; addi x2,x0,11; add x3,x1,x2; jal x0,0(halt)`
```
r
i 0 00700093      (addi x1,x0,7)
i 4 00b00113      (addi x2,x0,11)
i 8 002081b3      (add  x3,x1,x2)
i c 0000006f      (jal  x0,0  = halt)
g
D                 -> x1=00000007 x2=0000000b x3=00000012 ...
```
"명령 단위 실행+변화 회신"은 단발 실행(명령+halt 적재 → `g` → `x rd`)으로,
또는 `s`로 스텝하며 `cc`/`x` 폴링으로 구현. 호스트(윈도우 앱)가 어셈블→`i`로 전송→
`g`/`s`→`x`/`D`로 결과 표시하면 된다.
```
```
