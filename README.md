# Scalable-VHDL-Design-Tool-Flow


    

Here we present a Scalable VHDL design tool flow which  is automated, with error handling capabilities at different stages. It helps to generate scalable VHDL designs, and an implementation bit file, from a single intermediate VHDL design file. This tool flow helps the VHDL hardware designers to generate a single intermediate VHDL design file, with multiple design parameters. It also helps the end-users of VHDL hardware designs in choosing, and generating the right design parameter bit file according to there requirement.


![f1-1](https://user-images.githubusercontent.com/35568574/48627352-a8317a00-e9b4-11e8-93f0-346362504236.jpg)



#Varaints of Tool flow


![f6](https://user-images.githubusercontent.com/35568574/48627673-74a31f80-e9b5-11e8-89ad-0e96c9fab55c.jpeg)

https://github.com/vijaykumarvg1/Scalable-FPGA-design-Tool-Flow/issues/1#issue-381620953


Tool flow source files consists the original code for scalable VHDl design tool flow, in that you need run the file name scalable.py file for the trade off branch off the tool flow, and tripleDES.py file for the implementation branch of the tool flow. 

This source files consists of four Intermediate VHDl design files in order to run the both types of the tool flow.(design1.vhd, design2.vhd, design3.vhd, design4.vhd)


  #Dependencies
[:] The user should provide the following dependencies:

- [ ] 	A UNIX operating system (tools used: gcc, bash, minicom, curl, stty, ...)
- [ ] 	Xilinx Vivado (tested with Vivado version 2013.2, 64bit), Xilinx Corporation, http://www.xilinx.com
- [ ] 	TCL scripting
- [ ] 	Shell scripting
- [ ] 	Python 2.7, http://www.python.org

