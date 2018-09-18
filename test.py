#!/usr/bin/env python


aq= "design1_pipelined"+ "/"+ "post_syth_util.rpt"

q1=open ( aq,"r")


lut=[]

for line in q1:
	if "| Slice LUTs* " in line:
			line =line.replace( "| Slice LUTs*             |","")
			line =line [:6]
			print (line)
			lut.append(line)
			print (lut)
