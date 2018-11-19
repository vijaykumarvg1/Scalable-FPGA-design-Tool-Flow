#!/usr/bin/env python
import os

import fileinput
import sys
import random
from beautifultable import BeautifulTable
from tabulate import tabulate
from texttable import Texttable

print("Welcome to programme *** Generate Scalable VHDL design  ***\n\n  ")

# Asking Enter file name from user
while True:
    try:

        print("Enter the file name followed by .vhd: ")
        filein = raw_input(">>> ")

        fr = open(filein, "r")
        break
    except:

        print("Type valid file name")

# Extracting available designs

xx = filein
xx = xx.replace(".vhd", "")

# To scan diffrent parameters in design and print
print("List of design options available\n ")
q1 = open("temp.txt", "w+")

for line in fileinput.input(filein):
    if "--#" in line:
        line = line.replace(" ", "")
        line = line.replace("--#", "")
        line = line.replace("\t", "")

        q1 = open("temp.txt", "r")
        if line in q1:
            continue
        else:
            with open("temp.txt", "a")as q1:
                q1.write(line)

q11 = open("temp.txt", "r")
print(q11.read())



q7 = "--#"

q11 = open("temp.txt", "r")
for line in q11:
    z = line
    z=z.replace("\n","")

    q3 = xx + "_" + z

    q5 = "--#" + z
    q2 = q3 + ".vhd"


    q4 = open(q2, "w")
    with open(filein) as f:
        try:
            for line in f:
                if q5 in line:

                    q4.write(line)
                    line = next(f)
                    q4.write(line)
                elif q7 in line:
                    line = next(f)
                    while q7 not in line:
                        line = next(f)



                else:
                    q4.write(line.replace(xx, q3))
        except StopIteration:

            print("Error in defining parameters in source file")
        else:

            print(q2, "----------File generate successfully-----------\n\n")

q4.close()


print("********* Synthesis step for design ***************** \n\n ")

print("Default board is **XC7Z020CLG400-1** \n\n")

q11 = open("temp.txt", "r")
for line in q11:
    ee = line
    ee=ee.replace("\n","")
    er=xx+"_"+ee
    ez=xx+"_"+ee+".vhd"
    ef = ee + ".tcl"
    e1 = ee + ".vhd"

    ran1 = open(ef, "w")
    ran = open("ma.tcl", "r")
    for line in ran:

         if "read_vhdl" in line:

             ran1.write(line.replace("design1_pipelined.vhd", ez))
         elif "synth_design" in line:
             ran1.write(line.replace("design1_pipelined", er))
         elif "set outputDir"in line:
             ran1.write(line.replace("my_design_output",er))

         else:
             ran1.write(line)

ran.close()
ran1.close()


q11=open("temp.txt","r")

for line in q11:
	aq=line
	aq=aq.replace("\n", "")
	viva="vivado -mode batch -source "
	aq=aq+".tcl"
	vi=viva+aq
	os.system (vi)




lut=[]
lutl=[]
lutm=[]
ff=[]
bram=[]
dsp=[]
design=[]
design.append("Res. List")
lut.append("slice LUTs ")
lutl.append(" LUT Logic ")
lutm.append("LUT Memory ")
ff.append(" Flip Flop ")
bram.append("Block RAM")
dsp.append("DSPs ")




q11 = open("temp.txt", "r")
for line in q11:
	
    ee = line
    ee=ee.replace("\n","")
    design.append(ee)
    er= xx+"_"+ee   
    
    ew=er+"/"+ "post_syth_util.rpt" 
    q1=open( ew,"r")
    for line in q1:
		
		
		if "| Slice LU" in line:
		
			line =line [30:35]
			line=line.replace( " | " , "")
			lut.append(line)
		
			
		if "|   LUT as Logic "in line:
		
			line=line [30:35]
			line=line.replace( " | " , "")
			lutl.append(line)
		
			
			
		if "|   LUT as Memory "in line:
			
			line=line[30:35]
			line=line.replace( " | " , "")
			lutm.append(line)
		
			
			
		if "|   Register as Flip Flop" in line:
	
			line=line[30:35]
			line=line.replace( " | " , "")
			ff.append(line)
		
			
		if "| Block RAM Tile "in line:
		
			line=line[21:24]
			bram.append(line)
		
			
		if "| DSPs"in line:
		
			line=line[14:18]
			line=line.replace( " | " , "0")
			dsp.append(line)
	
					
print("\n")	
print("\n")
design.append("Total.a.List")	

				
			

lut.append(53200)
lutl.append(53200)
lutm.append(17400)
ff.append(106400)
bram.append(140)
dsp.append(220)








t = Texttable()			

t.add_rows([ design, lut, lutl, lutm, ff, bram, dsp ])
print t.draw()		 
 
print("\n")	


     



print("***************************************************Finished******************************************")

q11.close()
q1.close()





