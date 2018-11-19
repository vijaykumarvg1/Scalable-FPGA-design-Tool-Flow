
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.ALL;




--#pipe

entity design4_pipe is

	port (
	        a: in std_logic;
	        b: in std_logic;
	        o: out std_logic
		
	);
end design4_pipe;
	
architecture hw of design4_pipe is
	--
	
begin
	--
     o<=(a and b);
     
end hw;     
	
--#pipe





