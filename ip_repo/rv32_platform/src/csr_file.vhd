-- csr_file.vhd - RV32 machine-mode CSR file (Zicsr) + trap update path
-- Read combinational; CSRRW/RS/RC write and trap/MRET update on clock edge.
-- Spec: RV32_Pipeline_Spec.md 4.6, Movement.md 4.5
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity csr_file is
    Port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        -- Zicsr access
        csr_addr    : in  std_logic_vector(11 downto 0);
        csr_cmd     : in  std_logic_vector(1 downto 0);   -- 00 none,01 RW,10 RS,11 RC
        csr_wdata   : in  std_logic_vector(31 downto 0);  -- rs1_data or zimm
        csr_we      : in  std_logic;
        csr_rdata   : out std_logic_vector(31 downto 0);
        -- trap update (from trap_unit)
        trap_we     : in  std_logic;
        trap_mepc   : in  std_logic_vector(31 downto 0);
        trap_mcause : in  std_logic_vector(31 downto 0);
        trap_mtval  : in  std_logic_vector(31 downto 0);
        is_mret     : in  std_logic;
        -- exported CSRs (to trap_unit / IF)
        mstatus_o   : out std_logic_vector(31 downto 0);
        mtvec_o     : out std_logic_vector(31 downto 0);
        mepc_o      : out std_logic_vector(31 downto 0)
    );
end csr_file;

architecture Behavioral of csr_file is
    signal mstatus  : std_logic_vector(31 downto 0) := (others => '0');
    signal mie      : std_logic_vector(31 downto 0) := (others => '0');
    signal mtvec    : std_logic_vector(31 downto 0) := (others => '0');
    signal mscratch : std_logic_vector(31 downto 0) := (others => '0');
    signal mepc     : std_logic_vector(31 downto 0) := (others => '0');
    signal mcause   : std_logic_vector(31 downto 0) := (others => '0');
    signal mtval    : std_logic_vector(31 downto 0) := (others => '0');
    signal mip      : std_logic_vector(31 downto 0) := (others => '0');
    constant MISA   : std_logic_vector(31 downto 0) := x"40000100"; -- MXL=32, 'I'
    signal rdata    : std_logic_vector(31 downto 0);
    signal wval     : std_logic_vector(31 downto 0);
begin
    -- read mux
    with csr_addr select rdata <=
        mstatus      when x"300",
        MISA         when x"301",
        mie          when x"304",
        mtvec        when x"305",
        mscratch     when x"340",
        mepc         when x"341",
        mcause       when x"342",
        mtval        when x"343",
        mip          when x"344",
        x"00000000"  when others;   -- mhartid(0xF14)=0 and unknown
    csr_rdata <= rdata;

    -- write value per command
    wval <= csr_wdata                     when csr_cmd = "01" else
            (rdata or csr_wdata)          when csr_cmd = "10" else
            (rdata and (not csr_wdata))   when csr_cmd = "11" else
            rdata;

    mstatus_o <= mstatus;
    mtvec_o   <= mtvec;
    mepc_o    <= mepc;

    process(clk, reset)
    begin
        if reset = '1' then
            mstatus <= (others => '0'); mie <= (others => '0'); mtvec <= (others => '0');
            mscratch <= (others => '0'); mepc <= (others => '0'); mcause <= (others => '0');
            mtval <= (others => '0'); mip <= (others => '0');
        elsif rising_edge(clk) then
            if trap_we = '1' then                       -- trap entry (highest priority)
                mepc   <= trap_mepc;
                mcause <= trap_mcause;
                mtval  <= trap_mtval;
                mstatus(7)            <= mstatus(3);    -- MPIE <= MIE
                mstatus(3)            <= '0';           -- MIE  <= 0
                mstatus(12 downto 11) <= "11";          -- MPP  <= M
            elsif is_mret = '1' then                    -- trap return
                mstatus(3)            <= mstatus(7);    -- MIE  <= MPIE
                mstatus(7)            <= '1';           -- MPIE <= 1
                mstatus(12 downto 11) <= "00";          -- MPP  <= U
            elsif csr_we = '1' then                     -- explicit CSR write
                case csr_addr is
                    when x"300" => mstatus  <= wval;
                    when x"304" => mie      <= wval;
                    when x"305" => mtvec    <= wval;
                    when x"340" => mscratch <= wval;
                    when x"341" => mepc     <= wval;
                    when x"342" => mcause   <= wval;
                    when x"343" => mtval    <= wval;
                    when x"344" => mip      <= wval;
                    when others => null;                -- read-only / unknown
                end case;
            end if;
        end if;
    end process;
end Behavioral;
