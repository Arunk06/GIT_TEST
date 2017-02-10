# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : nametype
# File name		        : nametype.pyx
# Usage			        : Handles various types of names in AITESS.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 09/04/2015
#       No idea why this code was put, commenting it out. 
#       Hopefully it wont affect ATP
# Mod2: hari on 02/07/2015
#       Optimized the readable size handling code
# Mod3: hari on 07/07/2015
#       Changing DIS to DIS_16 instead of DIS_8.
#       Refer: TPR No. 20028 dated 27/03/2015 and
#              TPR No. 20032 dated 06/04/2015
# Mod4: hari on 30/09/2015
#       Unified discrete data type handling
# Mod5: hari on 06/01/2016
#       SPIL discrete data type mask bug fix

import cfg
from asizeof import asizeof
from sourceinfo import SourceInfo
from tokens import *


class Type(dict):
    def get_type(self):
        return TokenType.TYP_UNKNOWN

    def get_readable_size(self):
        storage_used = self.get_size()

        # Mod2: begin
        if (storage_used >= 0) and (storage_used < 1024):
            return "%.1f B" % storage_used
        elif (storage_used >= 1024) and (storage_used < 1048576):
            return "%.1f KiB" % (storage_used / 1024.0)
        elif (storage_used >= 1048576) and (storage_used < 1073741824):
            return "%.1f MiB" % (storage_used / 1048576.0)
        elif (storage_used >= 1073741824) and (storage_used < 1099511627776L):
            return "%.1f GiB" % (storage_used / 1073741824.0)
        else:
            return "%.1f B" % storage_used
            # Mod2: end


