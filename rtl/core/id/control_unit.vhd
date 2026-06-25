-- control_unit.vhd - RV32I main decoder (opcode/funct3 -> control signals)
-- Spec: Movement.md 4.2/4.2.1, RV32_Pipeline_Spec.md 4.2
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity control_unit is
    Port (
        opcode       : in  std_logic_vector(6 downto 0);
        funct3       : in  std_logic_vector(2 downto 0);
        instr_31_20  : in  std_logic_vector(11 downto 0); -- SYSTEM imm field
        reg_write    : out std_logic;
        mem_read     : out std_logic;
        mem_write    : out std_logic;
        alu_src      : out std_logic;                     -- 1=imm
        src_a_sel    : out std_logic;                     -- 1=PC
        branch       : out std_logic;
        jump         : out std_logic;
        alu_op       : out std_logic_vector(1 downto 0);  -- 00 ADD,01 SUB,10 funct,11 Bpass
        result_src   : out std_logic_vector(1 downto 0);  -- 00 ALU,01 MEM,10 PC+4
        csr_to_reg   : out std_logic;
        csr_use_imm  : out std_logic;
        csr_cmd      : out std_logic_vector(1 downto 0);  -- 00 none,01 RW,10 RS,11 RC
        is_ecall     : out std_logic;
        is_ebreak    : out std_logic;
        is_mret      : out std_logic;
        is_fence_i   : out std_logic;
        illegal      : out std_logic
    );
end control_unit;

architecture Behavioral of control_unit is
begin
    process(opcode, funct3, instr_31_20)
    begin
        reg_write   <= '0'; mem_read <= '0'; mem_write <= '0';
        alu_src     <= '0'; src_a_sel <= '0'; branch <= '0'; jump <= '0';
        alu_op      <= "00"; result_src <= "00";
        csr_to_reg  <= '0'; csr_use_imm <= '0'; csr_cmd <= "00";
        is_ecall    <= '0'; is_ebreak <= '0'; is_mret <= '0'; is_fence_i <= '0';
        illegal     <= '0';

        case opcode is
            when "0110011" => reg_write <= '1'; alu_op <= "10";                                  -- R
            when "0010011" => reg_write <= '1'; alu_src <= '1'; alu_op <= "10";                  -- I-ALU
            when "0000011" => reg_write <= '1'; alu_src <= '1'; mem_read <= '1';
                              result_src <= "01"; alu_op <= "00";                                -- Load
            when "0100011" => alu_src <= '1'; mem_write <= '1'; alu_op <= "00";                  -- Store
            when "1100011" => branch <= '1'; alu_op <= "01";                                     -- Branch
            when "1101111" => reg_write <= '1'; jump <= '1'; src_a_sel <= '1'; alu_src <= '1';
                              result_src <= "10";                                                -- JAL
            when "1100111" => reg_write <= '1'; jump <= '1'; alu_src <= '1'; result_src <= "10"; -- JALR
            when "0110111" => reg_write <= '1'; alu_src <= '1'; alu_op <= "11";                  -- LUI (Bpass)
            when "0010111" => reg_write <= '1'; src_a_sel <= '1'; alu_src <= '1'; alu_op <= "00";-- AUIPC
            when "1110011" =>                                                                    -- SYSTEM
                if funct3 = "000" then
                    case instr_31_20 is
                        when x"000" => is_ecall  <= '1';
                        when x"001" => is_ebreak <= '1';
                        when x"302" => is_mret   <= '1';
                        when others => null;                                                     -- WFI etc -> nop
                    end case;
                else
                    reg_write <= '1'; csr_to_reg <= '1'; csr_use_imm <= funct3(2);
                    case funct3(1 downto 0) is
                        when "01"   => csr_cmd <= "01";                                          -- CSRRW(I)
                        when "10"   => csr_cmd <= "10";                                          -- CSRRS(I)
                        when "11"   => csr_cmd <= "11";                                          -- CSRRC(I)
                        when others => illegal <= '1';                                           -- funct3=100
                    end case;
                end if;
            when "0001111" =>                                                                    -- FENCE
                if funct3 = "001" then is_fence_i <= '1'; end if;                                 -- FENCE.I
            when others => illegal <= '1';
        end case;
    end process;
end Behavioral;
