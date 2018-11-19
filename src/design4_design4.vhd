
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.ALL;









--#design4

entity design4_design4 is
Port ( 
    a : in std_logic;
    b : in std_logic;
    cin : in std_logic;
    s : out std_logic;
    cout : out std_logic);
end design4_design4;

architecture Behavioral of design4_design4 is

begin


    s<=(a xor (b xor cin));   
    cout<=(b and cin) or (a and cin) or (a and b);

end Behavioral;

--#design4
