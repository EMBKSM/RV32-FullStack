# 문서 생성·확장·검증 리포트 (Movement + Phase 3~6)

요청: 미해결 파라미터 확정 → 단계별 문서 생성/분할 → **문서당 20회 재검증** → 결과 보고.
범위: 명세/문서/검증. **RTL 코딩 미수행.**
결과: **Movement.md 30/30 + Phase 3~6 각 20/20 = 총 110/110 iteration, 758 sub-check ALL GREEN.**

---

## 1. 요약

| 문서 | 역할 | iteration | sub-check |
|---|---|---|---|
| `Movement.md` | IP 블록 동작·**제어 진리표**·내부 데이터 이동 | 30/30 | 386 |
| `Dataflow_Architecture.md` | 데이터플로우·블록/타이밍 다이어그램·구조 결정 | 20/20 | 94 |
| `Interface_LockIn.md` | 프로토콜 정의·인터페이스 락·I/O 속도 정합 | 20/20 | 86 |
| `RTL_FSM_Placement.md` | FSM 상태/천이/실행 시퀀스(코딩 X) | 20/20 | 101 |
| `Verification_Handover.md` | 유닛 검증·타이밍 정합·핸드오버 | 20/20 | 91 |
| **합계** | | **110/110** | **758** |

검증 하네스: `verification/verify_docs.py` (문서당 20 iteration). 메인 스펙은 `verify_spec.py`(10/10, 451 sub-check)로 별도 검증.

---

## 2. 확정한 미해결 파라미터 및 근거

사용자 결정(AXI 32-bit) + 합리적 할당. 상세는 `Movement.md` §1, 메인 스펙 §13.1.

| 파라미터 | 확정값 | 근거(요지) |
|---|---|---|
| AXI 데이터 폭 | **32-bit** (`xSIZE=010`) | 사용자 결정(32-bit CPU). XLEN=32와 동일 → 폭 변환 불필요 |
| 캐시 사상/용량/라인/라인수 | Direct-Mapped / 4 KB / 16 B / 256 | `addr_aligner.vhd` 비트 분할(tag20/idx8/off4)에서 **역산된 강제값**(임의 아님) |
| 라인 리필 | 4-beat INCR 버스트(`ARLEN=3`) | 단일 비트 → 라인 버스트 확장(노트 권고 반영) |
| `Wake up` 출처 | 읽기=`RLAST`, 쓰기=`BVALID` 채널 완료 OR | AXI 표준 완료 마커, 통합 done 불필요 |
| 분기 해소 | EX 스테이지, 2-bubble, 정적 not-taken | 노트 결정 |
| D-Cache 쓰기 | Write-Back+Write-Allocate, Dirty 1b, B 채널 필수 | MEM 정책(§8.9.5) |
| `RESET_ADDR` | `0x0000_0000` | `pc_reg` generic, 베어메탈 부트벡터 |
| 목표 클럭 | 100 MHz *(계획 가정)* | Zybo Z7 PL 동작점, 타이밍 기준 |
| 레지스터 파일 | 32×32, 2R/1W, x0=0, write-first | 표준, WB→ID RAW 회피 |

> 핵심: 캐시 기하구조는 임의 가정이 아니라 **이미 구현된 `addr_aligner.vhd`가 강제하는 유일 해**다.

---

## 3. 문서당 20 iteration 검증 항목

공통 12 + 문서별 8 = 20. 각 iteration은 다수의 sub-check를 포함한다.

| # | 검증 항목 | # | 검증 항목 |
|---|---|---|---|
| 01 | 최소 분량 | 11 | H2 번호 연속성 |
| 02 | H1 제목 1개 | 12 | 확정 파라미터 키워드 |
| 03 | H2 섹션 수 | 13 | 신호명 사용 |
| 04 | H2 본문 존재 | 14 | 필수 섹션 커버리지 |
| 05 | 표 열 수 일관성 | 15 | 필수 주제 커버리지 |
| 06 | 셀 내부 파이프 | 16 | IP/FSM/자산 블록 커버리지 |
| 07 | 플레이스홀더 없음 | 17 | 표 최소 개수 |
| 08 | 리셋 관례(active-high) | 18 | 문서별 핵심 문구 |
| 09 | AXI 32-bit 확정·64-bit 부재 | 19 | 범위 명시(RTL 코딩 제외) |
| 10 | 캐시 기하 일관성 | 20 | 일관성·코드펜스·줄길이 |

---

## 4. 검증 중 발견·수정

| 문서 | 발견 | 수정 |
|---|---|---|
| Movement.md | 표 3개 미만(2개) | 블록별 지연·버퍼 분류 요약 표(§10) 추가 |
| Phase3 | 표 3개 미만(§6 속도가 불릿) | §6 처리율 표 + §7.1 구조 결정 요약 표로 보강 |

그 외 문서는 초안에서 20/20 통과. 모든 문서에서 `rst_n`/`active-low`/`64-bit`(확정값) 미사용, 32-bit·캐시 기하·리셋 관례 일관성, 마크다운 표 무결성, "RTL 코딩 미수행" 범위 명시를 확인했다.

---

## 5. 생성 문서 구성(설계 워크플로우 정렬)

