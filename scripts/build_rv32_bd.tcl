# =====================================================================
# build_rv32_bd.tcl  -  script-build the full RV32 SoC block design
# Core (rv32_core) is rebuilt from leaf IPs + glue/registers; I$/D$ use the
# icache_unit/cache_unit IPs; memory uses axi_slave_mem (module reference).
# Mirrors rv32_soc. Equivalent to BD_CONNECTIONS.md, but scripted.
#
# PREREQ (once):
#   1) ip_repo packaged (package_all_ip.tcl + package_bd_glue.tcl)
#   2) fix_cache_axi_iface.tcl run  (icache_unit/cache_unit AXI -> plain pins)
# RUN inside an OPEN project (its part is used), e.g. in the rv_pl Tcl Console:
#   set_property ip_repo_paths C:/work/github/RV32-FullStack/ip_repo [current_project]
#   update_ip_catalog -rebuild
#   source C:/work/github/RV32-FullStack/build_rv32_bd.tcl
# =====================================================================
set BD   RV32_SoC
set RTL  C:/work/github/RV32-FullStack/ip_workspace

# module references (axi_slave_mem) need AUTOMATIC source management,
# otherwise: "Module references are not supported in manual compile order mode"
set_property source_mgmt_mode All [current_project]

# axi_slave_mem is a module reference -> its RTL must be in the project
add_files -norecurse -quiet $RTL/3_Mem/axi_slave_mem.vhd
update_compile_order -fileset sources_1

# remove any previous (partial) build of this BD so we can recreate cleanly
catch { close_bd_design -quiet [get_bd_designs -quiet $BD] }
set _old [get_files -quiet ${BD}.bd]
if {[llength $_old]} { remove_files -quiet $_old }
file delete -force C:/work/github/RV32-FullStack/rv_pl/rv_pl.srcs/sources_1/bd/$BD

create_bd_design $BD
current_bd_design [get_bd_designs $BD]

# ---------- helpers ----------
proc ip  {name vlnv} { create_bd_cell -type ip -vlnv $vlnv $name }
proc mod {name ref}  { create_bd_cell -type module -reference $ref $name }
proc N {args} {     ;# connect one net across pins; prefix an external port with "P:"
  set objs {}
  foreach a $args {
    if {[string match P:* $a]} {
      lappend objs [get_bd_ports [string range $a 2 end]]
    } else {
      lappend objs [get_bd_pins $a]
    }
  }
  connect_bd_net {*}$objs
}
proc U {vlnv} { return user:rv32:$vlnv:1.0 }

# ---------- cells: core leaf IPs ----------
ip pc_reg_0          [U pc_reg]
ip pc_adder_0        [U pc_adder]
ip next_pc_mux_0     [U next_pc_mux]
ip control_unit_0    [U control_unit]
ip imm_gen_0         [U imm_gen]
ip register_file_0   [U register_file]
ip hazard_unit_0     [U hazard_unit]
ip alu_control_0     [U alu_control]
ip alu_0             [U alu]
ip bcu_0             [U bcu]
ip forwarding_unit_0 [U forwarding_unit]
ip csr_file_0        [U csr_file]
ip trap_unit_0       [U trap_unit]
ip read_aligner_0    [U read_aligner]
ip write_strobe_gen_0 [U write_strobe_gen]
ip result_mux_0      [U result_mux]

# ---------- cells: glue / pipeline registers ----------
ip ifid_reg_0        [U ifid_reg]
ip idex_reg_0        [U idex_reg]
ip exmem_reg_0       [U exmem_reg]
ip memwb_reg_0       [U memwb_reg]
ip id_decode_glue_0  [U id_decode_glue]
ip fencei_oneshot_0  [U fencei_oneshot]
ip mux2_redirect     [U mux2_32]
ip mux2_csrwdata     [U mux2_32]
ip mux2_alua         [U mux2_32]
ip mux2_alub         [U mux2_32]
ip mux3_fa           [U mux3_32]
ip mux3_fb           [U mux3_32]
ip orgate2_redirect  [U orgate2]
ip orgate2_corestall [U orgate2]
ip orgate2_bubble    [U orgate2]
ip orgate2_memstall  [U orgate2]
ip orgate2_dreq      [U orgate2]
ip andn2_csrwe       [U andn2]
ip andn2_mret        [U andn2]
ip andn2_trapwe      [U andn2]
ip andn2_traptaken   [U andn2]

# ---------- cells: caches + memory ----------
ip  icache_unit_0  [U icache_unit]
ip  cache_unit_0   [U cache_unit]
mod imem axi_slave_mem
mod dmem axi_slave_mem