class Symbol(Type):
    """
    system mask   ->   specified using CHAN in symbol file.
    user mask     ->   specified with symbol usage.
    global mask   ->   specified using DCHAN command.
    """
    def __init__(self, name=None, iotype='undefined', **kwargs):
        super(Symbol, self).__init__(**kwargs)
        self.source_info = cfg.source_stack.get_source_info()

        self.name = name
        self.iotype = iotype
        self.chan = None
        self.addr = None
        self.dtype = None
        self.max_ = None
        self.min_ = None
        self.unit = ''
        self.subsystem = None
        self.struct_ = None
        self.stype = None
        self.ofst1 = None
        self.ofst2 = None
        self.ofst3 = None
        self.ofst4 = None
        self.bias = None
        self.slpe = None
        self.read = None
        self.wrte = None
        self.dest = None
        self.mask = None
        self.tolplus = None
        self.tolminus = None
        self.id_ = None
        self.ofstx = None
        self.mask1 = None
        self.mask2 = None
        self.mask3 = None
        self.mask4 = None
        self.rdbk = None
        self.slpe_text = ''
        self.bias_text = ''

    def get_iotype(self):
        return self.iotype

    def get_chan(self):
        if self.chan is not None:
            return self.chan
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'chan'" % self.name)

    def get_dtype_code(self):
        if self.dtype is not None:
            return self.dtype
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'dtype'" % self.name)

    def get_dtype(self, bypass=False):
        # Mod3: begin
        dtype_map = {'ffp': 4, 'dword': 4, 'word': 2, 'byte': 1, 'u32': 4, 'u16': 2, 'u8': 1, 'dpi': 4, 'spi': 2,
                     's32': 4, 's16': 2, 's8': 1, 'ssi': 1, 'd32': 0x44, 'd16': 0x22, 'd8': 0x11, 'u24': 4, 's24': 4}
        # Mod3: end
        if self.dtype is not None:
            try:
                # Mod1: begin
                r = dtype_map[self.dtype]
                return r
                # Mod1: end
            except KeyError as e:
                raise AttributeError(
                    "Error in database, symbol '%s' has unknown value %s for attribute 'dtype'" % (self.name, e))
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'dtype'" % self.name)

    def get_max(self):
        # Mod3: begin
        max_map = {'ffp': 17.0E+37, 'dword': 4294967295L, 'word': 65535, 'byte': 255, 'u32': 4294967295L, 'u16': 65535,
                   'u8': 255, 'dpi': 2147483647L, 'spi': 32767, 's32': 2147483647L, 's16': 32767, 's8': 127, 'ssi': 127,
                   'd32': 0xFFFFFFFF, 'd16': 0xFFFF, 'd8': 0xFF, 'u24': 16777215, 's24': 8388607}
        # Mod3: end
        if self.max_ is not None:
            return self.max_
        else:
            try:
                return max_map[self.dtype]
            except KeyError:
                raise AttributeError("Error in database, symbol '%s' has no attribute 'max'" % self.name)

    def get_min(self):
        # Mod3: begin
        min_map = {'ffp': -17.0E+37, 'dword': 0, 'word': 0, 'byte': 0, 'u32': 0, 'u16': 0, 'u8': 0, 'dpi': -2147483648L,
                   'spi': -32768, 's32': -2147483648L, 's16': -32768, 's8': -128, 'ssi': -128, 'd32': 0, 'd16': 0,
                   'd8': 0, 'u24': 0, 's24': -8388608}
        # Mod3: end
        if self.min_ is not None:
            return self.min_
        else:
            try:
                return min_map[self.dtype]
            except KeyError:
                raise AttributeError("Error in database, symbol '%s' has no attribute 'min'" % self.name)

    def get_unit(self):
        return self.unit

    def get_subsystem(self):
        if self.subsystem is not None:
            return self.subsystem
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'subsystem'" % self.name)

    def get_struct(self):
        if self.struct_ is not None:
            return self.struct_
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'struct'" % self.name)

    def get_stype(self):
        if self.stype is not None:
            return self.stype
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'stype'" % self.name)

    def get_addr(self):
        if self.addr is not None:
            return self.addr
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'addr'" % self.name)

    def get_ofst1(self):
        if self.ofst1 is not None:
            return self.ofst1
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'ofst1'" % self.name)

    def get_ofst2(self):
        if self.ofst2 is not None:
            return self.ofst2
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'ofst2'" % self.name)

    def get_ofst3(self):
        if self.ofst3 is not None:
            return self.ofst3
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'ofst3'" % self.name)

    def get_ofst4(self):
        if self.ofst4 is not None:
            return self.ofst4
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'ofst4'" % self.name)

    def get_bias(self):
        if self.bias is not None:
            return self.bias
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'bias'" % self.name)

    def get_slpe(self):
        if self.slpe is not None:
            return self.slpe
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'slpe'" % self.name)

    def get_read(self):
        if self.read is not None:
            return self.read
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'read'" % self.name)

    def get_wrte(self):
        if self.wrte is not None:
            return self.wrte
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'wrte'" % self.name)

    def get_dest(self):
        if self.dest is not None:
            return self.dest
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'dest'" % self.name)

    # Mod5: begin
    def get_mask(self, bypass=False):
        # Mod5: end
        # Mod3: begin
        mask_map = {'ffp': 0xFFFFFFFF, 'dword': 0xFFFFFFFF, 'word': 0xFFFF, 'byte': 0xFF, 'u32': 0xFFFFFFFF,
                    'u16': 0xFFFF, 'u8': 0xFF, 'dpi': 0xFFFFFFFF, 'spi': 0xFFFF, 's32': 0xFFFFFFFF, 's16': 0xFFFF,
                    's8': 0xFF, 'ssi': 0xFF, 'd32': 0xFFFFFFFF, 'd16': 0xFFFF, 'd8': 0xFF, 'u24': 0xFFFFFF,
                    's24': 0xFFFFFF}
        # Mod3: end
        # Mod5: begin
        if bypass or (self.mask is None):
            return mask_map[self.get_dtype_code()]
        else:
            return self.mask
            # Mod5: end

    def get_tolplus(self):
        if self.tolplus is not None:
            return self.tolplus
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'tolplus'" % self.name)

    def get_tolminus(self):
        if self.tolminus is not None:
            return self.tolminus
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'tolminus'" % self.name)

    def get_id_(self):
        if self.id_ is not None:
            return self.id_
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'id'" % self.name)

    def get_ofstx(self):
        if self.ofstx is not None:
            return self.ofstx
        else:
            raise AttributeError("Error in database, symbolz '%s' has no attribute 'ofst'" % self.name)

    def get_ofst(self):
        return self.get_ofst1(), self.get_ofst2(), self.get_ofst3(), self.get_ofst4()

    def get_mask1(self):
        if self.mask1 is not None:
            return self.mask1
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'mask1'" % self.name)

    def get_mask2(self):
        if self.mask2 is not None:
            return self.mask2
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'mask2'" % self.name)

    def get_mask3(self):
        if self.mask3 is not None:
            return self.mask3
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'mask3'" % self.name)

    def get_mask4(self):
        if self.mask4 is not None:
            return self.mask4
        else:
            raise AttributeError("Error in database, symbol '%s' has no attribute 'mask4'" % self.name)

    def set_iotype(self, iotype):
        self.iotype = iotype

    def set_chan(self, chan):
        self.chan = chan

    def set_dtype(self, dtype):
        # Mod4: begin
        if dtype in ('dis_8', 'd8'):
            self.dtype = 'd8'
        elif dtype in ('dis', 'dis_16', 'd16'):
            self.dtype = 'd16'
        elif dtype in ('dis_32', 'd32'):
            self.dtype = 'd32'
        else:
            self.dtype = dtype
            # Mod4: end

    def set_max(self, max_):
        self.max_ = max_

    def set_min(self, min_):
        self.min_ = min_

    def set_unit(self, unit):
        self.unit = unit

    def set_subsystem(self, subsystem):
        self.subsystem = subsystem

    def set_struct(self, struct_):
        self.struct_ = struct_

    def set_stype(self, stype):
        self.stype = stype

    def set_addr(self, addr):
        self.addr = addr

    def set_ofst1(self, ofst):
        self.ofst1 = ofst

    def set_ofst2(self, ofst):
        self.ofst2 = ofst

    def set_ofst3(self, ofst):
        self.ofst3 = ofst

    def set_ofst4(self, ofst):
        self.ofst4 = ofst

    def set_bias(self, bias):
        self.bias = bias

    def set_bias_text(self, text):
        self.bias_text = text

    def set_slpe(self, slpe):
        self.slpe = slpe

    def set_slpe_text(self, text):
        self.slpe_text = text

    def set_read(self, read):
        self.read = read

    def set_wrte(self, wrte):
        self.wrte = wrte

    def set_dest(self, dest):
        self.dest = dest

    def set_mask(self, mask):
        self.mask = mask

    def set_tolplus(self, tolplus):
        self.tolplus = tolplus

    def set_tolminus(self, tolminus):
        self.tolminus = tolminus

    def set_id_(self, id_):
        self.id_ = id_

    def set_ofstx(self, ofstx):
        self.ofstx = ofstx

    def set_mask1(self, mask):
        self.mask1 = mask

    def set_mask2(self, mask):
        self.mask2 = mask

    def set_mask3(self, mask):
        self.mask3 = mask

    def set_mask4(self, mask):
        self.mask4 = mask

    def get_type(self):
        """The type of Name.
        
        This method returns the class/type of name (in this case 'symbol').
        """
        return TokenType.TYP_SYMBOL

    def get_size(self):
        total_size = asizeof(self.iotype) + asizeof(self.chan) + asizeof(self.addr) + asizeof(self.dtype) + \
                     asizeof(self.max_) + asizeof(self.min_) + asizeof(self.unit) + asizeof(self.subsystem) + \
                     asizeof(self.struct_) + asizeof(self.stype) + asizeof(self.ofst1) + asizeof(self.ofst2) + \
                     asizeof(self.ofst3) + asizeof(self.ofst4) + asizeof(self.bias) + asizeof(self.slpe) + \
                     asizeof(self.read) + asizeof(self.wrte) + asizeof(self.dest) + asizeof(self.mask) + \
                     asizeof(self.tolplus) + asizeof(self.tolminus) + asizeof(self.id_) + asizeof(self.ofstx) + \
                     asizeof(self.mask1) + asizeof(self.mask2) + asizeof(self.mask3) + asizeof(self.mask4) + asizeof(
            self.rdbk)
        return total_size

    def __str__(self):
        return "%35s %21s %9s" % (self.name, "«symbol:" + self.iotype.lower() + "»", self.get_readable_size())


