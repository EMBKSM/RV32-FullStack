-- =====================================================================
-- rv32_ctrl_axi.vhd  -  AXI4-Lite control/status slave for the rv32 platform
-- Robust handshake: AW and W are latched independently (a compliant master may
-- drop AWVALID/WVALID right after each handshake), and the write commits once
-- both are captured. Read latches the address and presents data the next cycle.
-- Register map (byte offsets), see SOC_PLATFORM_DESIGN.md §4:
--   0x00 W CTRL{b0=cpu_reset,b1=run_en,b2=step,b3=clr_commit}  0x04 R STATUS
--   0x08 W IMEM_ADDR  0x0C W IMEM_WDATA(load)  0x10 W DMEM_ADDR  0x14 W DMEM_WDATA(load)
--   0x18 W REG_ADDR   0x1C R REG_RDATA  0x20 R PC  0x24 R LAST_RD  0x28 R LAST_WDATA
--   0x2C R COMMIT_CNT 0x30 W DMEM_RADDR 0x34 R DMEM_RDATA
--   0x38 R LED        0x3C R SW         0x40 R BTN   (board peripheral readback)
-- =====================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rv32_ctrl_axi is
    Port (
        S_AXI_ACLK    : in  std_logic;
        S_AXI_ARESETN : in  std_logic;
        S_AXI_AWADDR  : in  std_logic_vector(7 downto 0);
        S_AXI_AWVALID : in  std_logic;
        S_AXI_AWREADY : out std_logic;
        S_AXI_WDATA   : in  std_logic_vector(31 downto 0);
        S_AXI_WSTRB   : in  std_logic_vector(3 downto 0);
        S_AXI_WVALID  : in  std_logic;
        S_AXI_WREADY  : out std_logic;
        S_AXI_BRESP   : out std_logic_vector(1 downto 0);
        S_AXI_BVALID  : out std_logic;
        S_AXI_BREADY  : in  std_logic;
        S_AXI_ARADDR  : in  std_logic_vector(7 downto 0);
        S_AXI_ARVALID : in  std_logic;
        S_AXI_ARREADY : out std_logic;
        S_AXI_RDATA   : out std_logic_vector(31 downto 0);
        S_AXI_RRESP   : out std_logic_vector(1 downto 0);
        S_AXI_RVALID  : out std_logic;
        S_AXI_RREADY  : in  std_logic;
        cpu_reset   : out std_logic;
        run_en      : out std_logic;
        step        : out std_logic;
        imem_we     : out std_logic;
        imem_addr   : out std_logic_vector(31 downto 0);
        imem_data   : out std_logic_vector(31 downto 0);
        dmem_we     : out std_logic;
        dmem_addr   : out std_logic_vector(31 downto 0);
        dmem_data   : out std_logic_vector(31 downto 0);
        dbg_reg_addr: out std_logic_vector(4 downto 0);
        dbg_reg_data: in  std_logic_vector(31 downto 0);
        dmem_raddr  : out std_logic_vector(31 downto 0);
        dmem_rdata  : in  std_logic_vector(31 downto 0);
        pc_in       : in  std_logic_vector(31 downto 0);
        dbg_rd      : in  std_logic_vector(4 downto 0);
        dbg_wdata   : in  std_logic_vector(31 downto 0);
        dbg_commit  : in  std_logic;
        halted      : in  std_logic;
        -- board peripheral readback (0x38 LED / 0x3C SW / 0x40 BTN)
        led_in      : in  std_logic_vector(3 downto 0) := (others=>'0');
        sw_in       : in  std_logic_vector(3 downto 0) := (others=>'0');
        btn_in      : in  std_logic_vector(3 downto 0) := (others=>'0')
    );
end rv32_ctrl_axi;

architecture Behavioral of rv32_ctrl_axi is
    signal awready, wready, bvalid, arready, rvalid : std_logic := '0';
    signal aw_hs, w_hs : std_logic := '0';
    signal awaddr_q : std_logic_vector(7 downto 0) := (others=>'0');
    signal araddr_q : std_logic_vector(7 downto 0) := (others=>'0');
    signal wdata_q  : std_logic_vector(31 downto 0) := (others=>'0');
    signal rdata_q  : std_logic_vector(31 downto 0) := (others=>'0');
    -- writable registers
    signal r_ctrl      : std_logic_vector(31 downto 0) := (others=>'0');
    signal r_imem_addr : std_logic_vector(31 downto 0) := (others=>'0');
    signal r_imem_data : std_logic_vector(31 downto 0) := (others=>'0');
    signal r_dmem_addr : std_logic_vector(31 downto 0) := (others=>'0');
    signal r_dmem_data : std_logic_vector(31 downto 0) := (others=>'0');
    signal r_reg_addr  : std_logic_vector(31 downto 0) := (others=>'0');
    signal r_dmem_raddr: std_logic_vector(31 downto 0) := (others=>'0');
    signal commit_cnt  : unsigned(31 downto 0) := (others=>'0');
    -- registered command pulses
    signal imem_we_r, dmem_we_r, step_r : std_logic := '0';
