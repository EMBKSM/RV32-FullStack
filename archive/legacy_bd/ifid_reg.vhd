-- ifid_reg : IF/ID pipeline boundary register (extracted from rv32_core.vhd)
--   freeze on mem_stall (highest priority); on flush squash instr->NOP (pass pc/pc4);
--   else hold on load_use_stall; else latch. flush = ex_pc_src OR trap_taken_q.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
entity ifid_reg is
    Port (
        clk            : in  std_logic;
        reset          : in  std_logic;
        mem_stall      : in  std_logic;   -- freeze
        flush          : in  std_logic;   -- squash to NOP (branch/jump/trap)
        load_use_stall : in  std_logic;   -- hold
        pc_in          : in  std_logic_vector(31 downto 0);
        pc4_in         : in  std_logic_vector(31 downto 0);
        instr_in       : in  std_logic_vector(31 downto 0);
        ifid_pc        : out std_logic_vector(31 downto 0);
        ifid_pc4       : out std_logic_vector(31 downto 0);
        ifid_instr     : out std_logic_vector(31 downto 0)
    );
end ifid_reg;
architecture rtl of ifid_reg is
    constant NOP : std_logic_vector(31 downto 0) := x"00000013";
begin
    process(clk, reset)
    begin
        if reset = '1' then
            ifid_pc <= (others => '0'); ifid_pc4 <= (others => '0'); ifid_instr <= NOP;
        elsif rising_edge(clk) then
            if mem_stall = '1' then
                null;
            elsif flush = '1' then
                ifid_instr <= NOP; ifid_pc <= pc_in; ifid_pc4 <= pc4_in;
            elsif load_use_stall = '1' then
                null;
            else
                ifid_pc <= pc_in; ifid_pc4 <= pc4_in; ifid_instr <= instr_in;
            end if;
        end if;
    end process;
end rtl;
