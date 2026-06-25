# scripts/ — 빌드·검증·IP·구현 프로세스 스크립트

프로젝트를 재현하는 Vivado Tcl/배치 스크립트 모음. (Vivado 프로젝트가 자동 생성하는
`*.runs/`,`*.gen/` 내부 TCL과는 무관 — 그것들은 생성물이라 gitignore 대상.)

모든 스크립트는 절대경로(`C:/work/github/RV32-FullStack/...`)를 쓰므로 위치와 무관하게 동작한다.
배치 실행 예: `"C:\Xilinx\2025.2\Vivado\bin\vivado.bat" -mode batch -source scripts\<name>.tcl`

## HDL 회귀
- **run_all_xsim.bat** — 전 RTL 1회 컴파일 후 모든 단위/통합 SV TB를 일괄 elaborate+run.
  Vivado tools가 PATH에 있는 cmd에서 실행(`settings64.bat` 먼저).

## IP 패키징 (→ `ip_repo/`)
- **package_all_ip.tcl** — 코어 블록 30종(leaf 27 + 래퍼 icache_unit/cache_unit/rv32_core)을
  각각 user IP로 패키징.
- **package_bd_glue.tcl** — BD 손배선용 glue/레지스터 10종(mux2_32/mux3_32/orgate2/andn2/
  id_decode_glue/fencei_oneshot/ifid_reg/idex_reg/exmem_reg/memwb_reg) 패키징.
- **package_platform_ip.tcl** — `rv32_platform`(전체 PL 서브시스템, S_AXI 슬레이브)을 IP로 패키징.

## IP 메타데이터 정정
- **fix_icache_adapter_ip.tcl** — icache_axi_adapter IP의 오추론 AXI 인터페이스('c') 제거.
- **fix_cache_axi_iface.tcl** — icache_unit/cache_unit IP의 추론 AXI 인터페이스를 plain 핀으로
  (BD에서 메모리와 핀단위 연결하기 위함).

## 블록디자인 / 구현
- **build_rv32_bd.tcl** — (옵션) leaf IP들로 rv32_core를 손배선 재현하는 BD 빌드.
- **build_zynq_project.tcl** — 새 프로젝트 `vivado_zynq` + Zynq PS(Zybo 프리셋) + `rv32_platform`
  IP를 AXI로 연결한 BD + wrapper. (PREREQ: package_platform_ip.tcl)
- **run_bitstream.tcl** — GPIO XDC 추가 후 합성→구현→비트스트림 + 타이밍/자원 리포트.
  (PREREQ: build_zynq_project.tcl)

## 비트스트림까지 표준 순서
```
1) (필요시) package_platform_ip.tcl       # rv32_platform IP
2) build_zynq_project.tcl                 # Zynq BD + wrapper
3) run_bitstream.tcl                      # XDC + synth/impl/bitstream
```
제약 파일: `constraints/zybo_z7_20_gpio.xdc` (LED/SW/BTN 핀).