begin
    S_AXI_AWREADY <= awready;  S_AXI_WREADY <= wready;
    S_AXI_BRESP   <= "00";     S_AXI_BVALID <= bvalid;
    S_AXI_ARREADY <= arready;  S_AXI_RVALID <= rvalid;
    S_AXI_RRESP   <= "00";     S_AXI_RDATA  <= rdata_q;

    cpu_reset <= r_ctrl(0);     run_en <= r_ctrl(1);
    step      <= step_r;
    imem_we   <= imem_we_r;     imem_addr <= r_imem_addr;  imem_data <= r_imem_data;
    dmem_we   <= dmem_we_r;     dmem_addr <= r_dmem_addr;  dmem_data <= r_dmem_data;
    dbg_reg_addr <= r_reg_addr(4 downto 0);
    dmem_raddr   <= r_dmem_raddr;

    -- ---------------- write channel (latched AW/W, commit once) ----------------
    process(S_AXI_ACLK)
        variable clr : std_logic;
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                awready<='0'; wready<='0'; bvalid<='0'; aw_hs<='0'; w_hs<='0';
                r_ctrl<=(others=>'0'); r_imem_addr<=(others=>'0'); r_imem_data<=(others=>'0');
                r_dmem_addr<=(others=>'0'); r_dmem_data<=(others=>'0'); r_reg_addr<=(others=>'0');
                r_dmem_raddr<=(others=>'0'); commit_cnt<=(others=>'0');
                imem_we_r<='0'; dmem_we_r<='0'; step_r<='0';
            else
                -- default: pulses low
                imem_we_r<='0'; dmem_we_r<='0'; step_r<='0';
                clr := '0';

                -- accept AW (1-cycle ready, latch address)
                if (S_AXI_AWVALID='1' and aw_hs='0') then
                    awready<='1'; awaddr_q<=S_AXI_AWADDR; aw_hs<='1';
                else awready<='0'; end if;
                -- accept W (1-cycle ready, latch data)
                if (S_AXI_WVALID='1' and w_hs='0') then
                    wready<='1'; wdata_q<=S_AXI_WDATA; w_hs<='1';
                else wready<='0'; end if;

                -- commit when both captured
                if (aw_hs='1' and w_hs='1' and bvalid='0') then
                    case awaddr_q(7 downto 2) is
                        when "000000" =>                       -- 0x00 CTRL
                            r_ctrl(1 downto 0) <= wdata_q(1 downto 0);
                            step_r <= wdata_q(2);
                            clr    := wdata_q(3);
                        when "000010" => r_imem_addr <= wdata_q;        -- 0x08
                        when "000011" => r_imem_data <= wdata_q; imem_we_r<='1';  -- 0x0C load
                        when "000100" => r_dmem_addr <= wdata_q;        -- 0x10
                        when "000101" => r_dmem_data <= wdata_q; dmem_we_r<='1';  -- 0x14 load
                        when "000110" => r_reg_addr  <= wdata_q;        -- 0x18
                        when "001100" => r_dmem_raddr<= wdata_q;        -- 0x30
                        when others   => null;
                    end case;
                    bvalid<='1'; aw_hs<='0'; w_hs<='0';
                elsif (bvalid='1' and S_AXI_BREADY='1') then
                    bvalid<='0';
                end if;

                -- commit counter
                if clr='1' then commit_cnt<=(others=>'0');
                elsif dbg_commit='1' then commit_cnt<=commit_cnt+1; end if;
            end if;
        end if;
    end process;

    -- ---------------- read channel (latched AR, data next cycle) ----------------
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN='0' then
                arready<='0'; rvalid<='0'; araddr_q<=(others=>'0'); rdata_q<=(others=>'0');
            else
                if (S_AXI_ARVALID='1' and arready='0' and rvalid='0') then
                    arready<='1'; araddr_q<=S_AXI_ARADDR;
                else
                    arready<='0';
                end if;
                if (arready='1') then          -- one cycle after accept -> present data
                    rvalid<='1';
                    case araddr_q(7 downto 2) is
                        when "000001" => rdata_q <= (0=>halted, 2=>r_ctrl(1), others=>'0'); -- 0x04 STATUS
                        when "000111" => rdata_q <= dbg_reg_data;                  -- 0x1C
                        when "001000" => rdata_q <= pc_in;                         -- 0x20
                        when "001001" => rdata_q <= std_logic_vector(resize(unsigned(dbg_rd),32)); -- 0x24
                        when "001010" => rdata_q <= dbg_wdata;                     -- 0x28
                        when "001011" => rdata_q <= std_logic_vector(commit_cnt);  -- 0x2C
                        when "001101" => rdata_q <= dmem_rdata;                    -- 0x34
                        when "001110" => rdata_q <= std_logic_vector(resize(unsigned(led_in),32)); -- 0x38 LED
                        when "001111" => rdata_q <= std_logic_vector(resize(unsigned(sw_in), 32)); -- 0x3C SW
                        when "010000" => rdata_q <= std_logic_vector(resize(unsigned(btn_in),32)); -- 0x40 BTN
                        when others   => rdata_q <= (others=>'0');
                    end case;
                elsif (rvalid='1' and S_AXI_RREADY='1') then
                    rvalid<='0';
                end if;
            end if;
        end if;
    end process;
end Behavioral;
