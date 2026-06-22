-- imm_gen.vhd - RV32I immediate generator (I/S/B/U/J), sign-extended
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity imm_gen is
    Port (
        instr  : in  std_logic_vector(31 downto 0);
        opcode : in  std_logic_vector(6 downto 0);
        imm    : out std_logic_vector(31 downto 0)
    );
end imm_gen;

architecture Behavioral of imm_gen is
begin
    process(instr, opcode)
    begin
        case opcode is
            when "0100011" =>  -- S (Store)
                imm <= std_logic_vector(resize(signed(instr(31 downto 25) & instr(11 downto 7)), 32));
            when "1100011" =>  -- B (Branch)
                imm <= std_logic_vector(resize(signed(
                        instr(31) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0'), 32));
            when "0110111" | "0010111" =>  -- U (LUI/AUIPC)
                imm <= instr(31 downto 12) & x"000";
            when "1101111" =>  -- J (JAL)
                imm <= std_logic_vector(resize(signed(
                        instr(31) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0'), 32));
            when others =>     -- I (I-ALU/Load/JALR/...)
                imm <= std_logic_vector(resize(signed(instr(31 downto 20)), 32));
        end case;
    end process;
end Behavioral;
