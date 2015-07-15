DC = dmd
DFLAGS = -w -wi

all: debug

debug: DFLAGS += -debug -unittest -g
debug: filepunch holescan

release: DFLAGS += -release -O
release: filepunch holescan

filepunch: argstopaths.d file.d filepunch.d help.d linuxio.d
	$(DC) $(DFLAGS) -of$@ $^

holescan: argstopaths.d file.d help.d holescan.d linuxio.d
	$(DC) $(DFLAGS) -of$@ $^

clean:
	rm -f *.o filepunch holescan

.PHONY: all debug release clean
