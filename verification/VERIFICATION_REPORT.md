# RV32-FullStack — IF 스테이지 RTL 검증 리포트

대상: `ip_workspace/0_IF/` (PC 데이터패스 + Direct-Mapped 캐시 프론트엔드)
방법: 사이클 정확 참조 모델 기반 10회 반복 검증 (`verification/`)
결과: **수정 후 10/10 통과, 총 62,167 assertion green**

---

## 1. 요약 (TL;DR)

| 구분 | 통과 | Assertion | 상태 |
|---|---|---|---|
| 수정 전 (원본 RTL 모델, `--legacy`) | 8 / 10 | 62,166 | BUG-001 검출 |
| 수정 후 (현재 RTL 모델) | **10 / 10** | 62,167 | ALL GREEN |

10회 반복 검증 결과 **1건의 실제 버그(BUG-001: 리필 데이터 캡처 타이밍)** 를 발견하여 `cache_controller.vhd` 에 수정 적용했고, 그 외 구조적/프로토콜 동작은 모두 안정적임을 확인했다. 함께 **현재 구현 범위에서 누락된 동작 4건**을 식별해 (의도적 범위 제한 포함) 후속 과제로 정리했다.

---

## 2. 검증 방법 및 한계 (반드시 확인)

이 샌드박스에는 GHDL/Vivado xsim 등 HDL 시뮬레이터를 설치할 수 없어(루트 권한·패키지 저장소 접근 불가), 각 VHDL 엔티티를 **사이클 정확(cycle-accurate) Python 참조 모델**(`verification/models.py`)로 1:1 미러링하고, 테스트벤치(`verification/test_rv32.py`)로 결정론적으로 구동했다.

- 이 방식은 설계의 **논리·프로토콜·FSM 동작**을 검증한다.
- 다만 **합성/엘라보레이션 사인오프(타이밍, X-전파, 라이브러리 호환성)** 를 대체하지 않는다.
- 권장: 동일 시나리오를 GHDL(`ghdl -a/-e/-r`) 또는 Vivado xsim 테스트벤치로 1회 재확인.
- 정적 점검(Iter 01)은 모델이 아닌 **실제 `.vhd` 소스 파일**을 직접 파싱해 엔티티/아키텍처/버스폭/리셋 극성/FSM 상태 및 수정 반영 여부를 확인한다.

실행:
```bash
python3 verification/test_rv32.py            # 현재(수정본) 검증
python3 verification/test_rv32.py --legacy   # 원본 RTL 동작 재현(버그 확인용)
python3 verification/test_rv32.py --json r.json
```

---

## 3. 반복별 결과 (10 iterations)

| # | 반복(검증 항목) | 점검 수 | 수정 전 | 수정 후 |
|---|---|---|---|---|
| 01 | RTL 정적/엘라보레이션 sanity (엔티티·버스폭·리셋극성·FSM상태·수정마커) | 37 | PASS | PASS |
| 02 | `addr_aligner` 주소 필드 분해 (코너 + 2만 랜덤, 무손실 재구성) | 40,004 | PASS | PASS |
| 03 | `comparator` 히트 로직 (진리표 + 2만 랜덤) | 20,003 | PASS | PASS |
| 04 | PC 데이터패스 (`pc_adder`/`next_pc_mux`/`pc_reg`: 순차·stall·분기) | 8 | PASS | PASS |
| 05 | `tag_array` 저장/valid/reset (256라인 랜덤 5천회) | 6 | PASS | PASS |
| 06 | `cache_controller` 상태천이 커버리지 (5/5 상태, 전 엣지) | 41 | PASS | PASS |
| 07 | `cache_controller` 출력디코드 커버리지 (Moore 출력, arvalid/rready 상호배타) | 28 | PASS | PASS |
| 08 | 통합: miss→refill→hit (AXI 지연 {0,1,3}, stall 연속성/핸드셰이크 1회) | 30 | PASS | PASS |
| 09 | **리필 데이터 캡처 타이밍 (BUG-001 회귀)** | 2 | **FAIL** | PASS |
| 10 | 전체 리그레션 스윕 (Iter 02~09 재실행 + 풀패스 퍼즈 2천회) | 2,008 | FAIL | PASS |

> Iter 08(FSM·hit 로직)은 원본에서도 통과한다. 즉 상태머신과 태그/히트 판정 자체는 정상이며, 결함은 **리필 데이터 캡처 시점**에 국한된다(Iter 09에서 격리 검출).

---

## 4. 발견 결함 및 수정

### BUG-001 (수정 완료) — 리필 데이터가 RVALID 비활성 사이클에 캡처됨

