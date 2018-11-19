#!/usr/bin/env python
import os

import fileinput
import sys
from fast_tlutmap import run



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
# Removing .vhd extension from input filename
xx = filein
xx = xx.replace(".vhd", "")

# To scan diffrent parameters in design and print
print("List of design options available\n ")
q1= open("temp.txt","w+")

for line in fileinput.input(filein):
    if "--#" in line:
        line=line.replace(" ","")
        line = line.replace("--#", "")
        line = line.replace("\t", "")


        q1 = open("temp.txt", "r")
        if line in q1:
            continue
        else:
            with open("temp.txt","a")as q1:
                     q1.write(line)






q11=open("temp.txt","r")
print(q11.read())



# asking user to select file name to generate file

print(" Type design you would like to generate")
fi = raw_input(">> ")

while fi not in open("temp.txt",).read():
    print("Enter valid options from above list \n")
    print(" Type design you would like to generate")
    fi = raw_input(">> ")

q1.close()

#extract data from input file and print desired file output

q2=fi+".vhd"
q2=xx +"_" + q2
print(q2)
q3=xx + "_"+ fi

# creating new file and defining different keywords
q4=open(q2,"w")
q5="--#"+fi

q6=q5.replace(""," ")
q7="--#"
q8=q7.replace(""," ")

# writing design to new file for slected parameter

#exception handling also intreduces in code

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
                q4.write(line.replace(xx,q3))
    except StopIteration:
        print("Error in defining parameters in source file")
    else:

        print(q2, "----------File generate successfully-----------\n")


#closing file

q4.close()


print("********* Synthesis step for design ***************** \n\n ")

print("Default board is **XC7Z020CLG400-1** \n\n")



q23=xx+"_"+fi
ran1=open("tri.tcl", "w")

q1=open ("run.tcl","r")

for line in q1:	
		
	if "read_vhdl" in line:
		ran1.write(line.replace("design1_pipelined.vhd", q2))
		
	elif "synth_design"in line:
		ran1.write(line.replace("design1_pipelined", q23))
	else:
		ran1.write(line)	
		
q1.close()
ran1.close()		
				
    
    

			 
	
		
			
        
   
        
    
			  

  
	

viva="vivado -mode batch  -source tri.tcl"

os.system(viva)
print("\n")	
print("\n")	
print("***************Successfully Bit file generated*********************************")
print("\n")	
print("\n")	



