# Session Handoff — GPU + Multicore + Timing Closure

_저장: 2026-06-26 ~10:54, 갱신: 2026-06-28. (이전 NPU Fmax 핸드오프는 `docs/HANDOFF.md` 참고.)_

> **✅ 해결됨 (2026-06-28): GPU 타이밍 100 MHz MET — WNS +0.032 ns, 실패 EP 0/7825.**
> 결정타는 BRAM 행 인덱스 레지스터링(`ld_row_r`, VLD 3사이클/VST 2사이클)으로 BRAM 주소핀을
> fetch→스칼라가산기 경로에서 분리한 것. 최종 limiter = SADDI 스칼라 가산기. 상세는 `docs/GPU_DESIGN.md` §11.
> 아래 §6 추가수정은 더 이상 불필요(참고용). 남은 일: 커밋/푸시(아래 §4 절차)뿐.

---

## 0. 재개 시 제일 먼저 할 것

1. **GPU 최종 타이밍 결과 읽기** (impl이 끝났을 수 있음):
   - `C:\work\github\RV32-FullStack\_gpu_timing.rpt` 열기.
   - 4행 `| Date :` 확인 — **10:44:56 이후**면 새 런(파이프라인+Explore+phys_opt). 아직 `10:40:16`이면 미완 → impl 프로세스 확인/재실행(§3).
   - **Design Timing Summary** 표(~139–141행)에서 `WNS / TNS` 읽기.
2. **판단:**
   - **WNS ≥ 0 → 타이밍 MET.** §4(커밋+푸시), §5(문서 갱신).
   - **WNS < 0 (작게, 예: ≥ −0.3) →** §6 추가 수정 하나 적용 후 재-impl(§3).
3. 결과와 무관하게: **파이프라인 리팩터(미커밋) 커밋** + **로컬 전용 `cb8da85` 푸시**(§4).

---

## 1. 현재 상태

프로젝트(RV32I 5단 코어 + INT8 16×16 시스톨릭 NPU, Zybo Z7-20 / XC7Z020-CLG400-1, Vivado 2025.2)는 빌드·재구성·푸시 완료. 이번 세션은 **GPU**와 **멀티코어**를 추가하고 **GPU 타이밍을 닫는 중.**

**완료+푸시됨** (GitHub `EMBKSM/RV32-FullStack`, `main`):
- 커밋 정리 `1d4048e` · 레포 재구성 `6f5604a` · GPU `0c3fbd6` · 듀얼코어 `44805d3` · sim 런처 `077d615`

**로컬 전용(미푸시):** `cb8da85` `refactor(gpu): 16x16 DSP multiply per lane (was 32x32 LUT) + synth notes`

**미커밋 작업분(타이밍 클로징):**
- `rtl/gpu/gpu_core.vhd` — **파이프라인화**(3사이클 벡터-ALU FSM; DSP 고립). **핵심 변경.**
- `sim/gpu/tb_gpu.vhd` — 레지스터드 스크래치패드 읽기 타이밍(검증 PASS).
- `sim/gpu/gpu_ooc.xdc` — `create_clock 10ns (100 MHz)`.
- `sim/gpu/synth_impl_gpu.tcl` — synth `-retiming` + `place/route -directive Explore` + `phys_opt_design -directive AggressiveExplore`.

**검증 상태:** GPU C 골든 PASS; **xsim(Vivado) 3커널 ALL PASS**(vector_add/saxpy/relu) — 파이프라인 RTL 기준. 멀티코어 C+xsim PASS.

---

## 2. 타이밍 여정 (GPU OOC @ 100 MHz, XC7Z020-1)