- **파일:** `ip_workspace/0_IF/1_adress_split/cache_controller.vhd`
- **심각도:** High (기능 오류 — 캐시에 잘못된 데이터 적재)
- **증상:** 원본 FSM은 `we`(캐시 쓰기 enable)를 `S_UPDATE_CACHE` 상태에서 1로 구동한다. 그런데 AXI 읽기 데이터 핸드셰이크(`RVALID & RREADY`)는 한 사이클 앞선 `S_WAIT_R`에서 완료되고, 그 다음 사이클(`S_UPDATE_CACHE`)에는 슬레이브가 이미 `RVALID`를 내리고 `RDATA` 버스가 무효 상태가 된다. 따라서 데이터 어레이가 `we`로 래치하면 **유효 데이터 대신 직전/무효 버스값을 적재**한다.
- **검출:** Iter 09 불변식 — "`we`는 `RVALID=1`인 사이클에만 assert되어야 한다". 1워드 데이터 어레이 모델이 기대값 `0xCAFEF00D` 대신 센티넬 `0xDEADBEEF`를 래치함을 확인.

타이밍 비교 (지연=1 사이클 기준):

```
원본:  c2 WAIT_R(rdy)  c3 WAIT_R(rvalid=1)  c4 UPDATE(we=1, rvalid=0)  ← we가 데이터 무효 사이클에!
수정:  c2 WAIT_R(rdy)  c3 WAIT_R(rvalid=1, we=1)  c4 UPDATE(settle)      ← we가 데이터 유효 사이클에!
```

- **수정 내용:**
  1. `S_WAIT_R`에서 `we <= rvalid;` 로 구동 → 데이터가 유효한 바로 그 사이클(RVALID/RREADY 핸드셰이크)에 캡처.
  2. `S_UPDATE_CACHE`의 `we <= '1';` 제거 → 정착(settle) 사이클로만 유지(미스 패널티/지연 동일).
  3. 출력 디코드 프로세스 감도 목록에 `rvalid` 추가(`process(state_reg, miss, rvalid)`) → 시뮬/합성 불일치 방지.
- **회귀:** Iter 09/10 PASS, 그 외 9개 반복 무영향(리그레션 없음).

---

## 5. 누락 동작 / 후속 과제 (Operational gaps)

검증 중 식별한 미구현·제한 동작. (캐시는 폴더 `0_IF` 기준 **명령어 캐시(I-Cache, read-only)** 로 해석.)

1. **단일 비트 리필 (버스트 미지원)** — `addr_aligner`의 offset은 4비트(16B=4워드 라인)이지만, FSM/AXI 경로는 1워드만 리필한다. 라인 전체를 채우려면 `ARLEN/ARSIZE/RLAST` 기반 INCR 버스트와 워드 카운터가 필요. (기능 확장 권장)
2. **Data Array(SRAM) 및 Read MUX/Aligner 미구현** — offset[3:2] 워드 선택과 바이트/하프워드 정렬·부호확장(스펙 §3.4, §3.8) 모듈이 아직 리포지토리에 없음. 현재는 태그/히트 프론트엔드까지만 구현됨. (다음 단계 구현 대상)
3. **쓰기/Dirty/Write-Back 경로 없음** — I-Cache는 read-only이므로 의도적 제외로 판단(스펙의 B 채널·write-back은 데이터 캐시용). 데이터 캐시로 재사용 시 추가 필요.
4. **`tag_array` 태그 비트 미리셋** — reset 시 valid만 0으로 클리어(태그값은 미초기화). valid가 정합성을 보장하므로 기능상 안전하나, 시뮬레이션 X-전파 가시성을 위해 선택적 초기화 고려 가능.

---

## 6. 안정성 확인 항목 (PASS)

- FSM 5개 상태·전 입력 조합 엣지 100% 커버, 데드락/미정의 천이 없음.
- `arvalid`와 `rready` 동시 구동 없음(프로토콜 상호배타), 핸드셰이크 각 1회.
- 미스 처리 구간 `stall` 연속 유지(중간 버블/조기 해제 없음), `wake_up` 1회 펄스 후 IDLE 복귀.
- 리필된 라인은 stall 해제 시점에 정확히 hit로 서비스, 동일 주소 재접근 시 재미스 없음.
- PC: 선형 페치(+4), `stall` 시 동결, `pc_src` 분기 리다이렉트, 2^32 wrap 정상.
- 주소 필드 분해 무손실(2만 랜덤), 히트 로직 정확(2만 랜덤), 256라인 태그 어레이 정합(5천 랜덤).

---

## 7. 산출물

- `verification/models.py` — 7개 VHDL 엔티티의 사이클 정확 참조 모델.
- `verification/test_rv32.py` — 10회 반복 검증 테스트벤치(정적 점검 + 단위 + 통합 + 회귀).
- `verification/VERIFICATION_REPORT.md` — 본 리포트.
- 수정: `ip_workspace/0_IF/1_adress_split/cache_controller.vhd` (BUG-001).
