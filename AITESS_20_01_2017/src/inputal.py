# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : inputal
# File name		        : inputal.py
# Usage			        : Provides an input abstraction to AITESS i.e. AITESS need not
#                         worry whether the input comes from the commandline or a file.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 26/06/2015
#       Removed the newline character at the end of pseudo TPF file.
# Mod2: hari on 27/09/2016
#       Put back the newline character at the end of pseudo TPF file
#       because opwait and opmsg in LTM compatability mode requires it.

# input abstraction layer
import cfg
from errorhandler import ParseError


class PseudoTpfFile(object):
    def __init__(self, stream=''):
        self.name = '«stdin»'
        # Mod2: begin
        # Mod1: begin
        self.stream = stream + '\n'
        # Mod1: end
        # Mod2: end
        self.pointer = 0

    def get_name(self):
        return self.name

    def read(self, size):
        data = self.stream[self.pointer: (self.pointer + size)]
        self.pointer += size

        if self.pointer > len(self.stream):
            self.pointer = len(self.stream)

        return data

    def seek(self, offset, whence=0):
        self.pointer += offset

    def open(self):
        # no need of file open in pseudo file
        pass

    def close(self):
        pass

    def roll_back(self):
        self.seek(-1)

    def next_char(self):
        return self.read(1)

    def get_line_text(self, line_number):
        return self.stream

    def get_line_count(self):
        return self.stream.count('\n')


class RealTpfFile(object):
    def __init__(self, name):
        self.name = cfg.config_file.get_tpfpath(name)
        try:
            self.f = open(self.name, 'rt', 4096)
        except IOError as e:
            # An IO error exception indicates that there might be some 
            # file permission problem.
            self.__cleanup_files()
            message = "Test plan file '%s' I/O error, %s" \
                      % (self.name, e.strerror.lower())
            raise ParseError(message, cfg.source_stack.get_source_info())
        except RuntimeError as e:
            self.__cleanup_files()
            raise ParseError("Deeply nested test plan file inclusion, possibly cyclic (PYERR: %s)" % str(e),
                             cfg.source_stack.get_source_info())

        # Hari 27/11/2014: Fixed last line being duplicated because of non printing decimal 10 character at EOF
        self.stream_lines = self.f.readlines()
        # if there is something in the input file (first condition), then replace non-printing characters at
        # end of input by a newline
        if (len(self.stream_lines) > 0) and (ord(self.stream_lines[-1][-1]) <= 31):
            self.stream_lines[-1] = self.stream_lines[-1][:-1] + '\n'
        self.stream_lines += ['\x00']  # add EOF character as the last line

        self.stream = ''.join(self.stream_lines)
        self.pointer = 0

    def __cleanup_files(self):
        pass

    def get_name(self):
        return self.name

    def read(self, size):
        data = self.stream[self.pointer: (self.pointer + size)]
        self.pointer += size

        if self.pointer > len(self.stream):
            self.pointer = len(self.stream)

        return data

    def seek(self, offset, whence=0):
        self.pointer += offset

    def open(self):
        # file was already opened in constructor
        pass

    def close(self):
        self.f.close()

    def roll_back(self):
        self.seek(-1)

    def next_char(self):
        return self.read(1)

    def get_line_text(self, line_number):
        return self.stream_lines[line_number - 1]

    def get_line_count(self):
        return self.stream.count('\n')
