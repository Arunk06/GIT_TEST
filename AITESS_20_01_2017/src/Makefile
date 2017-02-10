CC            = gcc
PYTHON        = python
CYTHON        = cython

ifeq ($(SYSTEM), DEV)
# For the developer system (anything other than Fedora Core 2)
PYTHON_INC    = /usr/include/python2.7
endif

ifeq ($(SYSTEM), XEN)
# For Xenomai system
PYTHON_INC    = /usr/include/python2.7
endif

ifeq ($(SYSTEM), RTL)
# For Fedora Core 2
PYTHON_INC    = /usr/local/include/python2.7
RTLINUX_INC   = /usr/rtlinux-3.2-pre2/include
endif

all: cfg.so output.so asizeof.so aitessapp.so completer.so configfile.so datatable.so errorhandler.so evaluatetree.so inputal.so message.so nametype.so parser.so progressbar.pyc scanner.so sourceinfo.so syntaxtree.so tokens.so shm.so

clean:
	rm -f *.o *.c *.h *~

cfg.so: cfg.pyx
	$(CYTHON) cfg.pyx
	$(CC) -D GIT_VERSION=\"`git describe`\" -D GIT_VERSION_LONG=\"`git describe --long`\" -O3 -I$(PYTHON_INC) -c -fPIC cfg.c
	$(CC) -O3 -shared cfg.o -lm -o cfg.so

output.so: output.pyx
	$(CYTHON) output.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC output.c
	$(CC) -O3 -shared output.o -lm -o output.so

asizeof.so: asizeof.py
	$(CYTHON) asizeof.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC asizeof.c
	$(CC) -O3 -shared asizeof.o -lm -o asizeof.so

aitessapp.so: aitessapp.py
	$(CYTHON) aitessapp.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC aitessapp.c
	$(CC) -O3 -shared aitessapp.o -lm -o aitessapp.so

completer.so: completer.py
	$(CYTHON) completer.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC completer.c
	$(CC) -O3 -shared completer.o -lm -o completer.so

configfile.so: configfile.py
	$(CYTHON) configfile.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC configfile.c
	$(CC) -O3 -shared configfile.o -lm -o configfile.so

datatable.so: datatable.pyx
	$(CYTHON) datatable.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC datatable.c
	$(CC) -O3 -shared datatable.o -lm -o datatable.so

errorhandler.so: errorhandler.py
	$(CYTHON) errorhandler.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC errorhandler.c
	$(CC) -O3 -shared errorhandler.o -lm -o errorhandler.so

evaluatetree.so: evaluatetree.pyx
	$(CYTHON) evaluatetree.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC evaluatetree.c
	$(CC) -O3 -shared evaluatetree.o -lm -o evaluatetree.so

inputal.so: inputal.py
	$(CYTHON) inputal.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC inputal.c
	$(CC) -O3 -shared inputal.o -lm -o inputal.so

message.so: message.pyx
	$(CYTHON) message.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC message.c
	$(CC) -O3 -shared message.o -lm -o message.so

nametype.so: nametype.pyx
	$(CYTHON) nametype.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC nametype.c
	$(CC) -O3 -shared nametype.o -lm -o nametype.so

parser.so: parser.pyx
	$(CYTHON) parser.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC parser.c
	$(CC) -O3 -shared parser.o -lm -o parser.so

progressbar.pyc: progressbar.py
	$(PYTHON) -c "import progressbar"

scanner.so: scanner.pyx
	$(CYTHON) scanner.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC scanner.c
	$(CC) -O3 -shared scanner.o -lm -o scanner.so

sourceinfo.so: sourceinfo.py
	$(CYTHON) sourceinfo.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC sourceinfo.c
	$(CC) -O3 -shared sourceinfo.o -lm -o sourceinfo.so

syntaxtree.so: syntaxtree.pyx
	$(CYTHON) syntaxtree.pyx
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC syntaxtree.c
	$(CC) -O3 -shared syntaxtree.o -lm -o syntaxtree.so

tokens.so: tokens.py
	$(CYTHON) tokens.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC tokens.c
	$(CC) -O3 -shared tokens.o -lm -o tokens.so

shm.so: shm.pyx
ifeq ($(SYSTEM), DEV)
	$(CYTHON) shm_dummy.py
	$(CC) -O3 -I$(PYTHON_INC) -c -fPIC shm_dummy.c
	$(CC) -O3 -shared shm_dummy.o -lm -o shm_dummy.so
endif
ifeq ($(SYSTEM), XEN)
	$(CYTHON) shm.pyx
	$(CC) -O3 `xeno-config --skin=posix --cflags` -I$(PYTHON_INC) -c -fPIC shm.c
	$(CC) -O3 -shared shm.o `xeno-config --skin=posix --ldflags` -o shm.so
endif
ifeq ($(SYSTEM), RTL)
	$(CYTHON) shm.pyx
	$(CC) -O3 -I$(RTLINUX_INC) -I$(PYTHON_INC) -c -fPIC shm.c
	$(CC) -O3 -shared shm.o -lm -o shm.so
endif

clean_bin:
	rm -f cfg.so output.so asizeof.so aitessapp.so completer.so configfile.so datatable.so errorhandler.so evaluatetree.so inputal.so message.so nametype.so parser.so progressbar.pyc scanner.so sourceinfo.so syntaxtree.so tokens.so shm.so shm_dummy.so


