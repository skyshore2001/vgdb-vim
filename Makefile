CC=g++
CXX=g++

ifdef windir

CFLAGS=-g -D_WINDOWS
CXXFLAGS=$(CFLAGS)

all: vgdbc.dll vgdbc_test.exe cpp1.exe

test: all
	gvim -c "echo libcall('vgdbc.dll', 'test', 'libcall test')"

test2: vgdbc_test.exe
	@$< "help"

vgdbc_test.exe vgdbc.dll: LDFLAGS=-lwsock32

vgdbc_test.exe: vgdbc.o vgdbc.dll
	$(CC) $^ -o $@ $(LDFLAGS) 

vgdbc.dll: vgdbc.o 
	$(CC) -shared $^ -o $@ $(LDFLAGS) 

clean:
	-rm -rf *.o vgdbc.dll vgdbc_test.exe

cpp1.exe: cpp1.cpp Makefile
	$(CXX) $(CXXFLAGS) $< -o $@ $(LDFLAGS)

else # for linux:

CFLAGS=-g -fPIC -D_LINUX
CXXFLAGS=$(CFLAGS)
LDFLAGS=-ldl

all: libvgdbc.so vgdbc_test cpp1

test: all
	export LD_LIBRARY_PATH=`pwd` && vi -c "echo libcall('libvgdbc.so', 'test', 'libcall test')"

test2: vgdbc_test
	@$< "help"

vgdbc_test: vgdbc.o
	$(CC) $^ -o $@ $(LDFLAGS) 

libvgdbc.so: vgdbc.o
	$(CC) -shared $^ -o $@ $(LDFLAGS)

clean:
	-rm -rf *.o libvgdbc.so vgdbc_test

cpp1: cpp1.cpp Makefile
	$(CXX) $(CXXFLAGS) $< -o $@ $(LDFLAGS)

endif

######
vgdbc.o: vgdbc.c Makefile

