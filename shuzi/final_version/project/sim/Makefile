TIMESTAMP=$(shell powershell -NoProfile -Command "Get-Date -Format HHmmss")

all:clean elab run

elab: 
	vlib work
	vmap work ./work
	vlog -modelsimini modelsim.ini -sv -timescale 1ns/1ps -f ./files.f -l comp.log
run: 
	vsim -modelsimini modelsim.ini -novopt -wlf wave.wlf -c tb +seed=$(TIMESTAMP) -do run.tcl -l run.log

verdi:
	vsim -view wave.wlf &

clean:
	-rm -rf work transcript vsim.wlf wave.wlf wlft* comp.log run.log
