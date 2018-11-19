

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity design1_pipelined_pipelined is
port (
      clk : in std_logic;
      data_in : in std_logic_vector(8 downto 0);
      data_out : out std_logic
 );
end design1_pipelined_pipelined;
architecture behavioral of design1_pipelined_pipelined is
    signal data : std_logic_vector(8 downto 0);
    signal result : std_logic;
--#pipelined
    signal temp1,temp2,temp3,temp4, temp5,temp6,temp7 : std_logic;
--#pipelined
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
   
--#pipelined
  if(rising_edge(clk)) then
 temp1 <= (data(0) and data(1)) ;
 temp2 <= ( data(2) and temp1);
 temp3 <= (data (3) and temp2);
 temp4 <= (data(4) and temp3);
 temp5<= ( data(5) and temp4);
 temp6 <= (data (6) and temp5);
 temp7<=(data(7) and temp6);
 data_out<=(data(8) and temp7);
 end if;
                             --#pipelined

end process;


end behavioral;

