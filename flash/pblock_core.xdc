# Floorplan: compact the RV32 core (was sprawled X26..101 Y44..149 -> route-dominated
# hazard path exmem->ifid). Confine to a tight box; SLICE-only so the NPU keeps all DSPs.
create_pblock pb_core
add_cells_to_pblock pb_core [get_cells rv32_top_i/plat/U0/u_core]
resize_pblock pb_core -add {SLICE_X24Y45:SLICE_X70Y149}
set_property IS_SOFT FALSE [get_pblocks pb_core]