- **Movement.md** — 각 IP 블록의 동작·데이터 이동(진입/이탈 시점, comb/seq, 버퍼 유무).
- **Phase 3** — 연결성 매트릭스(Producer→Consumer), 데이터플로우 타이밍, 블록/타이밍 다이어그램, 구조 결정(임계경로·버퍼·I/O 균형).
- **Phase 4** — AXI4/Ready-Valid/UART-TLV 프로토콜 확정, 신호 레벨 락 테이블, I/O 속도 병목(UART) 식별·정합.
- **Phase 5** — FSM 인벤토리(캐시·AXI R/W·UART RX) 상태/천이/출력, 실행 시퀀스(성능·전력), "FSM은 결과물" 원칙.
- **Phase 6** — 점증적 유닛 검증(U1~U7), 파이프라인 타이밍 정합, 검증 매트릭스·회귀·커버리지, 검증팀 핸드오버 묶음.

---

## 6. 재현 방법

```bash
python3 verification/verify_docs.py            # 5문서 × 20 iteration
python3 verification/verify_docs.py phase3     # 단일 문서
python3 verification/verify_spec.py            # 메인 스펙 10 iteration
```


---

## 7. 개정 — Movement.md 제어 동작 극상세화 (+30 iteration)

요청에 따라 `Movement.md`를 **모든 조합 로직을 조건/선택 진리표로** 전면 확장하고, 검증을 **30 iteration**으로 강화했다(공통 20 + 전용 10).

추가된 상세 제어표(전용 검증 21~30으로 완전성 확인):
- ALU 연산표(11종) + zero 플래그, ALU Control 완전 디코드표(`alu_op`×`funct3`×`funct7[5]`).
- 분기 조건표(BEQ~BGEU 6종) + `pc_src = jump OR (branch AND cond_met)` 진리표 + target 선택.
- Decoder 전체 제어표(9 opcode × reg_write/src_a/alu_src/mem_read/mem_write/branch/jump/alu_op/result_src).
- 즉치 포맷 선택표(I/S/B/U/J 비트 구성), 로드 추출·확장표(LB/LH/LW/LBU/LHU × byte_off), `wstrb` 생성표(SB/SH/SW × byte_off).
- 포워딩 선택표(`forward_a/b`, EX/MEM>MEM/WB>RF 우선순위), Hazard 검출 조건표.
- 캐시 컨트롤러 FSM 다음상태·출력표(Mealy `we=rvalid`) + D-Cache write-back FSM(AW/W/B/AR/R) + AXI 핸드셰이크 조건표.
- PC/파이프라인 레지스터 제어 우선순위표(reset > flush > stall > load), 제어신호 종합 교차표.

> 참고: 사용자가 언급한 첨부 이미지는 세션에 도착하지 않아(업로드 폴더 비어 있음) 반영하지 못했다. 본 확장은 구현 RTL·기존 명세에 근거했으며, 이미지를 다시 첨부하면 대조·보강 가능하다.

**재검증 결과: Movement.md 30/30, Phase 3~6 각 20/20 = 총 110/110 iteration ALL GREEN.**


---

## 8. 개정 — BCU 추가 · Forwarding/Hazard Unit 전 문서 보강 · 데이터플로우 강화

지적 사항을 감사(audit)한 결과, **`BCU`는 전 문서에서 0회**, **Forwarding Unit은 Phase 3/4/5/6에서 누락**이었다. 다음과 같이 보강했다.

**1) BCU(Branch Comparison Unit) 1급 컴포넌트화 — 전 6개 문서:**
- 메인 스펙 §6.4를 `Branch Unit` → **BCU**로 정식화(전용 비교기, ALU 분리, `a_fwd/b_fwd/funct3/branch/jump/is_jalr` 입력, `branch_taken/pc_src/target_addr` 출력).
- Phase 4 §4.4에 **BCU 인터페이스 락 테이블** 추가(사용자 지적 "인터페이스에서 BCU 누락" 해소).
- Movement·Phase 3·5·6에 BCU 명시(블록/데이터플로우/조합유닛/검증 항목).

**2) Forwarding Unit · Hazard Unit 전 문서 보강:**
- 메인 스펙 §6.5(Forwarding Unit & MUX, 우선순위 EX/MEM>MEM/WB>RF)·§6.6(Hazard Unit) 추가.
- Phase 3/4/5/6에 누락돼 있던 Forwarding Unit·Hazard Unit을 인터페이스·데이터플로우·조합유닛·검증 매트릭스로 추가.

**3) 데이터플로우 대폭 강화(Phase 3):**
- 연결성 매트릭스에 `forward_a/b`·바이패스 경로·`branch_taken/pc_src`·해저드 stall 추가.
- 블록 다이어그램에 Forwarding MUX·BCU·바이패스 피드백 경로 반영.
- 신규 §8 EX 바이패스 네트워크(선택 생성·경로·사이클 예), §9 분기 해소 데이터플로우(BCU), §10 해저드 전파(stall/flush 발생원·전파·우선순위) 추가(113→210줄).

**4) 검증 강화:** `verify_docs.py`가 이제 **전 문서에서 BCU·Forwarding Unit·Hazard Unit 존재를 필수 검증**한다(누락 재발 방지). `verify_spec.py` 컴포넌트 커버리지에도 BCU/Forwarding Unit/Hazard Unit 추가.

**재검증 결과: Movement 30/30 + Phase 3~6 각 20/20 = 총 110/110 iteration(813 sub-check), 메인 스펙 10/10 ALL GREEN.** 보강 후 감사에서 6개 문서 전부 BCU/Forwarding Unit/Hazard Unit 포함을 확인했다.
