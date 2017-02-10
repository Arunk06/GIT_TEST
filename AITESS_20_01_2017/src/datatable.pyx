# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : datatable
# File name		        : datatable.pyx
# Usage			        : Definition and methods for the AITESS symbol table.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#

import cfg
from nametype import SystemFunction
from tokens import *

cdef class SymbolTable(dict):
    """Symbol table class.
    
    This defines the symbol table and the associated operations on it.
    The symbol table is a dictionary with the symbol as the key and the 
    attributes associated with it as the value. The attributes will be stored 
    as a list Eg: (symbol type, symbol value/symbol location, etc.).
    """
    cdef public dict source_name_map
    cdef cache_version
    def __init__(self):
        """Creates a symbol table.
        
        The constructor creates a symbol table by calling the super class
        constructor.
        """
        super(SymbolTable, self).__init__()
        self.cache_version = cfg.aitess_version_long
        self.source_name_map = {}
        self.__load_system_functions()

    cpdef get_cache_version(self):
        return self.cache_version

    cpdef update_cache_version(self):
        self.cache_version = cfg.aitess_version_long

    cpdef __load_system_functions(self):
        self.put_entry('frame_number', SystemFunction('frame_number', None))
        self.put_entry('channel_value', SystemFunction('channel_value', None))
        self.put_entry('in_range', SystemFunction('in_range', None))
        self.put_entry('channel_enabled', SystemFunction('channel_enabled', None))
        self.put_entry('get_wdm', SystemFunction('get_wdm', None))
        self.put_entry('set_wdm', SystemFunction('set_wdm', None))
        self.put_entry('str', SystemFunction('str', None))
        self.put_entry('hex', SystemFunction('hex', None))
        self.put_entry('oct', SystemFunction('oct', None))
        self.put_entry('bin', SystemFunction('bin', None))
        self.put_entry('left_shift', SystemFunction('left_shift', None))
        self.put_entry('right_shift', SystemFunction('right_shift', None))
        self.put_entry('bit_and', SystemFunction('bit_and', None))
        self.put_entry('bit_or', SystemFunction('bit_or', None))
        self.put_entry('bit_xor', SystemFunction('bit_xor', None))
        self.put_entry('pow', SystemFunction('pow', None))
        self.put_entry('time', SystemFunction('time', None))
        self.put_entry('sin', SystemFunction('sin', None))
        self.put_entry('cos', SystemFunction('cos', None))
        self.put_entry('tan', SystemFunction('tan', None))
        self.put_entry('input_int', SystemFunction('input_int', None))
        self.put_entry('input_float', SystemFunction('input_float', None))
        self.put_entry('input_str', SystemFunction('input_str', None))
        self.put_entry('system', SystemFunction('system', None))
        self.put_entry('init_1553b', SystemFunction('init_1553b', None))
        self.put_entry('message_msgtype', SystemFunction('message_msgtype', None))
        self.put_entry('message_rtaddr', SystemFunction('message_rtaddr', None))
        self.put_entry('message_rtsubaddr', SystemFunction('message_rtsubaddr', None))
        self.put_entry('message_wcntmcode', SystemFunction('message_wcntmcode', None))
        self.put_entry('message_info', SystemFunction('message_info', None))
        self.put_entry('message_msggap', SystemFunction('message_msggap', None))
        self.put_entry('message_defined', SystemFunction('message_defined', None))
        self.put_entry('file_access', SystemFunction('file_access', None))
        self.put_entry('file_downloadpath', SystemFunction('file_downloadpath', None))
        self.put_entry('file_uploadpath', SystemFunction('file_uploadpath', None))
        self.put_entry('get_uut', SystemFunction('get_uut', None))
        self.put_entry('get_version', SystemFunction('get_version', None))

    cpdef del_source(self, str source):
        try:
            if source == '«system»':
                raise TypeError
            self.source_name_map.pop(source)
        except KeyError:
            raise

    cpdef get_sources(self):
        return self.source_name_map.keys()

    cpdef get_external_sources(self):
        sources = self.source_name_map.keys()

        try:
            sources.remove('«stdin»')
        except ValueError:
            pass

        try:
            sources.remove('«system»')
        except ValueError:
            pass

        return sources

    cpdef get_names_count_from(self, str source):
        try:
            return len(self.source_name_map[source])
        except KeyError:
            raise

    cpdef get_names_from(self, str source):
        try:
            return list(self.source_name_map[source])
        except KeyError:
            raise

    cpdef get_entry(self, str name):
        try:
            return self[name]
        except KeyError:
            raise

    cpdef get_type(self, str name):
        try:
            return self[name].get_type()
        except KeyError:
            return TokenType.TYP_UNKNOWN

    cpdef put_entry(self, str name, entry):
        self[name] = entry
        if not self.source_name_map.has_key(entry.source_info.get_name()):
            self.source_name_map[entry.source_info.get_name()] = set()
        self.source_name_map[entry.source_info.get_name()].add(name)

    cpdef del_entry(self, str name):
        try:
            if not isinstance(self[name], SystemFunction):
                entry = self[name]
                self.source_name_map[entry.source_info.get_name()].remove(name)
                if len(self.source_name_map[entry.source_info.get_name()]) == 0:
                    self.source_name_map.pop(entry.source_info.get_name())
                self.pop(name)
            else:
                raise TypeError
        except KeyError:
            raise

    def clear(self):
        self.source_name_map.clear()
        for name in super(SymbolTable, self).keys():
            if not isinstance(self[name], SystemFunction):
                self.pop(name)

    def purge_file(self, filename):
        new_filename = '«stdin»' if filename == 'stdin' else filename
        new_filename = '«system»' if new_filename == 'system' else new_filename

        if new_filename in self.get_sources():
            names = self.get_names_from(new_filename)

            try:
                for n in names:
                    self.del_entry(n)
            except TypeError:
                raise TypeError("Error: Cannot delete source '%s' of system functions." % new_filename)
        else:
            raise TypeError("Error: File '%s' not loaded." % new_filename)

    # Strange that the below code works 04/01/2012
    def __getstate__(self):
        return {'cache_version': self.cache_version, 'source_name_map': self.source_name_map}

    def __setstate__(self, dict_):
        self.source_name_map = dict_['source_name_map']
        self.cache_version = dict_['cache_version']
