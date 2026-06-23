# HANDOFF / 상황 저장 — RV32 + 16×16 NPU
_저장 시점: 2026-06-23 (Fmax 최적화 완료)_

## 현재 상태 — 100 MHz 클로징 + 106 MHz(MMCM) 보드검증 ✅✅✅
**16×16 NPU SoC: 37→100 MHz 타이밍 클로징(WNS +0.085, 실패 0) + 실보드 PASS. 추가로 리타이밍+PL MMCM로 106 MHz까지 실보드 GEMM PASS.** MAC 어레이 무수정. 자세한 건 `docs/PERFORMANCE_FMAX.md`.
- **106MHz**: 합성 리타이밍으로 Fmax 100.9→110.8MHz, FCLK0 단계 안 맞아(÷9=111 초과) → **PL MMCM(clk_wiz) 삽입**: `FCLK0 100 → MMCM → 106MHz PL`. WNS −0.118@106(slow corner, 4EP)지만 실리콘서 GEMM PASS. 비트 `flash/rv32_16x16_mmcm.bit`, 테스트 `flash/run_gemm_test_mmcm.bat`. (BD에 clk_wiz_0 추가됨; 100MHz로 되돌리려면 rv32_16x16_100mhz.bit 사용.)
- 벽: 리타이밍 후 worst = RV32 코어 load-use 해저드(exmem→ifid, 75% route) ~110MHz가 5단 파이프 근본한계. 블라인드 플로어플랜=중립.
- 마지막 빗장: 시스톨릭 `t`카운터 피드(a_west/b_north)를 레지스터링 → t→PE 경로 분할, 입력 스트림 1클럭 균일 시프트(t_last+1, 비트동일). 이 한 방으로 WNS −0.602→**+0.085ns**, 실패 817→**0**. (코어는 limiter가 아니었음.)
- 100MHz = FCLK0 ÷10 (`mwr 0xF8000170 0x00100A00`) — MMCM 불필요. 보드 GEMM C=[[39,53],[17,23]] PASS.
- 비트스트림: `flash/rv32_16x16_100mhz.bit`(100MHz, 보드검증). 백업: `flash/rv32_16x16_94mhz_verified.bit`(v3 94MHz).
- 테스트: `flash/run_gemm_test_100.bat` (FCLK0=0x00100A00=100MHz). 90.9MHz로 낮추려면 0x00100B00.
- 병목은 NPU **리드백 경로** 2개였음(MAC 아님): ① 256:1 누산기 먹스, ② requant 32×17 곱셈.
  둘 다 레지스터 파이프라인 단계로 분리(코어 `mem_stall`/`rd_valid` 핸드셰이크 → SW엔 투명, 읽기 5클럭).
  - ① 3단 분리: 임계 26.7→13.3 ns, 37→75 MHz, 빌드 1h17m→8min(혼잡 해소).
  - ② requant 5단(곱셈→DSP): WNS −3.29→**−0.60 ns @100MHz** → **Fmax 94.3 MHz**. 실패 EP 3196→817.
- 기능검증: 매 단계 `verification/npu_scale16` 18,688 체크 / 0 에러.
- **보드 운영점: 90.9 MHz** (FCLK0 = IO-PLL 1000/11, 셋업 +0.40 ns·홀드 +0.016 ns 클린).
  - FCLK0=90.9MHz mwr 값 = **0x00100B00** (D0=11, D1=1). 94.3까지 정확히 가려면 PL MMCM("PLL MUX") 필요(후속).
- 비트스트림: `flash/rv32_16x16_100mhz.bit` (100MHz 타깃 빌드, ≤94.3MHz 클린). 보드테스트: `flash/run_gemm_test_100.bat`(FCLK0 값만 0x00100B00로 바꾸면 90.9MHz).
- 100MHz 풀클로징: 남은 worst = 시스톨릭 `t`카운터 제어 팬아웃 + RV32 5단 코어(50MHz 설계) → 코어 파이프라인 재설계 필요(보류, "달성가능 최대 Fmax" 선택).

### 마무리 상태 (자동 진행 결과)
- ✅ **커밋 완료: `e868476`** "perf(npu): pipeline NPU read-back -> Fmax 37->94.3 MHz". (sandbox git, rename기반 commit이 마운트에서 동작 — 단 delete는 EPERM이라 `.git`에 `_probe_dst`·`tmp_obj_*` 잔재 litter가 남음, 무해. 호스트에서 정리 권장.)
- ✅ **보드 통합테스트 @90.9MHz — PASS** (전원 재인가 후 `run_gemm_test_100.bat` 1회). `C=[[39,53],[17,23]]` 골든 정확 일치, `BOARD-GEMM-90MHZ: PASS`, xsct exit=0. 90.9MHz 통과 = 새 94MHz 비트스트림 실보드 동작 입증(구 37MHz는 90.9서 실패). 파이프라인 리드백(5클럭 스톨 핸드셰이크)도 실리콘 end-to-end 동작 확인.
  - (이력) 처음 3회는 전원 재인가 전 JTAG/DAP 퇴화(`DAP AHB AP transaction error`)로 실패 → 전원 OFF→ON 후 1회 통과.
  - 100MHz로도 돌려보려면 FCLK0=0x00100A00 (다만 WNS −0.602라 일부 경로 셋업 위반 — 2×2 GEMM은 우연히 통과할 수도, 보장 안 됨). 정석 94MHz는 PL MMCM 필요.

