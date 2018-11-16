# Scalable-VHDL-Design-Tool-Flow


In FPGA (Field Programmable Gate Array) design, the coding style has a considerable impact on how an application  is implemented and how it performs. Many popular HDL (Hardware Description Language) logic synthesis tools like Vivado by Xilinx, Quartus II by Altera, and IspLever by Lattice Semiconductor, have significantly improved the optimization algorithm for FPGAs. However, the designer still has to generate synthesizable HDL code that leads the synthesis tools and achieves the required result for a given hardware architecture. To achieve the required performance, HDL based hardware designers follow their own thumb rules, and there are many research papers which suggest best practices for VHDL hardware designers. However, as many trade-offs have to be made and results depend on the combination of optimized implementations and optimized hardware architectures, final implementation decisions may have to change over time.     

In this paper we present a Scalable VHDL design tool flow which  is automated, with error handling capabilities at different stages. It helps to generate scalable VHDL designs, and an implementation bit file, from a single intermediate VHDL design file. This tool flow helps the VHDL hardware designers to generate a single intermediate VHDL design file, with multiple design parameters. It also helps the end-users of VHDL hardware designs in choosing, and generating the right design parameter bit file according to there requirement.