# ---------- stock util IPs ----------
ip xlslice_byteoff xilinx.com:ip:xlslice:1.0
set_property -dict {CONFIG.DIN_WIDTH 32 CONFIG.DIN_FROM 1 CONFIG.DIN_TO 0 CONFIG.DOUT_WIDTH 2} [get_bd_cells xlslice_byteoff]
ip const0_1b  xilinx.com:ip:xlconstant:1.1
set_property -dict {CONFIG.CONST_WIDTH 1  CONFIG.CONST_VAL 0} [get_bd_cells const0_1b]
ip const0_32b xilinx.com:ip:xlconstant:1.1
set_property -dict {CONFIG.CONST_WIDTH 32 CONFIG.CONST_VAL 0} [get_bd_cells const0_32b]

# ---------- external ports ----------
create_bd_port -dir I clk
create_bd_port -dir I reset
create_bd_port -dir I imem_prog_we
create_bd_port -dir I -from 31 -to 0 imem_prog_addr
create_bd_port -dir I -from 31 -to 0 imem_prog_data
create_bd_port -dir I dmem_prog_we
create_bd_port -dir I -from 31 -to 0 dmem_prog_addr
create_bd_port -dir I -from 31 -to 0 dmem_prog_data

# ---------- clk / reset fanout ----------
foreach c {pc_reg_0 ifid_reg_0 register_file_0 csr_file_0 idex_reg_0 fencei_oneshot_0 \
           exmem_reg_0 memwb_reg_0 icache_unit_0 cache_unit_0 imem dmem} {
  N P:clk $c/clk
  N P:reset $c/reset
}

# ================= IF =================
N pc_reg_0/pc        pc_adder_0/pc_in ifid_reg_0/pc_in icache_unit_0/addr
N pc_adder_0/pc_out  next_pc_mux_0/pc_plus_4 ifid_reg_0/pc4_in
N next_pc_mux_0/next_pc pc_reg_0/next_pc
N mux2_redirect/y    next_pc_mux_0/target_addr
N bcu_0/target_addr  mux2_redirect/d0
N trap_unit_0/trap_target mux2_redirect/d1
N andn2_traptaken/y  mux2_redirect/sel orgate2_redirect/b
N bcu_0/pc_src       orgate2_redirect/a
N orgate2_redirect/y next_pc_mux_0/pc_src ifid_reg_0/flush orgate2_bubble/a
N orgate2_corestall/y pc_reg_0/stall
N hazard_unit_0/stall orgate2_corestall/a ifid_reg_0/load_use_stall orgate2_bubble/b
N icache_unit_0/rword ifid_reg_0/instr_in

# ================= ID =================
N ifid_reg_0/ifid_instr imm_gen_0/instr id_decode_glue_0/instr
N ifid_reg_0/ifid_pc    idex_reg_0/pc_in
N ifid_reg_0/ifid_pc4   idex_reg_0/pc4_in
N id_decode_glue_0/opcode      control_unit_0/opcode imm_gen_0/opcode
N id_decode_glue_0/funct3      control_unit_0/funct3 idex_reg_0/funct3_in
N id_decode_glue_0/instr_31_20 control_unit_0/instr_31_20 idex_reg_0/csr_addr_in
N id_decode_glue_0/rs1  register_file_0/a1 hazard_unit_0/if_id_rs1 idex_reg_0/rs1_in
N id_decode_glue_0/rs2  register_file_0/a2 hazard_unit_0/if_id_rs2 idex_reg_0/rs2_in
N id_decode_glue_0/rd        idex_reg_0/rd_in
N id_decode_glue_0/funct7_5  idex_reg_0/funct7_5_in
N id_decode_glue_0/jalr      idex_reg_0/jalr_in
N id_decode_glue_0/zimm      mux2_csrwdata/d1
N id_decode_glue_0/csr_we    idex_reg_0/csr_we_in
N control_unit_0/csr_use_imm mux2_csrwdata/sel id_decode_glue_0/csr_use_imm
N control_unit_0/csr_cmd     idex_reg_0/csr_cmd_in id_decode_glue_0/csr_cmd
N imm_gen_0/imm              idex_reg_0/imm_in
N register_file_0/rd1        mux2_csrwdata/d0 idex_reg_0/rs1d_in
N register_file_0/rd2        idex_reg_0/rs2d_in
N mux2_csrwdata/y            idex_reg_0/csr_wdata_in
N orgate2_bubble/y          idex_reg_0/bubble
# control_unit -> idex_reg control inputs
N control_unit_0/reg_write  idex_reg_0/reg_write_in
N control_unit_0/mem_read   idex_reg_0/mem_read_in
N control_unit_0/mem_write  idex_reg_0/mem_write_in
N control_unit_0/alu_src    idex_reg_0/alu_src_in
N control_unit_0/src_a_sel  idex_reg_0/src_a_sel_in
N control_unit_0/branch     idex_reg_0/branch_in
N control_unit_0/jump       idex_reg_0/jump_in
N control_unit_0/alu_op     idex_reg_0/alu_op_in
N control_unit_0/result_src idex_reg_0/result_src_in
N control_unit_0/csr_to_reg idex_reg_0/csr_to_reg_in
N control_unit_0/is_ecall   idex_reg_0/is_ecall_in
N control_unit_0/is_ebreak  idex_reg_0/is_ebreak_in
N control_unit_0/is_mret    idex_reg_0/is_mret_in
N control_unit_0/is_fence_i idex_reg_0/is_fence_i_in
N control_unit_0/illegal    idex_reg_0/illegal_in