class Variable(Type):
    def __init__(self, name, value, source_info, **kwargs):
        super(Variable, self).__init__(**kwargs)
        self.source_info = source_info
        self.name = name
        self.value = value

    def get_type(self):
        """The type of Name.
        
        This method returns the class/type of name (in this case 'variable').
        """
        return TokenType.TYP_VARIABLE

    def get_size(self):
        return asizeof(self.value)

    def get_data_type(self):
        return "undefined"

    def __str__(self):
        return "%35s %21s %9s" % (self.name, "«variable:undefined»", self.get_readable_size())


class Macro(Type):
    def __init__(self, name, expansion, **kwargs):
        super(Macro, self).__init__(**kwargs)
        self.source_info = cfg.source_stack.get_source_info()
        self.name = name
        self.expansion = expansion

    def set_expansion(self, expansion):
        self.expansion = expansion

    def get_type(self):
        """The type of Name.
        
        This method returns the class/type of name (in this case 'variable').
        """
        return TokenType.TYP_MACRO

    def expand(self):
        return self.expansion

    def get_size(self):
        return asizeof(self.expansion)

    def __str__(self):
        return "%35s %21s %9s" % (self.name, "«macro»", self.get_readable_size())


class SystemFunction(Type):
    line_number = 0
    def __init__(self, name, node, **kwargs):
        super(SystemFunction, self).__init__(**kwargs)
        SystemFunction.line_number += 1
        self.source_info = SourceInfo("«system»", SystemFunction.line_number)
        self.name = name
        self.node = node

    def set_node(self, node):
        self.node = node

    def get_type(self):
        """The type of Name.
                                                                                                                                                             
        This method returns the class/type of name (in this case 'variable').
        """
        return TokenType.TYP_SYSFUNC

    def get_size(self):
        return asizeof(self.node)

    def __str__(self):
        return "%35s %21s %9s" % (self.name, "«function:system»", self.get_readable_size())