| 단계 | WNS | 비고 |
|---|---|---|
| 조합형 스크래치패드(2D reg) | — | 스크래치패드가 65,536 FF로 추론 — impl 부적합 |
| BRAM 스크래치패드 + 32×32 LUT 곱 | — | synth ~16분, ~16k LUT — 곱셈 비현실적 |
| BRAM + **16×16 DSP** 곱 (단일사이클 exec) | **−3.975 ns** | 임계경로 `pc→imem→operand→**조합 DSP(3.84ns)**→result-mux→vreg`, route 8.5ns |
| **+ 파이프라인**(3사이클 ALU: S_RUN→S_EX→S_WB, DSP 고립) | **−0.338 ns** | 대폭 개선; 실패 EP 4237→64 |
| **+ retiming + Explore place/route + AggressiveExplore phys_opt** | **(실행중 — `_gpu_timing.rpt` 확인)** | retiming이 operand 레지스터를 DSP **AREG/BREG/CREG**로 흡수(`A'*B'`). post-place 추정 −0.972(라우팅 전), 최종 미정. |

**리소스(파이프라인, post-synth):** ~9k LUT, ~2.3k FF, **8 RAMB18**, **16 DSP**(레인당 2: VMUL+VMAC). XC7Z020 여유 충분.

---

## 3. GPU impl 실행 방법 (헤드리스 — GUI 프로젝트 아님)

> GUI `rv32_zynq` 프로젝트의 `synth_1/impl_1`이 "Out-of-date" WNS −0.065로 보이는 건 **RV32+NPU SoC**(GPU와 무관). 재구성으로 소스 경로가 바뀌어 out-of-date 표시되는 것. 그 디자인은 이전에 post-route phys_opt로 **+0.003 @106 MHz** 달성함.

GPU는 **out-of-context(OOC)**로, **별도 헤드리스 `vivado -mode batch`** 프로세스에서 합성(=GUI 우상단 진행바에 안 뜸):
- 스크립트 `sim/gpu/synth_impl_gpu.tcl`: read_vhdl(gpu_pkg/lane/core/top) → read_xdc(gpu_ooc.xdc) → synth OOC `-retiming` → opt → place Explore → route Explore → `phys_opt_design -directive AggressiveExplore` → `report_utilization`/`report_timing_summary` → `_gpu_*.rpt`.
- 런처 `_gpu_impl.bat`(settings64.bat 호출 → tcl 실행 → `_gpu_impl_out.txt` 로깅). xsim까지 재실행하려면 `_gpu_full.bat`.

**실행** (GUI 하단 **Tcl Console** 입력창):
```tcl
exec cmd /c C:/work/github/RV32-FullStack/_gpu_impl.bat &
```
PID 출력 후 백그라운드 실행(Explore+AggressiveExplore라 ~10–13분). `_gpu_timing.rpt` Date가 갱신되면 완료.

> **함정:** Tcl Console 입력 클릭이 잘 안 잡힘 — 스크린샷으로 명령이 입력창에 들어갔는지 확인(예전에 `1 &`만 들어간 적). 안 맞으면 Ctrl+A/Delete 후 재입력.

> **마운트 지연:** sandbox의 `C:\work\...` 뷰가 수 분 지연. `_gpu_timing.rpt`/`_gpu_impl_out.txt`는 **Read 툴**(호스트=정답)로 읽기, sandbox `cat`/`grep` 금지.

---

## 4. 커밋 + 푸시 절차 (호스트 전용)

sandbox는 git 인덱스 쓰기 불가(`.git/index` 손상). 모든 git은 **호스트**에서 `.bat`을 Tcl Console(`exec cmd /c <bat> &`)이나 파일탐색기 주소창으로 실행.

**커밋 대상(파이프라인 타이밍 클로징):**
```
git add rtl/gpu/gpu_core.vhd sim/gpu/tb_gpu.vhd sim/gpu/gpu_ooc.xdc sim/gpu/synth_impl_gpu.tcl
git commit -m "perf(gpu): pipeline vector-ALU (3-cycle, DSP isolated) -> 100 MHz timing closure"
```
본문 권장: WNS −3.975 → (최종) ns @100 MHz; retiming→DSP AREG/BREG; 8 RAMB18 / 16 DSP.

**푸시**(로컬 전용 `cb8da85`도 함께 올라감):
```
git push origin main
```
> **CredentialHelperSelector** 매 푸시마다 팝업(ESP-IDF git이 `<no helper>`). **"manager"** 선택 후 **Select** — 캐시된 GitHub 자격증명 사용. **비밀번호 입력 금지**(경계 규칙). 공개 레포 force-push는 사용자 명시 동의 필요(일반 push는 OK).