# ================= EX =================
N idex_reg_0/idex_rs1 forwarding_unit_0/id_ex_rs1
N idex_reg_0/idex_rs2 forwarding_unit_0/id_ex_rs2
N idex_reg_0/idex_mem_read hazard_unit_0/id_ex_mem_read
N idex_reg_0/idex_rd  hazard_unit_0/id_ex_rd
N forwarding_unit_0/forward_a mux3_fa/sel
N forwarding_unit_0/forward_b mux3_fb/sel
N idex_reg_0/idex_rs1d mux3_fa/d_reg
N idex_reg_0/idex_rs2d mux3_fb/d_reg
N mux3_fa/y mux2_alua/d0 bcu_0/a_fwd bcu_0/rs1_fwd
N mux3_fb/y mux2_alub/d0 bcu_0/b_fwd exmem_reg_0/store_in
N idex_reg_0/idex_pc  mux2_alua/d1 bcu_0/pc trap_unit_0/instr_pc trap_unit_0/fault_addr
N idex_reg_0/idex_imm mux2_alub/d1 bcu_0/imm
N idex_reg_0/idex_src_a_sel mux2_alua/sel
N idex_reg_0/idex_alu_src   mux2_alub/sel
N mux2_alua/y alu_0/a
N mux2_alub/y alu_0/b
N idex_reg_0/idex_alu_op   alu_control_0/alu_op
N idex_reg_0/idex_funct3   alu_control_0/funct3 bcu_0/funct3 exmem_reg_0/funct3_in
N idex_reg_0/idex_funct7_5 alu_control_0/funct7_5
N alu_control_0/alu_ctrl   alu_0/alu_ctrl
N alu_0/result            exmem_reg_0/alu_result_in
N idex_reg_0/idex_branch  bcu_0/branch
N idex_reg_0/idex_jump    bcu_0/jump
N idex_reg_0/idex_jalr    bcu_0/is_jalr
# CSR / trap
N idex_reg_0/idex_csr_addr  csr_file_0/csr_addr
N idex_reg_0/idex_csr_cmd   csr_file_0/csr_cmd
N idex_reg_0/idex_csr_wdata csr_file_0/csr_wdata
N idex_reg_0/idex_csr_we    andn2_csrwe/a
N idex_reg_0/idex_is_mret   andn2_mret/a trap_unit_0/is_mret
N idex_reg_0/idex_illegal   trap_unit_0/illegal_instr
N idex_reg_0/idex_is_ecall  trap_unit_0/is_ecall
N idex_reg_0/idex_is_ebreak trap_unit_0/is_ebreak
N idex_reg_0/idex_is_fence_i fencei_oneshot_0/is_fence_i
N andn2_csrwe/y     csr_file_0/csr_we
N andn2_mret/y      csr_file_0/is_mret
N andn2_trapwe/y    csr_file_0/trap_we
N trap_unit_0/trap_we     andn2_trapwe/a
N trap_unit_0/trap_taken  andn2_traptaken/a
N trap_unit_0/trap_mepc   csr_file_0/trap_mepc
N trap_unit_0/trap_mcause csr_file_0/trap_mcause
N trap_unit_0/trap_mtval  csr_file_0/trap_mtval
N csr_file_0/csr_rdata exmem_reg_0/csr_rdata_in
N csr_file_0/mtvec_o   trap_unit_0/mtvec
N csr_file_0/mepc_o    trap_unit_0/mepc
N idex_reg_0/idex_csr_to_reg exmem_reg_0/csr_to_reg_in
# exmem_reg remaining
N idex_reg_0/idex_pc4        exmem_reg_0/pc4_in
N idex_reg_0/idex_reg_write  exmem_reg_0/reg_write_in
N idex_reg_0/idex_mem_write  exmem_reg_0/mem_write_in cache_unit_0/we orgate2_dreq/a
N idex_reg_0/idex_mem_read   exmem_reg_0/mem_read_in
N idex_reg_0/idex_result_src exmem_reg_0/result_src_in
N idex_reg_0/idex_rd         exmem_reg_0/rd_in
# const0 -> trap misalign + result_mux.csr_to_reg + icache ext_inv
N const0_1b/dout trap_unit_0/instr_misalign trap_unit_0/load_misalign trap_unit_0/store_misalign result_mux_0/csr_to_reg icache_unit_0/ext_inv

