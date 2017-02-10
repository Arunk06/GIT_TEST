# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : syntaxtree
# File name		        : syntaxtree.pyx
# Usage			        : Used to create a parse tree.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 27/03/2015
#       Bug fix for specified RDF filename (see commented code)
# Mod2: hari on 27/03/2015
#       RDF file versioning to be made optional because AIRDATS-E
#       does not want it (requested by SED, Chandrashekhar)
#       * shifted Mod2 from evaluatetree.pyx
# Mod3: hari on 22/06/2015
#       Versioned RDF should have the format filename.rdf;00 instead of 
#       filename{00000}.rdf.
#       Refer: IV & V Report No. ADA/LCA/IVV/FCS/57/2015 dated 09/06/2015
#       * shifted Mod4 from evaluatetree.pyx
# Mod4: hari on 02/07/2015
#       User functions need not be expanded in RDF by default. To make a 
#       function expandable put a "*" character immediately after the
#       function name in the function declaration. 
#       (requested by SED, Chandrashekhar)

from os.path import basename, splitext

import cfg
from errorhandler import EvaluationError


# BEGIN base classes
# List of bases classes used in this file:
#
# 1. Node
# 2. DelayedError
# 3. SymbolAccess
# 4. SymbolStatementList
# 5. Tip
# 6. TipLoad
# 7. TipFill
# 8. TipDump

# The node base class.
class Node(object):
    def __init__(self, node_type='unknown', source_info=None):
        self.node_type = node_type
        self.source_info = source_info

    # Implemented in derived classes.
    def evaluate(self):
        pass

    def traverse(self, parent=None):
        pass

    def to_text(self):
        return '<not implemented>'


class DelayedError(Node):
    def __init__(self, message, source_info=None):
        super(DelayedError, self).__init__(node_type='derror', source_info=source_info)
        self.message = str(message)
        self.source_info = source_info

    def to_text(self):
        return '<skipped>'


class SymbolAccess(Node):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(SymbolAccess, self).__init__(node_type='sym', source_info=source_info)
        self.symtab_entry = cfg.symbol_table.get_entry(name)
        self.name = name
        self.user_mask = user_mask
        self.user_offset = user_offset

    def to_text(self):
        return '%s(%s) + %s' % (str(self.name), self.user_mask.to_text()[2:], self.user_offset.to_text())


class SymbolStatementList(Node):
    def __init__(self, children, source_info=None):
        super(SymbolStatementList, self).__init__(node_type='sym_lst', source_info=source_info)
        self.children = children

    def to_text(self):
        temp_stmt = ''
        for n in self.children:
            temp_stmt += n.to_text()
            if self.children.index(n) < len(self.children) - 1:
                temp_stmt += ' &'
        return temp_stmt


class Tip(Node):
    def __init__(self, tip_cmd, source_info=None):
        super(Tip, self).__init__(node_type='tip_' + tip_cmd, source_info=source_info)
        self.mask = 0b1111

    def add_mask(self, mask):
        self.mask = mask


class TipLoad(Tip):
    def __init__(self, load_cmd, start_address, data_list, source_info=None):
        super(TipLoad, self).__init__(tip_cmd=load_cmd, source_info=source_info)
        self.load_cmd = load_cmd
        self.start_address = start_address
        self.data_list = data_list

    def to_text(self):
        return 'tip # %s %s %s' % (
            self.load_cmd, self.start_address.to_text(), ' '.join([data.to_text() for data in self.data_list]))


class TipFill(Tip):
    def __init__(self, fill_cmd, start_address, end_address, data, source_info=None):
        super(TipFill, self).__init__(tip_cmd=fill_cmd, source_info=source_info)
        self.fill_cmd = fill_cmd
        self.start_address = start_address
        self.end_address = end_address
        self.data = data

    def to_text(self):
        return 'tip # %s %s %s %s' % (
            self.fill_cmd, self.start_address.to_text(), self.end_address.to_text(), self.data.to_text())


class TipDump(Tip):
    def __init__(self, dump_cmd, start_address, end_address, source_info=None):
        super(TipDump, self).__init__(tip_cmd=dump_cmd, source_info=source_info)
        self.dump_cmd = dump_cmd
        self.start_address = start_address
        self.end_address = end_address

    def to_text(self):
        return 'tip # %s %s %s' % (self.dump_cmd, self.start_address.to_text(), self.end_address.to_text())


# END base classes

class DelayedParseError(DelayedError):
    """The class for handling parse errors.
                                                                                                                             
    This class issues appropriate exception message for parse errors.
    """
    def __init__(self, message, source_info):
        """The constructor.
                                                                                                                             
        It calls the base class constructor with the message to be displayed,
        the name of the source which produced the error and the line number
        in that source.
        """
        super(DelayedParseError, self).__init__("Parse Error (%s): %s." % (source_info, message), source_info)


