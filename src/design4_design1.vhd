
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.ALL;

--#design1

entity design4_design1 is
    generic (
        clk_in_freq  : natural;
        clk_out_freq : natural
    );
    port (
        rst     : in  std_logic;
        clk_in  : in  std_logic;
        clk_out : out std_logic
    );
end design4_design1;

architecture BHV of design4_design1 is
    constant OUT_PERIOD_COUNT : integer := (clk_in_freq/clk_out_freq)-1;
begin
    process(clk_in, rst)
        variable count : integer range 0 to OUT_PERIOD_COUNT; -- note: integer type defaults to 32-bits wide unless you specify the range yourself
    begin
        if(rst = '1') then
            count := 0;
            clk_out <= '0';
        elsif(rising_edge(clk_in)) then
            if(count = OUT_PERIOD_COUNT) then
                count := 0;
            else
                count := count + 1;
            end if;
            if(count > OUT_PERIOD_COUNT/2) then
                clk_out <= '1';
            else
                clk_out <= '0';
            end if;
        end if;
    end process;
end BHV;
--#design1








