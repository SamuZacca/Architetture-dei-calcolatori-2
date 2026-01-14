# Variabili parametriche per la sintesi
TESTBENCH ?= tb.v
NETLIST ?= top.synth.v
SIMLIST ?= top.vvp
YOSYS_SCRIPT ?= synth.ys


all: $(SIMLIST)

# Sintesi netlist
$(NETLIST):
	yosys -s $(YOSYS_SCRIPT)

# Compilazione simulazione
$(SIMLIST): $(NETLIST) $(TESTBENCH)
	iverilog -o $@ $^
	
synth: $(NETLIST)

sim-compile: $(SIMLIST)

# Run simulation
run: $(SIMLIST)
	vvp $(SIMLIST)

clean:
	rm -rf $(SIMLIST) $(NETLIST) *.pdf *.dot *.vcd