`.bat`을 `_gc_push.bat`에 쓰고 `exec cmd /c .../_gc_push.bat &` → 로그에서 새 커밋 해시 + `main -> main` 확인.

---

## 5. MET 후 갱신할 문서 (현재 stale)

`docs/GPU_DESIGN.md`가 **초기(sim-first)** 설계 기준이라 일부 틀림:
- §1 "lanes LUT-based, `use_dsp=no`, 0 DSP" → 실제 **16×16 DSP, 16 DSP 사용**.
- §5/§9 "조합 단일사이클 스크래치패드 / BRAM은 다음" → 실제 **8 RAMB18 BRAM + 3사이클 파이프라인 벡터 ALU, 타이밍 클로즈**.
- 최종 **WNS/Fmax** + `_gpu_util.rpt` 리소스표 추가. (§9 확장 또는 §11 "Timing closure" 신설, §2 여정표 반영.)

---

## 6. 아직 MET 아니면 — 다음 수정 (레버리지 순)

1. **BRAM 출력 레지스터(VLD 경로).** synth 경고 `[Synth 8-7052]` 반복: 뱅크 RAM에 출력 레지스터 없음. 2단 읽기로 `bank_dout`를 한 번 더 레지스터링하고 `VLD`를 **3사이클**(S_RUN→S_VLD2→S_VLD3)로 → BRAM 옵션 출력 레지스터 흡수, `bank_dout→vreg` 경로 절단.
2. **imem fetch 레지스터링.** `imem`이 분산 RAM(RAM64M×44) 조합 읽기. fetch 레지스터 추가(시작 1사이클 증가) → `pc→imem→decode` 절단.
3. **DSP MREG/PREG.** retiming이 AREG/BREG 설정함; `res_r`를 DSP **PREG**로 밀어넣기(곱셈과 `res_r` 사이 로직 제거).
4. **클럭 완화.** GPU는 throughput 코프로세서 — `gpu_ooc.xdc`를 **~70 MHz(14.3ns)**로 두면 쉽게 MET, GPU 전용/분주 클럭 도메인이면 현실적. 최후 수단.

각 수정 → xsim 재검증(`_gpu_full.bat`) → 재-impl(`_gpu_impl.bat`) → `_gpu_timing.rpt` 확인.

---

## 7. 환경 핵심

- **Vivado/Vitis 2025.2.** `settings64.bat` = `C:\Xilinx\2025.2\Vivado\settings64.bat`. GUI 프로젝트 `vivado_zynq\rv32_zynq.xpr`(gitignored).
- **`open_application Vivado` 금지** — 깨진 2번째 unwrapped 인스턴스(`xv_commonmain.dll` 없음)가 뜸. 열려있는 GUI의 Tcl Console 또는 헤드리스 배치 사용.
- **sandbox 한계:** mkdir/mv/write/read + read-only git(`git ls-tree -r --name-only HEAD`) 가능; 삭제·git 인덱스 쓰기 **불가**. sandbox 내 HDL 시뮬 불가(ghdl/verilator 없음; C 골든은 gcc OK). 네트워크 403.
- **파일(호스트 경로):** RTL `rtl/gpu/{gpu_pkg,gpu_lane,gpu_core,gpu_top}.vhd`; sim `sim/gpu/{gpu_model.c,tb_gpu.vhd,gpu_ooc.xdc,synth_impl_gpu.tcl}`; 멀티코어 `rtl/soc/{rv32_shared,rv32_dual}.vhd`, `sim/multicore/*`.
- 레포 루트의 `_*.bat`/`_*.txt`/`_*.rpt`는 **gitignored**(커밋 금지).

---

## 8. 태스크 상태

완료 #1–#16. **진행중 #17 — GPU 타이밍 MET 클로징(반복).** ← 여기서 재개(`_gpu_timing.rpt` 읽고 → 커밋/푸시 또는 §6 적용).