class Function(Type):
    def __init__(self, name, node, **kwargs):
        super(Function, self).__init__(**kwargs)
        self.source_info = cfg.source_stack.get_source_info()
        self.name = name
        self.node = node

    def set_node(self, node):
        self.node = node

    def get_type(self):
        """The type of Name.
        
        This method returns the class/type of name (in this case 'variable').
        """
        return TokenType.TYP_FUNC

    def get_size(self):
        return asizeof(self.node)

    def __str__(self):
        return "%35s %21s %9s" % (self.name, "«function:user»", self.get_readable_size())


class StringVariable(Variable):
    def __init__(self, name, value, source_info):
        super(StringVariable, self).__init__(name, value, source_info)

    def __str__(self):
        return "%35s %21s %9s" % (self.name, "«variable:string»", self.get_readable_size())

    def read(self, *args, **kargs):
        return self.value

    def write(self, *args, **kargs):
        self.value = kargs['value']

    def get_data_type(self):
        return "string"


class NumericVariable(Variable):
    def __init__(self, name, value, source_info):
        super(NumericVariable, self).__init__(name, value, source_info)

    def __str__(self):
        return "%35s %21s %9s" % (self.name, "«variable:numeric»", self.get_readable_size())

    def read(self, *args, **kargs):
        return self.value

    def write(self, *args, **kargs):
        self.value = kargs['value']

    def get_data_type(self):
        return "numeric"
