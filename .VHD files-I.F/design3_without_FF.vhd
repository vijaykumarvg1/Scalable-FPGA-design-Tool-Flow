library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity design3_without_FF is

port (  
         x: in std_logic_vector(64 downto 0);
         y: in std_logic_vector(64 downto 0);
         z: in std_logic_vector(64 downto 0);
         sel: in std_logic_vector(1 downto 0); 
         out1: out std_logic_vector(64 downto 0);
         out2: out std_logic_vector(64 downto 0);
         out3: out std_logic_vector(64 downto 0)

   );
end design3_without_FF;

architecture behavioral of design3_without_FF is

begin

process(sel, x, y,z)

begin







--#without_FF
out1<="00000000000000000000000000000000000000000000000000000000000000000";
out2<="00000000000000000000000000000000000000000000000000000000000000000" ; 
out3<="00000000000000000000000000000000000000000000000000000000000000000" ;
--#without_FF


case (sel) is

  when "00"=> out1<=x;
  when "01"=> out1<=y;
  when "10"=> out1<=z; 
  when others=>out1<="00000000000000000000000000000000000000000000000000000000000000000"; out2<="00000000000000000000000000000000000000000000000000000000000000000"; out3<="00000000000000000000000000000000000000000000000000000000000000000";
 end case;

end process;


end behavioral;        