# The arithmetic group.
class Add(Node):
    def __init__(self, left, right, source_info=None):
        super(Add, self).__init__(node_type='add', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s + %s' % (self.left.to_text(), self.right.to_text())


class Subtract(Node):
    def __init__(self, left, right, source_info=None):
        super(Subtract, self).__init__(node_type='sub', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s - %s' % (self.left.to_text(), self.right.to_text())


class Multiply(Node):
    def __init__(self, left, right, source_info=None):
        super(Multiply, self).__init__(node_type='mul', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s * %s' % (self.left.to_text(), self.right.to_text())


class Divide(Node):
    def __init__(self, left, right, source_info=None):
        super(Divide, self).__init__(node_type='div', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s / %s' % (self.left.to_text(), self.right.to_text())


class Modulo(Node):
    def __init__(self, left, right, source_info=None):
        super(Modulo, self).__init__(node_type='mod', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s %% %s' % (self.left.to_text(), self.right.to_text())


class Minus(Node):
    def __init__(self, left, source_info=None):
        super(Minus, self).__init__(node_type='usub', source_info=source_info)
        self.left = left

    def to_text(self):
        return '- %s' % self.left.to_text()


class Plus(Node):
    def __init__(self, left, source_info=None):
        super(Plus, self).__init__(node_type='uadd', source_info=source_info)
        self.left = left

    def to_text(self):
        return '+ %s' % self.left.to_text()


# The logical group.
class Not(Node):
    def __init__(self, left, source_info=None):
        super(Not, self).__init__(node_type='not', source_info=source_info)
        self.left = left

    def to_text(self):
        return 'not %s' % self.left.to_text()


class Or(Node):
    def __init__(self, left, right, source_info=None):
        super(Or, self).__init__(node_type='or', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s or %s' % (self.left.to_text(), self.right.to_text())


class And(Node):
    def __init__(self, left, right, source_info=None):
        super(And, self).__init__(node_type='and', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s and %s' % (self.left.to_text(), self.right.to_text())


class BitNot(Node):
    def __init__(self, left, source_info=None):
        super(BitNot, self).__init__(node_type='notb', source_info=source_info)
        self.left = left

    def to_text(self):
        return 'notb %s' % self.left.to_text()


class BitOr(Node):
    def __init__(self, left, right, source_info=None):
        super(BitOr, self).__init__(node_type='orb', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s orb %s' % (self.left.to_text(), self.right.to_text())


class BitXOr(Node):
    def __init__(self, left, right, source_info=None):
        super(BitXOr, self).__init__(node_type='xorb', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s xorb %s' % (self.left.to_text(), self.right.to_text())


class BitAnd(Node):
    def __init__(self, left, right, source_info=None):
        super(BitAnd, self).__init__(node_type='andb', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s andb %s' % (self.left.to_text(), self.right.to_text())


class LeftShift(Node):
    def __init__(self, left, right, source_info=None):
        super(LeftShift, self).__init__(node_type='lsh', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s << %s' % (self.left.to_text(), self.right.to_text())


class RightShift(Node):
    def __init__(self, left, right, source_info=None):
        super(RightShift, self).__init__(node_type='rsh', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s >> %s' % (self.left.to_text(), self.right.to_text())


class In(Node):
    def __init__(self, expr, range_expr, source_info=None):
        super(In, self).__init__(node_type='in', source_info=source_info)
        self.expr = expr
        self.range_expr = range_expr

    def to_text(self):
        return '%s = %s?' % (self.expr.to_text(), self.range_expr.to_text())


class BypassIn(Node):
    def __init__(self, expr, range_expr, source_info=None):
        super(BypassIn, self).__init__(node_type='bin', source_info=source_info)
        self.expr = expr
        self.range_expr = range_expr

    def to_text(self):
        return '%s =" %s?' % (self.expr.to_text(), self.range_expr.to_text())


class NotIn(Node):
    def __init__(self, expr, range_expr, source_info=None):
        super(NotIn, self).__init__(node_type='not_in', source_info=source_info)
        self.expr = expr
        self.range_expr = range_expr

    def to_text(self):
        return '%s <> %s?' % (self.expr.to_text(), self.range_expr.to_text())


class BypassNotIn(Node):
    def __init__(self, expr, range_expr, source_info=None):
        super(BypassNotIn, self).__init__(node_type='bnot_in', source_info=source_info)
        self.expr = expr
        self.range_expr = range_expr

    def to_text(self):
        return '%s <>" %s?' % (self.expr.to_text(), self.range_expr.to_text())


# The equality group.
class EqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(EqualTo, self).__init__(node_type='eq', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s == %s' % (self.left.to_text(), self.right.to_text())


class NotEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(NotEqualTo, self).__init__(node_type='ne', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s <> %s' % (self.left.to_text(), self.right.to_text())


class ChannelEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelEqualTo, self).__init__(node_type='ceq', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s = %s?' % (self.left.to_text(), self.right.to_text())


class ChannelBypassEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelBypassEqualTo, self).__init__(node_type='cbeq', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s =" %s?' % (self.left.to_text(), self.right.to_text())


class ChannelNotEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelNotEqualTo, self).__init__(node_type='cne', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s <> %s?' % (self.left.to_text(), self.right.to_text())


class ChannelBypassNotEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelBypassNotEqualTo, self).__init__(node_type='cbne', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s <>" %s?' % (self.left.to_text(), self.right.to_text())


# The relational group.
class LessThan(Node):
    def __init__(self, left, right, source_info=None):
        super(LessThan, self).__init__(node_type='lt', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s < %s' % (self.left.to_text(), self.right.to_text())


class LessThanEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(LessThanEqualTo, self).__init__(node_type='le', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s <= %s' % (self.left.to_text(), self.right.to_text())


class GreaterThan(Node):
    def __init__(self, left, right, source_info=None):
        super(GreaterThan, self).__init__(node_type='gt', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s > %s' % (self.left.to_text(), self.right.to_text())


class GreaterThanEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(GreaterThanEqualTo, self).__init__(node_type='ge', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s >= %s' % (self.left.to_text(), self.right.to_text())


class ChannelLessThan(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelLessThan, self).__init__(node_type='clt', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s < %s?' % (self.left.to_text(), self.right.to_text())


class ChannelBypassLessThan(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelBypassLessThan, self).__init__(node_type='cblt', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s <" %s?' % (self.left.to_text(), self.right.to_text())


class ChannelLessThanEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelLessThanEqualTo, self).__init__(node_type='cle', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s <= %s?' % (self.left.to_text(), self.right.to_text())


class ChannelBypassLessThanEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelBypassLessThanEqualTo, self).__init__(node_type='cble', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s <=" %s?' % (self.left.to_text(), self.right.to_text())


class ChannelGreaterThan(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelGreaterThan, self).__init__(node_type='cgt', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s > %s?' % (self.left.to_text(), self.right.to_text())


class ChannelBypassGreaterThan(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelBypassGreaterThan, self).__init__(node_type='cbgt', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s >" %s?' % (self.left.to_text(), self.right.to_text())


class ChannelGreaterThanEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelGreaterThanEqualTo, self).__init__(node_type='cge', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s >= %s?' % (self.left.to_text(), self.right.to_text())


class ChannelBypassGreaterThanEqualTo(Node):
    def __init__(self, left, right, source_info=None):
        super(ChannelBypassGreaterThanEqualTo, self).__init__(node_type='cbge', source_info=source_info)
        self.left = left
        self.right = right

    def to_text(self):
        return '%s >=" %s?' % (self.left.to_text(), self.right.to_text())


# The assignment operator.
class Assign(Node):
    def __init__(self, l_value, r_value, source_info=None):
        super(Assign, self).__init__(node_type='assign', source_info=source_info)
        self.l_value = l_value
        self.r_value = r_value

    def to_text(self):
        return '%s := %s' % (self.l_value.to_text(), self.r_value.to_text())


class ChannelAssign(Node):
    def __init__(self, l_value, r_value, source_info=None):
        super(ChannelAssign, self).__init__(node_type='cassign')
        self.l_value = l_value
        self.r_value = r_value

    def to_text(self):
        return '%s = %s' % (self.l_value.to_text(), self.r_value.to_text())


class ChannelBypassAssign(Node):
    def __init__(self, l_value, r_value, source_info=None):
        super(ChannelBypassAssign, self).__init__(node_type='cbassign', source_info=source_info)
        self.l_value = l_value
        self.r_value = r_value

    def to_text(self):
        return '%s =" %s' % (self.l_value.to_text(), self.r_value.to_text())


# The expression elements group.
class Range(Node):
    def __init__(self, lower, upper, source_info=None):
        super(Range, self).__init__(node_type='rng', source_info=source_info)
        self.lower = lower
        self.upper = upper

    def to_text(self):
        return '(%s, %s)' % (self.lower.to_text(), self.upper.to_text())


class Tolerance(Node):
    def __init__(self, base, tolerance, source_info=None):
        super(Tolerance, self).__init__(node_type='tlr', source_info=source_info)
        self.base = base
        self.tolerance = tolerance
        self.begin = 0
        self.end = 0

    def to_text(self):
        return '(%s, %s)' % (self.begin, self.end)


class Identifier(Node):
    def __init__(self, name, source_info=None):
        super(Identifier, self).__init__(node_type='id', source_info=source_info)
        self.name = name

    def get_name(self):
        return self.name

    def to_text(self):
        try:
            return '%s[=%s]' % (str(self.name), str(cfg.symbol_table.get_entry(self.name).value))
        except KeyError:
            message = "Unknown name '%s', not a variable or symbol" % self.name
            raise EvaluationError(message, self.source_info)


class SPILSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(SPILSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class CCDLInSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(CCDLInSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class CCDLOutSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(CCDLOutSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class CCDLTaskSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(CCDLTaskSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class DPFSSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(DPFSSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class SIMPROCInSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(SIMPROCInSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class SIMPROCOutSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(SIMPROCOutSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class SIMPROCTaskSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(SIMPROCTaskSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class RS422InSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(RS422InSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class RS422OutSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(RS422OutSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class MIL1553BInSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(MIL1553BInSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class MIL1553BOutSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(MIL1553BOutSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class MIL1553BTaskSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(MIL1553BTaskSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class RS422TaskSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(RS422TaskSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class RS422ErrorSymbolAccess(SymbolAccess):
    def __init__(self, name, user_mask, user_offset, source_info=None):
        super(RS422ErrorSymbolAccess, self).__init__(name, user_mask, user_offset, source_info=source_info)


class String(Node):
    def __init__(self, value, source_info=None):
        super(String, self).__init__(node_type='str', source_info=source_info)
        self.value = value

    def to_text(self):
        return "'%s'" % str(self.value)


class Integer(Node):
    def __init__(self, value, source_info=None):
        super(Integer, self).__init__(node_type='int', source_info=source_info)
        self.value = value

    def to_text(self):
        return str(self.value)


class Hexadecimal(Node):
    def __init__(self, value, source_info=None):
        super(Hexadecimal, self).__init__(node_type='hex', source_info=source_info)
        self.value = value

    def to_text(self):
        return hex(self.value).split('L')[0]


class Octal(Node):
    def __init__(self, value, source_info=None):
        super(Octal, self).__init__(node_type='oct', source_info=source_info)
        self.value = value

    def to_text(self):
        return oct(self.value)


class Binary(Node):
    def __init__(self, value, source_info=None):
        super(Binary, self).__init__(node_type='bin', source_info=source_info)
        self.value = value

    def to_text(self):
        return bin(self.value)


class Float(Node):
    def __init__(self, value, source_info=None):
        super(Float, self).__init__(node_type='flt', source_info=source_info)
        self.value = value

    def to_text(self):
        return str(self.value)


# The program elements group.
class Empty(Node):
    def __init__(self, source_info=None):
        super(Empty, self).__init__(node_type='empty', source_info=source_info)

    def to_text(self):
        return ''


class FrWait(Node):
    def __init__(self, count, source_info=None):
        super(FrWait, self).__init__(node_type='frwait', source_info=source_info)
        self.count = count

    def to_text(self):
        return 'frwait = %s' % self.count.to_text()


class Wait(Node):
    def __init__(self, delay, source_info=None):
        super(Wait, self).__init__(node_type='wait', source_info=source_info)
        self.delay = delay

    def to_text(self):
        return 'wait = %s' % self.delay.to_text()


class TipWdm(Tip):
    def __init__(self, source_info=None):
        super(TipWdm, self).__init__(tip_cmd='wdm', source_info=source_info)

    def to_text(self):
        return 'tip # wdm'


class TipDmas(Tip):
    def __init__(self, source_info=None):
        super(TipDmas, self).__init__(tip_cmd='dmas', source_info=source_info)

    def to_text(self):
        return 'tip # dmas'


class TipDmar(Tip):
    def __init__(self, source_info=None):
        super(TipDmar, self).__init__(tip_cmd='dmar', source_info=source_info)

    def to_text(self):
        return 'tip # dmar'


class TipMrhp(Tip):
    def __init__(self, address, source_info=None):
        super(TipMrhp, self).__init__(tip_cmd='mrhp', source_info=source_info)
        self.address = address

    def to_text(self):
        return 'tip # mrhp %s' % self.address.to_text()


class TipMrfp(Tip):
    def __init__(self, address, source_info=None):
        super(TipMrfp, self).__init__(tip_cmd='mrfp', source_info=source_info)
        self.address = address

    def to_text(self):
        return 'tip # mrfp %s' % self.address.to_text()


class TipMrhrp(Tip):
    def __init__(self, address, data, source_info=None):
        super(TipMrhrp, self).__init__(tip_cmd='mrhrp', source_info=source_info)
        self.address = address
        self.data = data

    def to_text(self):
        return 'tip # mrhrp %s %s' % (self.address.to_text(), self.data.to_text())


class TipMrfrp(Tip):
    def __init__(self, address, data, source_info=None):
        super(TipMrfrp, self).__init__(tip_cmd='mrfrp', source_info=source_info)
        self.address = address
        self.data = data

    def to_text(self):
        return 'tip # mrfrp %s %s' % (self.address.to_text(), self.data.to_text())


class TipDd(TipDump):
    def __init__(self, start_address, end_address, source_info=None):
        super(TipDd, self).__init__('dd', start_address, end_address, source_info=source_info)


class TipDw(TipDump):
    def __init__(self, start_address, end_address, source_info=None):
        super(TipDw, self).__init__('dw', start_address, end_address, source_info=source_info)


class TipDb(TipDump):
    def __init__(self, start_address, end_address, source_info=None):
        super(TipDb, self).__init__('db', start_address, end_address, source_info=source_info)


class TipFd(TipFill):
    def __init__(self, start_address, end_address, data, source_info=None):
        super(TipFd, self).__init__('fd', start_address, end_address, data, source_info=source_info)


class TipFw(TipFill):
    def __init__(self, start_address, end_address, data, source_info=None):
        super(TipFw, self).__init__('fw', start_address, end_address, data, source_info=source_info)


class TipFb(TipFill):
    def __init__(self, start_address, end_address, data, source_info=None):
        super(TipFb, self).__init__('fb', start_address, end_address, data, source_info=source_info)


class TipLd(TipLoad):
    def __init__(self, start_address, data_list, source_info=None):
        super(TipLd, self).__init__('ld', start_address, data_list, source_info=source_info)


class TipLw(TipLoad):
    def __init__(self, start_address, data_list, source_info=None):
        super(TipLw, self).__init__('lw', start_address, data_list, source_info=source_info)


class TipLb(TipLoad):
    def __init__(self, start_address, data_list, source_info=None):
        super(TipLb, self).__init__('lb', start_address, data_list, source_info=source_info)


class TipCs(Tip):
    def __init__(self, start_address, end_address, source_info=None):
        super(TipCs, self).__init__(tip_cmd='cs', source_info=source_info)
        self.start_address = start_address
        self.end_address = end_address

    def to_text(self):
        return 'tip # cs %s %s' % (self.start_address.to_text(), self.end_address.to_text())


class TipEprNDsb(Tip):
    def __init__(self, source_info=None):
        super(TipEprNDsb, self).__init__(tip_cmd='eprndsb', source_info=source_info)

    def to_text(self):
        return 'tip # epr n dsb'


class TipEprNEnb(Tip):
    def __init__(self, source_info=None):
        super(TipEprNEnb, self).__init__(tip_cmd='eprnenb', source_info=source_info)

    def to_text(self):
        return 'tip # epr n enb'


class TipEprTDsb(Tip):
    def __init__(self, source_info=None):
        super(TipEprTDsb, self).__init__(tip_cmd='eprtdsb', source_info=source_info)

    def to_text(self):
        return 'tip # epr t dsb'


class TipEprTEnb(Tip):
    def __init__(self, source_info=None):
        super(TipEprTEnb, self).__init__(tip_cmd='eprtenb', source_info=source_info)

    def to_text(self):
        return 'tip # epr t enb'


class TipEprNErs(Tip):
    def __init__(self, source_info=None):
        super(TipEprNErs, self).__init__(tip_cmd='eprners', source_info=source_info)

    def to_text(self):
        return 'tip # epr n ers'


class TipEprTErs(Tip):
    def __init__(self, source_info=None):
        super(TipEprTErs, self).__init__(tip_cmd='eprters', source_info=source_info)

    def to_text(self):
        return 'tip # epr t ers'


class TipBo(Tip):
    def __init__(self, source_info=None):
        super(TipBo, self).__init__(tip_cmd='bo', source_info=source_info)

    def to_text(self):
        return 'tip # bo'


class TipDf(Tip):
    def __init__(self, fifo_address, count, source_info=None):
        super(TipDf, self).__init__(tip_cmd='df', source_info=source_info)
        self.fifo_address = fifo_address
        self.count = count

    def to_text(self):
        return 'tip # df %s %s' % (self.fifo_address.to_text(), self.count.to_text())


class TipFfc(Tip):
    def __init__(self, fifo_address, data, count, source_info=None):
        super(TipFfc, self).__init__(tip_cmd='ffc', source_info=source_info)
        self.fifo_address = fifo_address
        self.data = data
        self.count = count

    def to_text(self):
        return 'tip # ffc %s %s %s' % (self.fifo_address.to_text(), self.data.to_text(), self.count.to_text())


class TipFfi(Tip):
    def __init__(self, fifo_address, initial_data, count, source_info=None):
        super(TipFfi, self).__init__(tip_cmd='ffi', source_info=source_info)
        self.fifo_address = fifo_address
        self.initial_data = initial_data
        self.count = count

    def to_text(self):
        return 'tip # ffi %s %s %s' % (self.fifo_address.to_text(), self.initial_data.to_text(), self.count.to_text())


class TipMtd(Tip):
    def __init__(self, start_address, end_address, bit, source_info=None):
        super(TipMtd, self).__init__(tip_cmd='mtd', source_info=source_info)
        self.start_address = start_address
        self.end_address = end_address
        self.bit = bit

    def to_text(self):
        return 'tip # mtd %s %s %s' % (self.start_address.to_text(), self.end_address.to_text(), self.bit.to_text())


class TipMtw(Tip):
    def __init__(self, start_address, end_address, bit, source_info=None):
        super(TipMtw, self).__init__(tip_cmd='mtw', source_info=source_info)
        self.start_address = start_address
        self.end_address = end_address
        self.bit = bit

    def to_text(self):
        return 'tip # mtw %s %s %s' % (self.start_address.to_text(), self.end_address.to_text(), self.bit.to_text())


class TipMtb(Tip):
    def __init__(self, start_address, end_address, bit, source_info=None):
        super(TipMtb, self).__init__(tip_cmd='mtb', source_info=source_info)
        self.start_address = start_address
        self.end_address = end_address
        self.bit = bit

    def to_text(self):
        return 'tip # mtb %s %s %s' % (self.start_address.to_text(), self.end_address.to_text(), self.bit.to_text())


class TipVr(Tip):
    def __init__(self, start_address, end_address, data, source_info=None):
        super(TipVr, self).__init__(tip_cmd='vr', source_info=source_info)
        self.start_address = start_address
        self.end_address = end_address
        self.data = data

    def to_text(self):
        return 'tip # vr %s %s %s' % (self.start_address.to_text(), self.end_address.to_text(), self.data.to_text())


class TipP(Tip):
    def __init__(self, source_info=None):
        super(TipP, self).__init__(tip_cmd='p', source_info=source_info)

    def to_text(self):
        return '<skipped>'  # return 'tip # p'


class TipPl(Tip):
    def __init__(self, source_info=None):
        super(TipPl, self).__init__(tip_cmd='pl', source_info=source_info)

    def to_text(self):
        return 'tip # pl'


class Comment(Node):
    def __init__(self, text, source_info=None):
        super(Comment, self).__init__(node_type='cmnt', source_info=source_info)
        self.text = text

    def to_text(self):
        return str(self.text)


class InputListing(Node):
    def __init__(self, text, source_info=None):
        super(InputListing, self).__init__(node_type='listing', source_info=source_info)
        self.text = text

    def to_text(self):
        return str(self.text)


class Expression(Node):
    def __init__(self, child, source_info=None):
        super(Expression, self).__init__(node_type='exp', source_info=source_info)
        self.child = child

    def traverse(self, parent=None):
        self.child.traverse(parent)

    def delayed_evaluate(self):
        pass

    def to_text(self):
        return self.child.to_text()


class FinalValueExpression(Node):
    def __init__(self, child, source_info=None):
        super(FinalValueExpression, self).__init__(node_type='fvexp', source_info=source_info)
        self.child = child
        self.final_value = 0

    def traverse(self, parent=None):
        self.child.traverse(parent)

    def delayed_evaluate(self):
        pass

    def to_text(self):
        return str(self.final_value)


class FinalValueExpressionHex(Node):
    def __init__(self, child, source_info=None):
        super(FinalValueExpressionHex, self).__init__(node_type='fvexph', source_info=source_info)
        self.child = child
        self.final_value = 0

    def traverse(self, parent=None):
        self.child.traverse(parent)

    def delayed_evaluate(self):
        pass

    def to_text(self):
        return hex(self.final_value).split('L')[0]


class FinalValueExpressionBin(Node):
    def __init__(self, child, source_info=None):
        super(FinalValueExpressionBin, self).__init__(node_type='fvexpb', source_info=source_info)
        self.child = child
        self.final_value = 0

    def traverse(self, parent=None):
        self.child.traverse(parent)

    def delayed_evaluate(self):
        pass

    def to_text(self):
        return bin(self.final_value)


class FinalValueExpressionString(Node):
    def __init__(self, child, source_info=None):
        super(FinalValueExpressionString, self).__init__(node_type='fvexps', source_info=source_info)
        self.child = child
        self.final_value = ""

    def traverse(self, parent=None):
        self.child.traverse(parent)

    def delayed_evaluate(self):
        pass

    def to_text(self):
        return str(self.final_value)


class If(Node):
    def __init__(self, gated_statement_list, source_info=None):
        super(If, self).__init__(node_type='if', source_info=source_info)
        self.gated_statement_list = gated_statement_list

    def to_text(self):
        return ''  # ('if %s then %s else %s') % (self.expr.to_text(), self.if_stmt.to_text(), self.else_stmt.to_text())


class While(Node):
    def __init__(self, expr, stmt, source_info=None):
        super(While, self).__init__(node_type='while', source_info=source_info)
        self.expr = expr
        self.stmt = stmt

    def to_text(self):
        return 'while %s do' % self.expr.to_text()  # (self.expr.to_text(), self.stmt.to_text())


class Wfc(Node):
    def __init__(self, wait_value, sym_stmt, source_info=None):
        super(Wfc, self).__init__(node_type='wfc', source_info=source_info)
        self.wait_value = wait_value
        self.sym_stmt = sym_stmt

    def to_text(self):
        return 'wfc maxwait = %s %s' % (self.wait_value.to_text(), self.sym_stmt.to_text())


class Break(Node):
    def __init__(self, source_info=None):
        super(Break, self).__init__(node_type='break', source_info=source_info)

    def to_text(self):
        return 'break'


class Continue(Node):
    def __init__(self, source_info=None):
        super(Continue, self).__init__(node_type='cont', source_info=source_info)

    def to_text(self):
        return 'continue'


class Display(Node):
    def __init__(self, expr, source_info=None):
        super(Display, self).__init__(node_type='disp', source_info=source_info)
        self.expr = expr

    def to_text(self):
        return 'display %s' % self.expr.to_text()


class Logging(Node):
    def __init__(self, expr, source_info=None):
        super(Logging, self).__init__(node_type='log', source_info=source_info)
        self.expr = expr

    def to_text(self):
        return 'logging %s' % self.expr.to_text()


class Print(Node):
    def __init__(self, expr_list, source_info=None):
        super(Print, self).__init__(node_type='print', source_info=source_info)
        self.expr_list = expr_list

    def to_text(self):
        temp_stmt = ', '.join(map(lambda n: n.to_text(), self.expr_list))
        return 'print %s' % temp_stmt


class LtmSytax(Node):
    def __init__(self, message, source_info=None):
        super(LtmSytax, self).__init__(node_type='ltmsyn', source_info=source_info)
        self.message = message

    def to_text(self):
        return ''


class Download(Node):
    def __init__(self, file_name, user_mask, source_info=None):
        super(Download, self).__init__(node_type='download', source_info=source_info)
        self.file_name = file_name
        self.user_mask = user_mask

    def to_text(self):
        return 'download = %s' % self.file_name.to_text()


class Upload(Node):
    def __init__(self, file_name, start_address, end_address, source_info=None):
        super(Upload, self).__init__(node_type='upload', source_info=source_info)
        self.file_name = file_name
        self.start_address = start_address
        self.end_address = end_address

    def to_text(self):
        return 'upload = %s, %s, %s' % (
            self.file_name.to_text(), self.start_address.to_text(), self.end_address.to_text())


class Verify(Node):
    def __init__(self, file_name, start_address, end_address, source_info=None):
        super(Verify, self).__init__(node_type='verify', source_info=source_info)
        self.file_name = file_name
        self.start_address = start_address
        self.end_address = end_address

    def to_text(self):
        return 'verify = %s, %s, %s' % (
            self.file_name.to_text(), self.start_address.to_text(), self.end_address.to_text())


class Dchan(Node):
    def __init__(self, global_mask, source_info=None):
        super(Dchan, self).__init__(node_type='dchan', source_info=source_info)
        self.global_mask = global_mask

    def to_text(self):
        return 'dchan = %s' % self.global_mask.to_text()


class List(Node):
    def __init__(self, filename_pattern, name_pattern, source_info=None):
        super(List, self).__init__(node_type='list', source_info=source_info)
        self.filename_pattern = filename_pattern
        self.name_pattern = name_pattern

    def to_text(self):
        return 'list %s : %s' % (self.filename_pattern, self.name_pattern)


class OpMsg(Node):
    def __init__(self, message='', source_info=None):
        super(OpMsg, self).__init__(node_type='opmsg', source_info=source_info)
        self.message = message

    def to_text(self):
        return 'opmsg %s' % self.message


class OpWait(Node):
    def __init__(self, message='', source_info=None):
        super(OpWait, self).__init__(node_type='opwt', source_info=source_info)
        self.message = message

    def to_text(self):
        return 'opwait %s' % self.message


class Exit(Node):
    def __init__(self, source_info=None):
        super(Exit, self).__init__(node_type='exit', source_info=source_info)

    def to_text(self):
        return 'exit'


class Assert(Node):
    def __init__(self, expr, message='Assertion failed', source_info=None):
        super(Assert, self).__init__(node_type='assert', source_info=source_info)
        self.expr = expr
        self.message = message

    def to_text(self):
        return 'assert %s, %s' % (self.expr.to_text(), self.message)


class Locate(Node):
    def __init__(self, loc_list, source_info=None):
        super(Locate, self).__init__(node_type='loc', source_info=source_info)
        self.loc_list = loc_list

    def to_text(self):
        return 'locate %s' % (', '.join(self.loc_list))


class Delete(Node):
    def __init__(self, del_list, source_info=None):
        super(Delete, self).__init__(node_type='del', source_info=source_info)
        self.del_list = del_list

    def to_text(self):
        return 'delete %s' % (', '.join(self.del_list))


class Expand(Node):
    def __init__(self, expand_list, source_info=None):
        super(Expand, self).__init__(node_type='expand', source_info=source_info)
        self.expand_list = expand_list

    def to_text(self):
        return 'expand %s' % (', '.join(self.expand_list))


class PrintSymbol(Node):
    def __init__(self, expr, source_info=None):
        super(PrintSymbol, self).__init__(node_type='psym_stmt', source_info=source_info)
        self.expr = expr

    def to_text(self):
        return '%s = ?' % self.expr.to_text()


class PrintBypassSymbol(Node):
    def __init__(self, expr, source_info=None):
        super(PrintBypassSymbol, self).__init__(node_type='pbsym_stmt', source_info=source_info)
        self.expr = expr

    def to_text(self):
        return '%s =" ?' % self.expr.to_text()


class SPILSymbolStatementList(SymbolStatementList):
    def __init__(self, children, source_info=None):
        super(SPILSymbolStatementList, self).__init__(children, source_info=source_info)


class RS422SymbolStatementList(SymbolStatementList):
    def __init__(self, children, source_info=None):
        super(RS422SymbolStatementList, self).__init__(children, source_info=source_info)


class Statement(Node):
    def __init__(self, stmt_list, source_info=None):
        super(Statement, self).__init__(node_type='stmt', source_info=source_info)
        self.stmt_list = stmt_list

    # This is used by loop statements to process their child statements 
    # under their own control (see 'evaluatetree.py' class 'While').
    def get_statements(self):
        return self.stmt_list

    def to_text(self):
        temp_stmt = ''
        for n in self.stmt_list:
            temp_stmt += n.to_text()
            if self.stmt_list.index(n) < len(self.stmt_list) - 1:
                temp_stmt += '\n'
        return temp_stmt


class Function(Node):
    # Mod4: begin
    def __init__(self, name, stmt, silent=True, source_info=None):
        # Mod4: end
        super(Function, self).__init__(node_type='func', source_info=source_info)
        self.name = name
        self.stmt = stmt
        # Mod4: begin
        self.silent = silent
        # Mod4: end

    def to_text(self):
        # Mod4: begin
        return 'function = %s %s' % (str(self.name), '' if self.silent else '*')
        # Mod4: end


class ParameterNumber(Node):
    def __init__(self, number, source_info=None):
        super(ParameterNumber, self).__init__(node_type='func', source_info=source_info)
        self.number = number

    def to_text(self):
        return '$(%s)' % (self.number.to_text())


class FunctionSystem(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionSystem, self).__init__(node_type='func_system', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionStr(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionStr, self).__init__(node_type='func_str', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionHex(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionHex, self).__init__(node_type='func_hex', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionOct(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionOct, self).__init__(node_type='func_oct', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionBin(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionBin, self).__init__(node_type='func_bin', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionLeftShift(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionLeftShift, self).__init__(node_type='func_ls', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionRightShift(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionRightShift, self).__init__(node_type='func_rs', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionBitAnd(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionBitAnd, self).__init__(node_type='func_ba', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionBitOr(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionBitOr, self).__init__(node_type='func_bo', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionBitXor(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionBitXor, self).__init__(node_type='func_bx', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionPow(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionPow, self).__init__(node_type='func_pw', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionTime(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionTime, self).__init__(node_type='func_time', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionSin(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionSin, self).__init__(node_type='func_sin', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionCos(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionCos, self).__init__(node_type='func_cos', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionTan(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionTan, self).__init__(node_type='func_tan', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionInputInt(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionInputInt, self).__init__(node_type='func_ii', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionInputFloat(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionInputFloat, self).__init__(node_type='func_if', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionInputStr(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionInputStr, self).__init__(node_type='func_is', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionGetWdm(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionGetWdm, self).__init__(node_type='func_gw', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionSetWdm(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionSetWdm, self).__init__(node_type='func_sw', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionChannelEnabled(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionChannelEnabled, self).__init__(node_type='func_ce', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionInRange(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionInRange, self).__init__(node_type='func_ir', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionFrameNumber(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionFrameNumber, self).__init__(node_type='func_frm', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionInit1553B(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionInit1553B, self).__init__(node_type='func_1553', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionMessageMsgType(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionMessageMsgType, self).__init__(node_type='', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionMessageRTAddr(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionMessageRTAddr, self).__init__(node_type='', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionMessageRTSubAddr(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionMessageRTSubAddr, self).__init__(node_type='', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionMessageWCntMCode(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionMessageWCntMCode, self).__init__(node_type='', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionMessageMsgGap(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionMessageMsgGap, self).__init__(node_type='', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionMessageInfo(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionMessageInfo, self).__init__(node_type='', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionMessageDefined(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionMessageDefined, self).__init__(node_type='', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionChannelValue(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionChannelValue, self).__init__(node_type='func_cv', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionFileAccess(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionFileAccess, self).__init__(node_type='func_fa', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionFileDownloadPath(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionFileDownloadPath, self).__init__(node_type='func_fdp', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionFileUploadPath(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionFileUploadPath, self).__init__(node_type='func_fup', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionGetUUT(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionGetUUT, self).__init__(node_type='func_guut', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionGetVersion(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionGetVersion, self).__init__(node_type='func_gver', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class FunctionInvocation(Node):
    def __init__(self, name, param_lst, source_info=None):
        super(FunctionInvocation, self).__init__(node_type='func_invoc', source_info=source_info)
        self.name = name
        self.param_lst = param_lst

    def to_text(self):
        return '%s' % (str(self.name))


class LocalIdentifier(Node):
    def __init__(self, name, source_info=None):
        super(LocalIdentifier, self).__init__(node_type='loc_id', source_info=source_info)
        self.name = name

    def to_text(self):
        return '$%s' % (str(self.name))


class Return(Node):
    def __init__(self, expr, source_info=None):
        super(Return, self).__init__(node_type='ret', source_info=source_info)
        self.expr = expr

    def to_text(self):
        return 'return %s' % (self.expr.to_text())


class MacroInvocation(Node):
    def __init__(self, name, source_info=None):
        super(MacroInvocation, self).__init__(node_type='macinvoc', source_info=source_info)
        self.name = name
        self.entry = cfg.symbol_table.get_entry(name)

    def to_text(self):
        return 'macname = %s' % (str(self.name))


class Pass(Node):
    def __init__(self, source_info=None):
        super(Pass, self).__init__(node_type='pass', source_info=source_info)

    def to_text(self):
        return 'pass'


class Patch(Node):
    def __init__(self, channel_number_expr, source_info=None):
        super(Patch, self).__init__(node_type='patch', source_info=source_info)
        self.channel_number_expr = channel_number_expr

    def to_text(self):
        return 'patch %s' % (self.channel_number_expr.to_text())


class Diffs(Node):
    def __init__(self, channel_number_expr, source_info=None):
        super(Diffs, self).__init__(node_type='diffs', source_info=source_info)
        self.channel_number_expr = channel_number_expr

    def to_text(self):
        return 'diffs %s' % (self.channel_number_expr.to_text())


class Info(Node):
    def __init__(self, info_name, source_info=None):
        super(Info, self).__init__(node_type='info', source_info=source_info)
        self.info_name = info_name

    def to_text(self):
        return 'info %s' % self.info_name


class Program(Node):
    def __init__(self, child, name=None, user_rdfname=None, source_info=None):
        super(Program, self).__init__(node_type='prgm', source_info=source_info)
        self.name = name
        self.child = child
        self.rdfname = None
        self.rdf_error_flag = 0
        if self.name:
            self.rdfname = self.__generate_rdfname()
        if user_rdfname:
            # Mod1: begin
            self.rdfname = cfg.config_file.get_rdfpath(user_rdfname)
            # Mod1: end

        # Mod2: begin
        if self.rdfname and (cfg.config_file.get_value("rdfversions") == "true"):
            self.rdfname = self.__get_new_rdfname()
            # Mod2: end

    def __generate_rdfname(self):
        prg_name_ext = basename(self.name)
        prg_name, prg_ext = splitext(prg_name_ext)

        if (prg_ext.lower() == '.tpf') or (prg_ext.lower() == '.tst'):
            return cfg.config_file.get_rdfpath(prg_name + '.rdf')
        else:
            return None

    def __get_new_rdfname(self):
        # 28/01/2015: hari
        # RFA without a number dated 27/01/2015
        # "1.c For every test conducted for particular interface, separate RDF is required to
        # be generated with version number like in ETS system (At present , it appends
        # to same RDF)"
        from glob import glob
        import os

        # Mod3: begin
        files = glob("%s;*" % self.rdfname)
        # Mod3: end
        files.sort()

        if len(files) == 0:
            cur_num = 0
        else:
            try:
                # Mod3: begin
                cur_num = int(os.path.basename(files[-1])[-2:])
                # Mod3: end
                cur_num += 1
            except ValueError:
                cur_num = 0
                self.rdf_error_flag = 1

        # Mod3: begin
        # restart file counter for more than 100 files
        if cur_num == 100:
            # Mod3: end
            self.rdf_error_flag = 2
        # Mod3: begin
        cur_num %= 100
        # Mod3: end

        # Mod3: begin
        return "%s;%02d" % (self.rdfname, cur_num)
        # Mod3: end

    def to_text(self):
        return self.child.to_text()
