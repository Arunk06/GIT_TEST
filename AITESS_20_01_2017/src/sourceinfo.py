# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : sourceinfo
# File name		        : sourceinfo.py
# Usage			        : Provides source file and line number information to 
#                         AITESS messages and maintains current source 
#                         information.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 26/09/2016
#       Bug fix for incorrect listing of statements in RDF file. This was
#       due to the instance variable "previous_line" of class "SourceStack" not 
#       being saved to stack.
#       Refer: TPR No. 20160 dated 15/09/2016

from copy import deepcopy


class SourceInfo(object):
    """
    This provides a source information entity that stores the source name
    the line number within the source and the text of that line. This is
    used to show detailed error in input.
    """

    def __init__(self, name, lineno, max_lines=1):
        self.name = name
        self.lineno = lineno
        # Line number is incremented for each '\n' character and
        # this may cause the line number to exceed the maximum lines
        # in the input which should be corrected using this varaible
        # see __str__
        self.max_lines = max_lines

    def get_name(self):
        return self.name

    def get_lineno(self):
        return self.lineno

    def increment_lineno(self):
        self.lineno += 1

    def decrement_lineno(self):
        self.lineno -= 1

    def __str__(self):
        return "file '%s', line %ld" % (self.name, min(self.max_lines, self.lineno))


class SourceStack(object):
    """
    This provides a stack where the different opened files are stored in the
    reverse order in which they were opened i.e. the top of the stack contains
    the last opened file. Each element of the stack is a dictionary with the
    following entries.

    source_id       -> an instance of either the class PseudoTpfFile or
                       the class RealTpfFile (the input abstraction)
    source_info     -> an instance of SourceInfo class

    """

    def __init__(self):
        self.previous_line = 0
        self.stack = []

    def __close_all(self):
        for s in self.stack:
            s['source_id'].close()  # close all open files

    def get_source_id(self):
        return self.top()['source_id']

    def get_source_line(self):
        text_block = ''
        # One is subtracted because after the current line is
        # processed line number is incrememnted by one to get
        # to get to the beginning of the next line
        current_line = self.top()['source_info'].get_lineno() - 1

        # If a block of text was missed the entire block must be
        # returned for listing. Examples for such a case will be
        # a block comment enclosed in '!#' and '#!' and spanning
        # multiple lines
        if current_line - self.previous_line > 1:
            for line in xrange(self.previous_line + 1, current_line + 1):
                text_block += self.top()['source_id'].get_line_text(line)

            self.previous_line = current_line
            return text_block
        else:
            text_line = self.top()['source_id'].get_line_text(current_line)
            self.previous_line = current_line
            return text_line

    def get_source_info(self, copy=True):
        # Return a deep copy because the stack is cleared before evaluation
        # and the referenced source info object may cease to exist.
        if copy:
            return deepcopy(self.top()['source_info'])
        else:
            return self.top()['source_info']

    def top(self):
        return self.stack[-1]

    def push(self, source_id, source_info):
        # Mod1: begin
        # Save previous line number of current file
        self.stack.append({'source_id': source_id, 'source_info': source_info, 'previous_line': self.previous_line})
        self.previous_line = 0  # Reset previous line number for the new file
        # Mod1: end

    def pop(self):
        # Mod1: begin
        source_item = self.stack.pop()
        self.previous_line = source_item['previous_line']  # Restore previous line number of the old file
        return source_item
        # Mod1: end

    def clear(self):
        self.__close_all()
        # Mod1: begin
        self.previous_line = 0  # Reset previous line number
        # Mod1: end
        self.stack = []