# ================= MEM =================
N exmem_reg_0/exmem_alu_result cache_unit_0/addr xlslice_byteoff/Din mux3_fa/d_exmem mux3_fb/d_exmem memwb_reg_0/alu_result_in
N exmem_reg_0/exmem_reg_write forwarding_unit_0/ex_mem_reg_write memwb_reg_0/reg_write_in
N exmem_reg_0/exmem_rd        forwarding_unit_0/ex_mem_rd memwb_reg_0/rd_in
N exmem_reg_0/exmem_mem_read  orgate2_dreq/b
N orgate2_dreq/y              cache_unit_0/req
N exmem_reg_0/exmem_store     write_strobe_gen_0/store_data
N exmem_reg_0/exmem_funct3    read_aligner_0/funct3 write_strobe_gen_0/funct3
N xlslice_byteoff/Dout        read_aligner_0/byte_off write_strobe_gen_0/byte_off
N cache_unit_0/rword          read_aligner_0/word_data
N read_aligner_0/read_data    memwb_reg_0/read_data_in
N write_strobe_gen_0/wstrb         cache_unit_0/st_strb
N write_strobe_gen_0/wdata_aligned cache_unit_0/st_data
N exmem_reg_0/exmem_pc4        memwb_reg_0/pc4_in
N exmem_reg_0/exmem_result_src memwb_reg_0/result_src_in

# ================= WB =================
N memwb_reg_0/memwb_result_src result_mux_0/result_src
N memwb_reg_0/memwb_alu_result result_mux_0/alu_result
N memwb_reg_0/memwb_read_data  result_mux_0/read_data
N memwb_reg_0/memwb_pc4        result_mux_0/pc_plus4
N const0_32b/dout              result_mux_0/csr_rdata
N memwb_reg_0/memwb_reg_write  register_file_0/we3 forwarding_unit_0/mem_wb_reg_write
N memwb_reg_0/memwb_rd         register_file_0/a3 forwarding_unit_0/mem_wb_rd
N result_mux_0/write_data      register_file_0/wd3 mux3_fa/d_wb mux3_fb/d_wb

# ================= SoC: mem_stall + fence + caches<->mem =================
N icache_unit_0/stall orgate2_memstall/a
N cache_unit_0/stall  orgate2_memstall/b
N orgate2_memstall/y  ifid_reg_0/mem_stall idex_reg_0/mem_stall exmem_reg_0/mem_stall memwb_reg_0/mem_stall orgate2_corestall/b andn2_csrwe/b andn2_mret/b andn2_trapwe/b andn2_traptaken/b
N fencei_oneshot_0/ic_fence_i icache_unit_0/fence_i

# cache <-> memory AXI (plain pins; only the ports axi_slave_mem has)
foreach p {ARADDR ARVALID ARREADY RDATA RLAST RVALID RREADY \
           AWADDR AWVALID AWREADY WDATA WSTRB WLAST WVALID WREADY BVALID BREADY} {
  connect_bd_net [get_bd_pins icache_unit_0/$p] [get_bd_pins imem/$p]
  connect_bd_net [get_bd_pins cache_unit_0/$p]  [get_bd_pins dmem/$p]
}

# memory preload ports -> external
N P:imem_prog_we   imem/prog_we
N P:imem_prog_addr imem/prog_addr
N P:imem_prog_data imem/prog_data
N P:dmem_prog_we   dmem/prog_we
N P:dmem_prog_addr dmem/prog_addr
N P:dmem_prog_data dmem/prog_data

# ---------- finish ----------
regenerate_bd_layout
validate_bd_design
save_bd_design
puts "RV32_SoC block design built. Check the Tcl console for validate_bd_design result."