---
## (과거 기록) 30 MHz 클럭다운 경로

## 왜 클럭 다운인가 (핵심 결론)
- 16×16(256-PE INT8 systolic GEMM)은 **시뮬·기능·자원 전부 입증**됨: 18,688 체크 0 에러, 202/220 DSP(91.8%), 27% LUT.
- 그러나 50 MHz(20 ns)에서 **셋업 타이밍 실패: WNS = −6.74 ns** (32 endpoints). 256-PE가 DSP를 92% 채우면 작은 XC7Z020에서 PE↔PE 배선이 길어짐.
  - Default(정밀) 전략은 이 −6.74 ns를 닫으려다 **몇 시간**(220 DSP는 7691 overlaps로 1시간+ 미완).
  - RuntimeOptimized 전략은 **19분 만에 비트스트림** 생성하지만 타이밍 클로징을 건너뜀 → −6.74 ns.
- **홀드는 충족**(WHS +0.036 ns) → 클럭만 늦추면 셋업이 깨끗이 해결됨.
- 임계경로 = 26.74 ns → 최대 ~37.4 MHz. **30.3 MHz(÷33)에서 셋업 여유 +6.3 ns, 홀드 OK. 유효함.**

## 다음 단계 (정확히 이대로 실행하면 됨)
1. **`flash/ws/fsbl_fix/src/ps7_init.c`** 편집 — FCLK0 분주 변경 (3개 실리콘 리비전 카피 전부):
   ```
   EMIT_MASKWRITE(0XF8000170, 0x03F03F30U ,0x00400500U)   // 현재: D0=5,D1=4 → 1000/20 = 50 MHz
   →
   EMIT_MASKWRITE(0XF8000170, 0x03F03F30U ,0x00102100U)   // 변경: D0=33,D1=1 → 1000/33 = 30.3 MHz
   ```
   (FPGA0_CLK_CTRL @ 0xF8000170: [13:8]=DIVISOR0, [25:20]=DIVISOR1, [5:4]=SRCSEL=IO PLL 1000 MHz)
2. **FSBL 재빌드**: `flash\run_build_fsbl.bat` 실행 (xsct → `flash/ws/fsbl_fix/Debug/fsbl_fix.elf`).
   - build_fsbl.tcl의 `app create`는 앱이 이미 존재해 에러(catch)되고, `app build`가 편집된 ps7_init.c로 재컴파일됨 → 편집 보존됨.
3. **bif 작성** `flash/boot_npu16_30mhz.bif`:
   ```
   the_ROM_image:
   {
       [bootloader] C:/work/github/RV32-FullStack/flash/ws/fsbl_fix/Debug/fsbl_fix.elf
       C:/work/github/RV32-FullStack/flash/rv32_16x16_rtopt_wns-6p74.bit
       C:/work/github/RV32-FullStack/rv_ps/rv_firmware/build/rv_firmware.elf
   }
   ```
4. **bootgen** → `BOOT_npu16_30mhz.bin` (`bootgen -arch zynq -image boot_npu16_30mhz.bif -w -o BOOT_npu16_30mhz.bin`).
5. (보드) QSPI 플래시 → 부팅. NPU가 30.3 MHz로 동작, 타이밍 충족.
   - 검증: 드라이버(`host_app/npu_gemm_demo.s`)로 GEMM 실행 → C=4/16/96/256 기대.

## 핵심 산출물 (경로)
- **보존된 16×16 비트스트림** (50 MHz에선 −6.74 ns, ≤37 MHz에선 OK): `flash/rv32_16x16_rtopt_wns-6p74.bit` (4.0 MB)
- 16×16 RTL: `ip_workspace/6_NPU/` (npu_pe·array·top·top16). 현재 `npu_top16.vhd`는 **DSP_BUDGET=200** (요청 시 220으로 복귀 가능).
- 빌드 스크립트: `scripts/build_npu16.tcl`(전체 repackage+synth+impl), `scripts/rebuild_runtimeopt.tcl`(impl만 빠르게 재실행), `scripts/ooc_synth_npu16.tcl`(OOC 합성).
- 설계문서: `docs/NPU_DESIGN.md` (§11 scale-up + fit/timing).
- 기존 8×8 보드 이미지: `flash/BOOT_npu.bin` (50 MHz, 정상 동작) — **건드리지 않음, 보드 멀쩡**.

## 완료된 것 (검증됨)
- 16×16 기능 시뮬: 18,688 체크 0 에러 (GEMM·전체 256-PE 공간·누적·랜덤·requant).
- N=8 회귀 그대로 통과 (회귀 손상 0).
- OOC + 풀-SoC 합성: 202/220 DSP, 27% LUT.
- git 커밋 `cb642cb` (NPU + LUTRAM + 16×16). 그 이후 변경(아직 커밋 안 됨): npu_top16 200-DSP, rebuild_runtimeopt.tcl, 보존 비트스트림, 이 문서.

