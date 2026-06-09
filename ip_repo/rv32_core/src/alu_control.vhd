-- alu_control.vhd - decode (alu_op, funct3, funct7_5) -> alu_ctrl[3:0]
-- Spec: Movement.md 5.3
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity alu_control is
    Port (
        alu_op    : in  std_logic_vector(1 downto 0);
        funct3    : in  std_logic_vector(2 downto 0);
        funct7_5  : in  std_logic;
        alu_ctrl  : out std_logic_vector(3 downto 0)
    );
end alu_control;

architecture Behavioral of alu_control is
begin
    process(alu_op, funct3, funct7_5)
    begin
        case alu_op is
            when "00"   => alu_ctrl <= "0000";                 -- ADD (addr)
            when "01"   => alu_ctrl <= "0001";                 -- SUB (branch compare base)
            when "11"   => alu_ctrl <= "1010";                 -- Bpass (LUI)
            when others =>                                     -- "10" R/I funct decode
                case funct3 is
                    when "000"  => if funct7_5 = '1' then alu_ctrl <= "0001";  -- SUB
                                   else                 alu_ctrl <= "0000"; end if; -- ADD
                    when "001"  => alu_ctrl <= "0101";          -- SLL
                    when "010"  => alu_ctrl <= "1000";          -- SLT
                    when "011"  => alu_ctrl <= "1001";          -- SLTU
                    when "100"  => alu_ctrl <= "0100";          -- XOR
                    when "101"  => if funct7_5 = '1' then alu_ctrl <= "0111";  -- SRA
                                   else                 alu_ctrl <= "0110"; end if; -- SRL
                    when "110"  => alu_ctrl <= "0011";          -- OR
                    when others => alu_ctrl <= "0010";          -- AND (111)
                end case;
        end case;
    end process;
end Behavioral;
