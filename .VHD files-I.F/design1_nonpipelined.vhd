

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity design1_nonpipelined is
port (
      clk : in std_logic;
      data_in : in std_logic_vector(8 downto 0);
      data_out : out std_logic
 );
end design1_nonpipelined;
architecture behavioral of design1_nonpipelined is
    signal data : std_logic_vector(8 downto 0);
    signal result : std_logic;
begin
-- process for registering data_in
process(clk)
begin
    if(rising_edge(clk)) then
        data <= data_in;
    end if;
end process;
--process for AND gate equation.
process(clk)
begin
--#nonpipelined
 if(rising_edge(clk)) then
 -- AND gate is done in a single stage.
     data_out <=data(0) and data(1) and data(2) and
                data(3) and data(4)and data(5) and data(6) and
                data(7) and data(8);
 end if;
 --#nonpipelined
   

end process;


end behavioral;