## 대안 (클럭 다운 말고, 나중에 재검토 시)
- **12×12 @ 50 MHz**: 혼잡 줄어 라우팅·타이밍 둘 다 분 단위 통과. 가장 깔끔한 정석 보드 데모. (144 MAC = 8×8의 2.25배)
- **16×16 @ 50 MHz 정석**: NPU Pblock 영역 고정 + skew/고팬아웃 제어신호 레지스터 단계 추가(긴 배선 끊기). RTL+XDC 작업. 32코어 확장의 토대.

## 보드 브링업 현황 (2026-06-22 — ✅ 보드 GEMM 검증 완료)
- **★ 16×16 NPU GEMM이 실보드(XC7Z020)에서 동작 확인됨 @ 30.3 MHz.** ctrl_axi 직접구동(DDR/OCM/모니터 전부 우회)으로 RV32에 드라이버 로드→실행→C 결과 읽기:
  - `flash/run_gemm_test.bat` (=jtag_gemm_test.tcl). 2×2 타일 GEMM(K=2): A=[[3,4],[1,2]], B=[[5,7],[6,8]].
  - 결과 **C = [[39,53],[17,23]]** = 골든 정확 일치. PC=0x7c(done 루프 도달), 커밋됨 → RV32+NPU end-to-end 실행 입증.
  - ⚠ `mrd -value`는 **10진수** 반환 → tcl puts에서 `0x` 프리픽스 붙이면 잘못 보임. 원시값(=실제 레지스터)이 정답.
- **16×16 비트스트림 프로그램**: JTAG `fpga`, FCLK0=0x00102100(30.3 MHz) 확인. DONE 점등.
- **QSPI 플래시 불가**(미해결, HW): `program_flash` mini-u-boot이 DDR에서 동작 → 보드 DDR 결함 → "Problem in running uboot". → 그래서 ctrl_axi 직접구동으로 우회 검증함.
- **JTAG 링크 플래키**: 반복 세션 누적 시 DAP/A9 enumeration 실패(AHB AP transaction error). 재현 시 보드 전원 OFF→ON 후 첫 1회 깨끗하게 통과.

### 보드 GEMM 재현 절차 (검증된 클린 경로)
1. **보드 전원 OFF→ON** (JTAG 부트모드) → 깨끗한 PS/DAP 상태 (반복 실행 후 DAP 꼬이면 필요).
2. `flash/run_gemm_test.bat` 1회 실행. xsct가 ① ps7 클럭(노-DDR)+FCLK0=30.3MHz ② 16×16 비트스트림 program ③ `configparams force-mem-access 1`+`memmap 0x40000000`로 PL-AXI 접근 허용 ④ RV32 reset→imem 32워드 로드→run ⑤ x10..x13 = C 결과 읽어 골든(39/53/17/23)과 PASS 비교.
3. 드라이버 변경 시: `/tmp/npu16_demo.s` 편집 → rv32_console.assemble로 워드 재생성 → jtag_gemm_test.tcl의 `prog` 리스트 교체.
- ctrl_axi 레지스터맵: `0x00` CTRL{b0 cpu_reset,b1 run_en}, `0x04` STATUS(b0 halted,b2 run_en), `0x08` IMEM_ADDR(바이트), `0x0C` IMEM_WDATA, `0x18` REG_ADDR, `0x1C` REG_RDATA, `0x20` PC, `0x2C` COMMIT_CNT.
- NPU 16×16 오프셋: A=0x3000_1000(+row*256+k*4), B=0x3000_2000(+col*256+k*4), C=0x3000_3000(+(i*16+j)*4); CTRL/STATUS/K_DIM=0x3000_0000/4/8; CTRL=0x3(start|clr_acc).
- **핵심 교훈**: XSDB로 PL-AXI(0x4000_0000) 접근하려면 `configparams force-mem-access 1` 필수 (없으면 "PL AXI slave ports access is not allowed").
- 보조 스크립트(생성됨): flash/jtag_program_only.tcl(프로그램만), flash/jtag_gemm_test.tcl(GEMM 검증).

## 주의/환경 (Gotchas)
- **좀비 프로세스**: 취소한 라우팅의 자식 vivado 프로세스가 "host 불일치"로 Vivado가 못 죽임 → 자기 라우팅 끝나면 자동 종료. impl_1은 Reset됨, synth_1(202 DSP)은 Complete 유지.
- **git 쓰기는 호스트 경유 필요**: sandbox 마운트가 `.git` 내부 파일 삭제 불가(FUSE EPERM). Jun 16자 stale `.git/*.lock`을 호스트에서 지운 뒤 커밋해야 함(=Vivado Tcl `exec cmd /c {bat}` 방식).
- Vivado: rv32_zynq 프로젝트 열려 있음, synth_1 완료, impl_1 reset 상태.
- 클럭 다운 시 PL 주변장치(uart_lite/SPI/I2C/PWM Pmod)의 클럭 분주값도 50/30 배율로 바뀜 — NPU 데모엔 무관(PS↔PL AXI는 핸드셰이크라 클럭 무관).
