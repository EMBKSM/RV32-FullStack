-- trap_unit.vhd - machine-mode exception detection + precise trap (commit)
-- Spec: RV32_Pipeline_Spec.md 6.7/10.3, Movement.md 7.3
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity trap_unit is
    Port (
        illegal_instr  : in  std_logic;
        instr_misalign : in  std_logic;
        load_misalign  : in  std_logic;
        store_misalign : in  std_logic;
        is_ecall       : in  std_logic;
        is_ebreak      : in  std_logic;
        is_mret        : in  std_logic;
        instr_pc       : in  std_logic_vector(31 downto 0);
        fault_addr     : in  std_logic_vector(31 downto 0);
        mtvec          : in  std_logic_vector(31 downto 0);
        mepc           : in  std_logic_vector(31 downto 0);
        trap_taken     : out std_logic;
        trap_target    : out std_logic_vector(31 downto 0);
        flush_all      : out std_logic;
        trap_we        : out std_logic;                       -- CSR update on exception
        trap_mepc      : out std_logic_vector(31 downto 0);
        trap_mcause    : out std_logic_vector(31 downto 0);
        trap_mtval     : out std_logic_vector(31 downto 0)
    );
end trap_unit;

architecture Behavioral of trap_unit is
    signal exc   : std_logic;
    signal cause : std_logic_vector(31 downto 0);
begin
    exc <= illegal_instr or instr_misalign or load_misalign or store_misalign
           or is_ecall or is_ebreak;

    -- exception cause priority encoder
    process(instr_misalign, illegal_instr, is_ebreak, load_misalign, store_misalign, is_ecall)
    begin
        if    instr_misalign = '1' then cause <= x"00000000";   -- 0
        elsif illegal_instr  = '1' then cause <= x"00000002";   -- 2
        elsif is_ebreak      = '1' then cause <= x"00000003";   -- 3
        elsif load_misalign  = '1' then cause <= x"00000004";   -- 4
        elsif store_misalign = '1' then cause <= x"00000006";   -- 6
        elsif is_ecall       = '1' then cause <= x"0000000B";   -- 11 (ECALL M)
        else                            cause <= x"00000000";
        end if;
    end process;

    trap_taken  <= exc or is_mret;
    flush_all   <= exc or is_mret;
    trap_we     <= exc;                                          -- only exceptions update mepc/mcause/mtval
    trap_target <= mtvec when exc = '1' else mepc;               -- exception->mtvec, MRET->mepc
    trap_mepc   <= instr_pc;
    trap_mcause <= cause;
    trap_mtval  <= fault_addr;
end Behavioral;
