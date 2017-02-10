# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : parser
# File name		        : parser.pyx
# Usage			        : Handles parsing of AITESS input.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 24/06/2015
#       Bug fix for duplicate line before undefined symbol error in RDF.
# Mod2: hari on 02/07/2015
#       User functions need not be expanded in RDF by default. To make a 
#       function expandable put a "*" character immediately after the
#       function name in the function declaration. 
#       (requested by SED, Chandrashekhar)
# Mod3: hari on 07/07/2015
#       Changing DIS to DIS_16 instead of DIS_8.
#       Refer: TPR No. 20028 dated 27/03/2015 and
#              TPR No. 20032 dated 06/04/2015
# Mod4: hari on 07/07/2015
#       Added support for values beginning with a '+' in max, min, slpe 
#       and bias attributes in symbol declaration statements
# Mod5: hari on 30/09/2015
#       Shifted this logic to nametype.pyx file and made it common for all
#       types of symbols (not only SPIL) see Mod4 in file nametype.pyx

import gc
import os
import re

import cfg
import evaluatetree
import syntaxtree as tree
from errorhandler import ScanError, ParseError, EvaluationError, UserExitError, ExitError, AssertError, \
    GenerateExceptionMessage
from message import NormalMessage
from nametype import Symbol, Macro, Function
from scanner import Scanner
from sourceinfo import SourceInfo
from tokens import Token, TokenType, TokenName

from cpython cimport bool

from inputal import RealTpfFile, PseudoTpfFile

cdef class Parser(object):
    """The parser class.
    
    This is a two pass parser. In the first pass it obtains the tokens from 
    the scanner and populates the symbol table. In the second pass 
    it executes the actions contained in the test plan file.
    """
    cdef public object ans_variable  # = 0
    cdef public unsigned int in_loop  # = False
    cdef public bool in_func  # = False
    cdef public bool skip_evaluation
    cdef public unsigned char profile_level
    cdef public object look, scan, symbol_list_type
    cdef public list look_stack, stmt_lst_with_listing, stmt_lst_with_listing_stack

    def __init__(self):
        """The constructor.
        
        Copies the given scanner instance to object variable.
        """
        #
        self.ans_variable = 0
        self.in_loop = 0
        self.in_func = False
        #
        self.skip_evaluation = False
        self.look = Token()
        # Save the passed scanner object as the instance's scanner object.
        self.scan = Scanner()
        self.look_stack = []
        self.symbol_list_type = None
        self.stmt_lst_with_listing = []
        self.stmt_lst_with_listing_stack = []
        self.profile_level = 0

    def get_profile_level(self):
        return self.profile_level

    def set_profile_level(self, profile_level):
        self.profile_level = profile_level

    def get_skip_evaluation(self):
        return self.skip_evaluation

    def set_skip_evaluation(self, status):
        self.skip_evaluation = status

    def __skip_till_EOL(self):
        while self.look['type'] != TokenType.OPR_NEWLINE:
            self.__move()

        self.__match(TokenType.OPR_NEWLINE)

    def __is_numeric(self, _type):
        return _type in (TokenType.LIT_INT, TokenType.LIT_FLOAT,
                         TokenType.LIT_BIN, TokenType.LIT_HEX, TokenType.LIT_OCT)

    def __move(self):
        """Gets a new token.
        
        This function calls the 'get_token' method of Scanner class 
        to obtain a new token.
        """
        # Assign the new token to 'look' which will be the current token.
        self.look = self.scan.get_token()

    def __match(self, token_type):
        """Matches a given token to the current token.
        
        This function compares the current token to the given token.
        If successful, it performs a move otherwise, it shows an error.
        """
        # Mod1: begin
        if (token_type == TokenType.OPR_NEWLINE) and (self.look['type'] == token_type):
            # Mod1: end
            self.stmt_lst_with_listing.append(tree.InputListing(cfg.source_stack.get_source_line()[:-1],
                                                                source_info=cfg.source_stack.get_source_info()))
        if (token_type == TokenType.LIT_NUMBER) and \
                (self.__is_numeric(self.look['type'])):
            self.__move()
        # If current token and given token are equal.
        elif self.look['type'] == token_type:
            # Perform a move.
            self.__move()
        else:
            if self.look['text'] == TokenName[self.look['type']]:
                message = "General syntax error, expected '%s' but found '%s'" % \
                          (TokenName[token_type], self.look['text'])
            else:
                message = "General syntax error, expected '%s' but found '%s' which is '%s'" % \
                          (TokenName[token_type], self.look['text'], TokenName[self.look['type']])
            raise ParseError(message, cfg.source_stack.get_source_info())

    def __get_bin(self):
        if self.look['type'] == TokenType.OPR_LSQBRACKET:
            self.__match(TokenType.OPR_LSQBRACKET)
            expr = tree.FinalValueExpressionBin(self.__bool(), source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_RSQBRACKET)
        else:
            try:
                expr = tree.Binary(int(('0b' + str(self.look['text'])), 2),
                                   source_info=cfg.source_stack.get_source_info())
                self.__move()
            except (ValueError, TypeError):
                raise ParseError("Value not a binary literal",
                                 cfg.source_stack.get_source_info())

        return expr

    def __get_hex(self):
        if self.look['type'] == TokenType.OPR_LSQBRACKET:
            self.__match(TokenType.OPR_LSQBRACKET)
            expr = tree.FinalValueExpressionHex(self.__bool(), source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_RSQBRACKET)
        else:
            try:
                expr = tree.Hexadecimal(int(('0x' + str(self.look['text'])), 16),
                                        source_info=cfg.source_stack.get_source_info())
                self.__move()
            except (ValueError, TypeError):
                raise ParseError("Value not a hexadecimal literal",
                                 cfg.source_stack.get_source_info())

        return expr

    def __get_text(self, separated=False):
        text = ''

        while self.look['type'] != TokenType.OPR_NEWLINE:
            if separated:
                text += self.look['text'] + ' '
            else:
                text += self.look['text']
            self.__move()

        return text

    def __get_filename(self):
        if self.look['type'] == TokenType.OPR_LSQBRACKET:
            self.__match(TokenType.OPR_LSQBRACKET)
            expr = tree.FinalValueExpressionString(self.__bool(), source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_RSQBRACKET)
        else:
            filename = ''
            while self.look['type'] != TokenType.OPR_COMMA:
                if self.look['type'] == TokenType.OPR_NEWLINE:
                    break
                filename += self.look['text']
                self.__move()

            if len(filename) == 0:
                raise ParseError("Empty filename", cfg.source_stack.get_source_info())
            expr = tree.String(filename, source_info=cfg.source_stack.get_source_info())

        return expr

    def __translate_vax_filespec(self):
        filename = ''
        while self.look['type'] != TokenType.OPR_NEWLINE:
            filename += self.look['text']
            self.__move()

        linux_path_spec = ""
        vax_path_spec = re.compile(
            r"(?:([0-9A-Za-z_]+):)?(\[[0-9A-Za-z_]+(?:\.[0-9A-Za-z_]+)*\])?([0-9A-Za-z_]+\.[0-9A-Za-z_]+)")
        vax_path_spec_search = vax_path_spec.search(filename)

        path_spec_groups = vax_path_spec_search.groups()
        device = path_spec_groups[0]
        directory = path_spec_groups[1]
        file_ = path_spec_groups[2]

        if device is not None:
            linux_path_spec += "%s/" % device

        if directory is not None:
            directory = directory.replace('[', '').replace(']', '').replace('.', '/')
            linux_path_spec += "%s/" % directory

        if file_ is not None:
            linux_path_spec += file_

        return linux_path_spec

    # The expression grammar in BNF
    #    <assignment> ::= <assignment> = <bool>   | <bool>
    #    <bool> ::= <bool> or <join> | <join>
    #    <join>  ::= <join> and <equality> | <equality>
    #    <equality> ::= <equality> == <rel> | <equality> != <rel> | <rel>
    #    <rel> ::= <expr> < <expr> | <expr> <= <expr> | <expr> >= <expr> |
    #              <expr> > <expr> | <expr>
    #    <expr> ::= <expr> + <term> | <expr> - <term> | <term>
    #    <term> ::= <term> * <unary> | <term> / <unary> | <unary>
    #    <unary> ::= not <unary> | - <unary> | <factor>
    #    <factor> ::= ( <assignment> ) | num | identifier

    # ******************** incomplete *********************
    # <num> ::= <sign> [0-9]+ | <sign> [0-9]+. | <sign> 0x[0-9]+ |
    #           <sign> 0b[0-9]+ | ' .* ' | true | false

    def __number(self):
        if self.look['type'] == TokenType.LIT_INT:
            expr = tree.Integer(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_INT)
        elif self.look['type'] == TokenType.LIT_FLOAT:
            expr = tree.Float(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_FLOAT)
        elif self.look['type'] == TokenType.LIT_HEX:
            expr = tree.Hexadecimal(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_HEX)
        elif self.look['type'] == TokenType.LIT_OCT:
            expr = tree.Octal(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_OCT)
        elif self.look['type'] == TokenType.LIT_BIN:
            expr = tree.Binary(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_BIN)
        elif self.look['type'] == TokenType.LIT_STRING:
            expr = tree.String(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_STRING)
        elif self.look['type'] == TokenType.KEY_TRUE:
            expr = tree.Integer(1, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.KEY_TRUE)
        elif self.look['type'] == TokenType.KEY_FALSE:
            expr = tree.Integer(0, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.KEY_FALSE)
        else:
            raise ParseError("Syntax error in basic expression on/before '%s' in input" % TokenName[self.look['type']],
                             cfg.source_stack.get_source_info())

        return expr

    def __function(self):
        func_name = self.look['attribute']
        self.__match(TokenType.TYP_FUNC)

        param_lst = [0]

        if self.look['type'] == TokenType.OPR_LBRACKET:
            param_lst = self.__function_parameters()
        else:
            raise ParseError("Function call '(' missing for function '%s'" % func_name,
                             cfg.source_stack.get_source_info())

        expr = tree.FunctionInvocation(func_name, param_lst, source_info=cfg.source_stack.get_source_info())

        return expr

    def __parameter_expression(self):
        """The continue statement implementation.
        
        This method skips the remainder of a while loop. 
        The BNF form is:
        
            <continue_statement> ::= continue
        """
        if not self.in_func:
            raise ParseError("Scoped identifier outside 'function' statement",
                             cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_PARAMS)

        if self.look['type'] == TokenType.OPR_LBRACKET:
            self.__match(TokenType.OPR_LBRACKET)
            param_num = self.__bool()
            self.__match(TokenType.OPR_RBRACKET)
            param_stmt = tree.ParameterNumber(param_num, source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.TYP_UNKNOWN:
            id_name = self.look['attribute']
            self.__match(TokenType.TYP_UNKNOWN)
            param_stmt = tree.LocalIdentifier(id_name, source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.TYP_VARIABLE:
            id_name = self.look['attribute']
            self.__match(TokenType.TYP_VARIABLE)
            param_stmt = tree.LocalIdentifier(id_name, source_info=cfg.source_stack.get_source_info())
        else:
            raise ParseError("Syntax error in scoped identifier, found '%s' (%s) following a '$'" % (
                self.look['text'], TokenName[self.look['type']]),
                             cfg.source_stack.get_source_info())

        return param_stmt

    def __system_function(self):
        func_name = self.look['attribute']
        self.__match(TokenType.TYP_SYSFUNC)

        param_lst = [0]

        if self.look['type'] == TokenType.OPR_LBRACKET:
            param_lst = self.__function_parameters()
        else:
            raise ParseError("Function call '(' missing for system function '%s'" % func_name,
                             cfg.source_stack.get_source_info())

        if func_name == 'frame_number':
            expr = tree.FunctionFrameNumber(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'channel_value':
            expr = tree.FunctionChannelValue(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'in_range':
            expr = tree.FunctionInRange(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'channel_enabled':
            expr = tree.FunctionChannelEnabled(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'get_wdm':
            expr = tree.FunctionGetWdm(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'set_wdm':
            expr = tree.FunctionSetWdm(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'str':
            expr = tree.FunctionStr(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'hex':
            expr = tree.FunctionHex(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'oct':
            expr = tree.FunctionOct(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'bin':
            expr = tree.FunctionBin(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'left_shift':
            expr = tree.FunctionLeftShift(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'right_shift':
            expr = tree.FunctionRightShift(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'bit_and':
            expr = tree.FunctionBitAnd(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'bit_or':
            expr = tree.FunctionBitOr(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'bit_xor':
            expr = tree.FunctionBitXor(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'pow':
            expr = tree.FunctionPow(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'time':
            expr = tree.FunctionTime(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'sin':
            expr = tree.FunctionSin(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'cos':
            expr = tree.FunctionCos(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'tan':
            expr = tree.FunctionTan(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'input_int':
            expr = tree.FunctionInputInt(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'input_float':
            expr = tree.FunctionInputFloat(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'input_str':
            expr = tree.FunctionInputStr(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'system':
            expr = tree.FunctionSystem(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'init_1553b':
            expr = tree.FunctionInit1553B(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'message_msgtype':
            expr = tree.FunctionMessageMsgType(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'message_rtaddr':
            expr = tree.FunctionMessageRTAddr(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'message_rtsubaddr':
            expr = tree.FunctionMessageRTSubAddr(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'message_wcntmcode':
            expr = tree.FunctionMessageWCntMCode(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'message_msggap':
            expr = tree.FunctionMessageMsgGap(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'message_info':
            expr = tree.FunctionMessageInfo(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'message_defined':
            expr = tree.FunctionMessageDefined(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'file_access':
            expr = tree.FunctionFileAccess(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'file_downloadpath':
            expr = tree.FunctionFileDownloadPath(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'file_uploadpath':
            expr = tree.FunctionFileUploadPath(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'get_uut':
            expr = tree.FunctionGetUUT(func_name, param_lst, source_info=cfg.source_stack.get_source_info())
        elif func_name == 'get_version':
            expr = tree.FunctionGetVersion(func_name, param_lst, source_info=cfg.source_stack.get_source_info())

        return expr

    def __function_parameters(self):
        param_lst = [0]

        self.__match(TokenType.OPR_LBRACKET)

        if self.look['type'] != TokenType.OPR_RBRACKET:
            param_lst.append(self.__assignment())

            while self.look['type'] == TokenType.OPR_COMMA:
                self.__match(TokenType.OPR_COMMA)
                param_lst.append(self.__assignment())

        self.__match(TokenType.OPR_RBRACKET)

        param_lst[0] = tree.Integer((len(param_lst) - 1), source_info=cfg.source_stack.get_source_info())

        return param_lst

    # <factor> ::= ( <assignment> ) | num | identifier

    def __factor(self):
        """The parenthesised expression implementation.
        
        This method handles parenthesised expressions in the language. 
        The BNF form is:
        
            <factor> ::= ( <assignment> ) | num | identifier
        """
        if self.look['type'] == TokenType.OPR_LBRACKET:
            self.__match(TokenType.OPR_LBRACKET)
            expr = self.__assignment()
            self.__match(TokenType.OPR_RBRACKET)
        elif self.look['type'] == TokenType.TYP_UNKNOWN:
            id_name = self.look['attribute']
            self.__match(TokenType.TYP_UNKNOWN)
            if self.look['type'] == TokenType.OPR_LBRACKET:
                param_lst = self.__function_parameters()
                expr = tree.FunctionInvocation(id_name, param_lst, source_info=cfg.source_stack.get_source_info())
            else:
                expr = tree.Identifier(id_name, source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.TYP_VARIABLE:
            id_name = self.look['attribute']
            expr = tree.Identifier(id_name, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.TYP_VARIABLE)
        elif self.look['type'] == TokenType.TYP_SYMBOL:
            raise ParseError("Symbols cannot be part of complex expressions",
                             cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.TYP_MACRO:
            message = "Invalid use of macro type, 'macname=%s' is the valid syntax" % (self.look['attribute'])
            raise ParseError(message,
                             cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.TYP_SYSFUNC:
            expr = self.__system_function()
        elif self.look['type'] == TokenType.TYP_FUNC:
            expr = self.__function()
        elif self.look['type'] == TokenType.OPR_PARAMS:
            expr = self.__parameter_expression()
        else:
            expr = self.__number()

        return expr

    # <unary>  ::= + <unary> | - <unary> | not <unary> | bnot <unary> | <factor>

    def __unary(self):
        """The logical not, unary plus, minus and bitwise not operator implementation.
        
        This method handles NOT and unary minus operators in the language. 
        The BNF form is:
        
            <unary>  ::= + <unary> | - <unary> | not <unary> | bnot <unary> | <factor>
        """
        if self.look['type'] == TokenType.OPR_PLUS:
            self.__match(TokenType.OPR_PLUS)
            expr = tree.Plus(self.__unary(), source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.OPR_MINUS:
            self.__match(TokenType.OPR_MINUS)
            expr = tree.Minus(self.__unary(), source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.KEY_NOTB:
            self.__match(TokenType.KEY_NOTB)
            expr = tree.BitNot(self.__unary(), source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.KEY_NOT:
            self.__match(TokenType.KEY_NOT)
            expr = tree.Not(self.__unary(), source_info=cfg.source_stack.get_source_info())
        else:
            expr = self.__factor()

        return expr

    # <term> ::= <term> * <unary> | <term> / <unary> | <unary>

    def __term(self):
        """The multiplication and division operator implementation.
        
        This method handles multiplication and division operators in the language. 
        The BNF form is:
        
            <term> ::= <term> * <unary> | <term> / <unary> | <unary>
        """
        expr = self.__unary()

        while (self.look['type'] == TokenType.OPR_MULTIPLY) or \
                (self.look['type'] == TokenType.OPR_DIVIDE) or \
                (self.look['type'] == TokenType.OPR_MODULO):
            if self.look['type'] == TokenType.OPR_MULTIPLY:
                self.__match(TokenType.OPR_MULTIPLY)
                expr = tree.Multiply(expr, self.__unary(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_DIVIDE:
                self.__match(TokenType.OPR_DIVIDE)
                expr = tree.Divide(expr, self.__unary(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_MODULO:
                self.__match(TokenType.OPR_MODULO)
                expr = tree.Modulo(expr, self.__unary(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <expr> ::= <expr> + <term> | <expr> - <term> | <term>

    def __expr(self):
        """The addition and subtraction operator implementation.
        
        This method handles addition and subtraction operators in the language. 
        The BNF form is:
        
            <expr> ::= <expr> + <term> | <expr> - <term> | <term>
        """
        expr = self.__term()

        while (self.look['type'] == TokenType.OPR_PLUS) or \
                (self.look['type'] == TokenType.OPR_MINUS):
            if self.look['type'] == TokenType.OPR_PLUS:
                self.__match(TokenType.OPR_PLUS)
                expr = tree.Add(expr, self.__term(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_MINUS:
                self.__match(TokenType.OPR_MINUS)
                expr = tree.Subtract(expr, self.__term(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <shifts> ::= <shifts> << <expr> | <shifts> >> <expr> | <expr>

    def __shifts(self):
        """The addition and subtraction operator implementation.
        
        This method handles addition and subtraction operators in the language. 
        The BNF form is:
        
            <shifts> ::= <shifts> << <expr> | <shifts> >> <expr> | <expr>
        """
        expr = self.__expr()

        while (self.look['type'] == TokenType.OPR_LSHIFT) or \
                (self.look['type'] == TokenType.OPR_RSHIFT):
            if self.look['type'] == TokenType.OPR_LSHIFT:
                self.__match(TokenType.OPR_LSHIFT)
                expr = tree.LeftShift(expr, self.__expr(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_RSHIFT:
                self.__match(TokenType.OPR_RSHIFT)
                expr = tree.RightShift(expr, self.__expr(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <rel> ::= <shifts> < <shifts> | <shifts> <= <shifts> | <shifts> >= <shifts> |
    #           <shifts> > <shifts> | <shifts>

    def __rel(self):
        """The relational operator implementation.
        
        This method handles relational operators in the language. 
        The BNF form is:
        
            <rel> ::= <shifts> < <shifts> | <shifts> <= <shifts> | <shifts> >= <shifts> |
                      <shifts> > <shifts> | <shifts>
        """
        expr = self.__shifts()

        while (self.look['type'] == TokenType.OPR_LESSER) or \
                (self.look['type'] == TokenType.OPR_LEQUALTO) or \
                (self.look['type'] == TokenType.OPR_GEQUALTO) or \
                (self.look['type'] == TokenType.OPR_GREATER):
            if self.look['type'] == TokenType.OPR_LESSER:
                self.__match(TokenType.OPR_LESSER)
                expr = tree.LessThan(expr, self.__shifts(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_LEQUALTO:
                self.__match(TokenType.OPR_LEQUALTO)
                expr = tree.LessThanEqualTo(expr, self.__shifts(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_GEQUALTO:
                self.__match(TokenType.OPR_GEQUALTO)
                expr = tree.GreaterThanEqualTo(expr, self.__shifts(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_GREATER:
                self.__match(TokenType.OPR_GREATER)
                expr = tree.GreaterThan(expr, self.__shifts(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <equality> ::= <equality> == <rel> | <equality> != <rel> | <rel>

    def __equality(self):
        """The equality operator implementation.
        
        This method handles equality operators in the language. 
        The BNF form is:
        
            <equality> ::= <equality> == <rel> | <equality> != <rel> | <rel>
        """
        expr = self.__rel()

        while (self.look['type'] == TokenType.OPR_EQUALTO) or \
                (self.look['type'] == TokenType.OPR_NOTEQUALTO):
            if self.look['type'] == TokenType.OPR_EQUALTO:
                self.__match(TokenType.OPR_EQUALTO)
                expr = tree.EqualTo(expr, self.__rel(), source_info=cfg.source_stack.get_source_info())
            if self.look['type'] == TokenType.OPR_NOTEQUALTO:
                self.__match(TokenType.OPR_NOTEQUALTO)
                expr = tree.NotEqualTo(expr, self.__rel(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <andbs> ::= <andbs> band <equality> | <equality>

    def __andbs(self):
        """The AND operator implementation.
        
        This method handles AND operators in the language. 
        The BNF form is:
        
            <andbs> ::= <andbs> band <equality> | <equality>
        """
        expr = self.__equality()

        while self.look['type'] == TokenType.KEY_ANDB:
            self.__match(TokenType.KEY_ANDB)
            expr = tree.BitAnd(expr, self.__equality(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <xorbs> ::= <xorbs> bxor <andbs> | <andbs>

    def __xorbs(self):
        """The OR operator implementation.
        
        This method handles OR operators in the language. 
        The BNF form is:
        
            <xorbs> ::= <xorbs> bxor <andbs> | <andbs>
        """
        expr = self.__andbs()

        while self.look['type'] == TokenType.KEY_XORB:
            self.__match(TokenType.KEY_XORB)
            expr = tree.BitXOr(expr, self.__andbs(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <orbs> ::= <orbs> bor <xorbs> | <xorbs>

    def __orbs(self):
        """The OR operator implementation.
        
        This method handles OR operators in the language. 
        The BNF form is:
        
            <orbs> ::= <orbs> bor <xorbs> | <xorbs>
        """
        expr = self.__xorbs()

        while self.look['type'] == TokenType.KEY_ORB:
            self.__match(TokenType.KEY_ORB)
            expr = tree.BitOr(expr, self.__xorbs(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <join> ::= <join> and <orbs> | <orbs>

    def __join(self):
        """The AND operator implementation.
        
        This method handles AND operators in the language. 
        The BNF form is:
        
            <join> ::= <join> and <orbs> | <orbs>
        """
        expr = self.__orbs()

        while self.look['type'] == TokenType.KEY_AND:
            self.__match(TokenType.KEY_AND)
            expr = tree.And(expr, self.__orbs(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <bool> ::= <bool> or <join> | <join>

    def __bool(self):
        """The OR operator implementation.
        
        This method handles OR operators in the language. 
        The BNF form is:
        
            <bool> ::= <bool> or <join> | <join>
        """
        expr = self.__join()

        while self.look['type'] == TokenType.KEY_OR:
            self.__match(TokenType.KEY_OR)
            expr = tree.Or(expr, self.__join(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <assignment> ::= <assignment> = <bool> | <bool>

    def __assignment(self):
        """The assignment statement implementation.
        
        This method handles assignment statements in the language. 
        The BNF form is:
        
            <assignment> ::= <assignment> = <bool> | <bool>
        """
        expr = self.__bool()

        while self.look['type'] == TokenType.OPR_ASSIGN:
            self.__match(TokenType.OPR_ASSIGN)
            expr = tree.Assign(expr, self.__assignment(), source_info=cfg.source_stack.get_source_info())

        return expr

    # <symbol_statement_list> ::= <symbol_statement> & 
    #                             <symbol_statement_list> | <symbol_statement>
    # <symbol_statement> :: = <symbol_access> not in <range_exp> <print_symbol> |
    #                         <symbol_access> in <range_exp> <print_symbol> |
    #                         <symbol_access> <equ_op> num <print_symbol> |
    #                         <symbol_access> <rel_op> num <print_symbol> |
    #                         <symbol_access> = num |
    #                         <symbol_access> <print_symbol>
    # <symbol_access> ::= symbol | symbol + num | symbol ( num ) | 
    #                     symbol ( num ) + num
    # <range_exp> ::= num ( num ) | (num, num)
    # <print_symbol> ::= ? | "?

    # <range_exp> ::= num ( num ) | (num, num)

    # <symbol_access>  ::= symbol | symbol + num | symbol ( num ) |
    #                      symbol ( num ) + num

    def __symbol_access(self):
        """The symbol access implementation.
        
        This method handles symbol access in the language. 
        The BNF form is:
        
            <symbol_access>  ::= symbol | symbol + num | symbol ( num ) |
                                 symbol ( num ) + num |
        """
        mask_flag = False
        user_mask = tree.Binary(0b1111, source_info=cfg.source_stack.get_source_info())
        user_offset = tree.Integer(0, source_info=cfg.source_stack.get_source_info())

        symbol_name = self.look['attribute']
        self.__match(TokenType.TYP_SYMBOL)

        if cfg.legacy_syntax:  # Old syntax
            if self.look['type'] == TokenType.OPR_PLUS:
                self.__match(TokenType.OPR_PLUS)
                user_offset = self.__get_hex()  # offset is in hex in old syntax

            if self.look['type'] == TokenType.OPR_LBRACKET:
                self.__match(TokenType.OPR_LBRACKET)
                user_mask = self.__get_bin()
                self.__match(TokenType.OPR_RBRACKET)
        else:  # New syntax
            if self.look['type'] == TokenType.OPR_LBRACKET:
                self.__match(TokenType.OPR_LBRACKET)
                user_mask = self.__get_bin()
                self.__match(TokenType.OPR_RBRACKET)

            if self.look['type'] == TokenType.OPR_PLUS:
                self.__match(TokenType.OPR_PLUS)
                # 26/11/2014: Using bool as offset in symbol causes problems with <>, <, etc. operators
                user_offset = tree.FinalValueExpression(self.__expr(), source_info=cfg.source_stack.get_source_info())

        current_symbol_type = cfg.symbol_table.get_entry(symbol_name).get_iotype()

        if (self.symbol_list_type is not None) and (self.symbol_list_type != current_symbol_type):
            raise ParseError("Cannot combine different types of symbols", cfg.source_stack.get_source_info())

        self.symbol_list_type = current_symbol_type

        if current_symbol_type == 'spil':
            expr = tree.SPILSymbolAccess(symbol_name, user_mask, user_offset,
                                         source_info=cfg.source_stack.get_source_info())
        elif current_symbol_type == 'ccdl':
            if cfg.symbol_table.get_entry(symbol_name).get_struct() == 'in':
                expr = tree.CCDLInSymbolAccess(symbol_name, user_mask, user_offset,
                                               source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'out':
                expr = tree.CCDLOutSymbolAccess(symbol_name, user_mask, user_offset,
                                                source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'task':
                expr = tree.CCDLTaskSymbolAccess(symbol_name, user_mask, user_offset,
                                                 source_info=cfg.source_stack.get_source_info())
            else:
                raise ParseError(
                    "Unknown STRUCT value '%s' for CCDL symbol" % cfg.symbol_table.get_entry(symbol_name).get_struct(),
                    cfg.source_stack.get_source_info())
        elif current_symbol_type == 'dpfs':
            expr = tree.DPFSSymbolAccess(symbol_name, user_mask, user_offset,
                                         source_info=cfg.source_stack.get_source_info())
        elif current_symbol_type == 'simproc':
            if cfg.symbol_table.get_entry(symbol_name).get_struct() == 'in':
                expr = tree.SIMPROCInSymbolAccess(symbol_name, user_mask, user_offset,
                                                  source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'out':
                expr = tree.SIMPROCOutSymbolAccess(symbol_name, user_mask, user_offset,
                                                   source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'task':
                expr = tree.SIMPROCTaskSymbolAccess(symbol_name, user_mask, user_offset,
                                                    source_info=cfg.source_stack.get_source_info())
            else:
                raise ParseError("Unknown STRUCT value '%s' for SIMPROC symbol" % cfg.symbol_table.get_entry(
                    symbol_name).get_struct(), cfg.source_stack.get_source_info())
        elif current_symbol_type == 'rs422':
            if cfg.symbol_table.get_entry(symbol_name).get_struct() == 'in':
                expr = tree.RS422InSymbolAccess(symbol_name, user_mask, user_offset,
                                                source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'out':
                expr = tree.RS422OutSymbolAccess(symbol_name, user_mask, user_offset,
                                                 source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'task':
                expr = tree.RS422TaskSymbolAccess(symbol_name, user_mask, user_offset,
                                                  source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'error':
                expr = tree.RS422ErrorSymbolAccess(symbol_name, user_mask, user_offset,
                                                   source_info=cfg.source_stack.get_source_info())
            else:
                raise ParseError(
                    "Unknown STRUCT value '%s' for RS422 symbol" % cfg.symbol_table.get_entry(symbol_name).get_struct(),
                    cfg.source_stack.get_source_info())
        elif current_symbol_type == '1553b':
            if cfg.symbol_table.get_entry(symbol_name).get_struct() == 'in':
                expr = tree.MIL1553BInSymbolAccess(symbol_name, user_mask, user_offset,
                                                   source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'out':
                expr = tree.MIL1553BOutSymbolAccess(symbol_name, user_mask, user_offset,
                                                    source_info=cfg.source_stack.get_source_info())
            elif cfg.symbol_table.get_entry(symbol_name).get_struct() == 'task':
                expr = tree.MIL1553BTaskSymbolAccess(symbol_name, user_mask, user_offset,
                                                     source_info=cfg.source_stack.get_source_info())
            else:
                raise ParseError(
                    "Unknown STRUCT value '%s' for 1553B symbol" % cfg.symbol_table.get_entry(symbol_name).get_struct(),
                    cfg.source_stack.get_source_info())
        else:
            raise ParseError("Unknown IOTYPE value '%s' for symbol" % current_symbol_type,
                             cfg.source_stack.get_source_info())

        return expr

    def __range_expression(self, expr=None, bypass=False):
        """The range expression implementation.
        
        This method handles range expressions in the language. 
        The BNF form is:
        
            <range_exp> ::= num ( num ) | (num, num)
        """
        if self.look['type'] == TokenType.OPR_LBRACKET:
            self.__match(TokenType.OPR_LBRACKET)

            if bypass:
                lower_expr = self.__get_hex()
            else:
                if cfg.legacy_syntax:  # Old syntax
                    try:
                        lower_expr = self.__get_hex()
                    except:
                        lower_expr = tree.FinalValueExpression(self.__expr(),
                                                               source_info=cfg.source_stack.get_source_info())
                else:  # New syntax
                    lower_expr = tree.FinalValueExpression(self.__bool(),
                                                           source_info=cfg.source_stack.get_source_info())

            self.__match(TokenType.OPR_COMMA)

            if bypass:
                upper_expr = self.__get_hex()
            else:
                if cfg.legacy_syntax:  # Old syntax
                    try:
                        upper_expr = self.__get_hex()
                    except:
                        upper_expr = tree.FinalValueExpression(self.__expr(),
                                                               source_info=cfg.source_stack.get_source_info())
                else:  # New syntax
                    upper_expr = tree.FinalValueExpression(self.__bool(),
                                                           source_info=cfg.source_stack.get_source_info())

            self.__match(TokenType.OPR_RBRACKET)

            if expr:
                return tree.Range(lower_expr, upper_expr, source_info=cfg.source_stack.get_source_info())
        else:
            if bypass:
                value_expr = self.__get_hex()
            else:
                if cfg.legacy_syntax:  # Old syntax
                    try:
                        value_expr = self.__get_hex()
                    except:
                        value_expr = tree.FinalValueExpression(self.__expr(),
                                                               source_info=cfg.source_stack.get_source_info())
                else:  # New syntax
                    value_expr = tree.FinalValueExpression(self.__bool(),
                                                           source_info=cfg.source_stack.get_source_info())

            self.__match(TokenType.OPR_LBRACKET)

            if bypass:
                tolerance_expr = self.__get_hex()
            else:
                if cfg.legacy_syntax:  # Old syntax
                    try:
                        tolerance_expr = self.__get_hex()
                    except:
                        tolerance_expr = tree.FinalValueExpression(self.__expr(),
                                                                   source_info=cfg.source_stack.get_source_info())
                else:  # New syntax
                    tolerance_expr = tree.FinalValueExpression(self.__bool(),
                                                               source_info=cfg.source_stack.get_source_info())

            self.__match(TokenType.OPR_RBRACKET)
            if expr:
                return tree.Tolerance(value_expr, tolerance_expr, source_info=cfg.source_stack.get_source_info())

    def __speculate_notequal_range(self):
        success = True
        self.scan.mark()
        try:
            self.__parse_notequal_range()
        except ParseError:
            success = False
        self.scan.release()
        self.__move()

        return success

    def __speculate_notequal_range_bypass(self):
        success = True
        self.scan.mark()
        try:
            self.__parse_notequal_range_bypass()
        except ParseError:
            success = False
        self.scan.release()
        self.__move()

        return success

    def __speculate_equal_range(self, bypass=False):
        success = True
        self.scan.mark()
        try:
            self.__parse_equal_range(bypass=bypass)
        except ParseError:
            success = False
        self.scan.release()
        self.__move()

        return success

    def __speculate_equal(self, bypass=False):
        success = True
        self.scan.mark()
        try:
            self.__parse_equal(bypass=bypass)
        except ParseError:
            success = False
        self.scan.release()
        self.__move()

        return success

    def __speculate_assignment(self, bypass=False):
        success = True
        self.scan.mark()
        try:
            self.__parse_symbol_assignment(bypass=bypass)
        except ParseError:
            success = False
            #raise
        self.scan.release()
        self.__move()

        return success

    def __speculate_ask(self):
        success = True
        self.scan.mark()
        try:
            self.__parse_symbol_ask()
        except ParseError:
            success = False
        self.scan.release()
        self.__move()

        return success

    def __parse_notequal_range(self, expr=None):
        self.__match(TokenType.OPR_NOTEQUALTO)
        range_expr = self.__range_expression(expr)

        self.__match(TokenType.OPR_QUESTION)

        if expr:
            return range_expr

    def __parse_notequal_range_bypass(self, expr=None):
        self.__match(TokenType.OPR_BNOTEQUALTO)
        range_expr = self.__range_expression(expr, bypass=True)

        self.__match(TokenType.OPR_QUESTION)

        if expr:
            return range_expr

    def __parse_equal_range(self, expr=None, bypass=False):
        range_expr = self.__range_expression(expr, bypass=bypass)

        self.__match(TokenType.OPR_QUESTION)

        if expr:
            return range_expr

    def __parse_equal(self, expr=None, bypass=False):
        if bypass:
            value = self.__get_hex()
        else:
            if cfg.legacy_syntax:  # Old syntax
                try:
                    value = self.__get_hex()
                except:
                    value = tree.FinalValueExpression(self.__expr(), source_info=cfg.source_stack.get_source_info())
            else:  # New syntax
                value = tree.FinalValueExpression(self.__bool(), source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_QUESTION)

        if expr:
            return value

    def __parse_symbol_assignment(self, expr=None, bypass=False):
        if bypass:
            value = self.__get_hex()
        else:
            if cfg.legacy_syntax:  # Old syntax
                try:
                    value = self.__get_hex()
                except:
                    value = tree.FinalValueExpression(self.__expr(), source_info=cfg.source_stack.get_source_info())
            else:  # New syntax
                value = tree.FinalValueExpression(self.__bool(), source_info=cfg.source_stack.get_source_info())

        if expr:
            return value

    def __parse_symbol_ask(self, expr=None):
        self.__match(TokenType.OPR_QUESTION)

    def __speculate_parse(self, expr):
        if self.look['type'] == TokenType.OPR_BEQUAL:
            self.__match(TokenType.OPR_BEQUAL)

            if self.__speculate_ask():
                self.__parse_symbol_ask()
                expr = tree.PrintBypassSymbol(expr, source_info=cfg.source_stack.get_source_info())
            elif self.__speculate_equal_range(bypass=True):
                expr = tree.BypassIn(expr, self.__parse_equal_range(expr, bypass=True),
                                     source_info=cfg.source_stack.get_source_info())
            elif self.__speculate_equal(bypass=True):
                expr = tree.ChannelBypassEqualTo(expr, self.__parse_equal(expr, bypass=True),
                                                 source_info=cfg.source_stack.get_source_info())
            elif self.__speculate_assignment(bypass=True):
                bool_expr = self.__parse_symbol_assignment(expr, bypass=True)
                expr = tree.ChannelBypassAssign(expr, bool_expr, source_info=cfg.source_stack.get_source_info())
            else:
                raise ParseError("Expected '?', range expression, or expression after '=\"' in symbol statement",
                                 cfg.source_stack.get_source_info())
        else:
            self.__match(TokenType.OPR_EQUAL)

            if self.__speculate_ask():
                self.__parse_symbol_ask()
                expr = tree.PrintSymbol(expr, source_info=cfg.source_stack.get_source_info())
            elif self.__speculate_equal_range(bypass=False):
                expr = tree.In(expr, self.__parse_equal_range(expr, bypass=False),
                               source_info=cfg.source_stack.get_source_info())
            elif self.__speculate_equal(bypass=False):
                expr = tree.ChannelEqualTo(expr, self.__parse_equal(expr, bypass=False),
                                           source_info=cfg.source_stack.get_source_info())
            elif self.__speculate_assignment(bypass=False):
                bool_expr = self.__parse_symbol_assignment(expr, bypass=False)
                expr = tree.ChannelAssign(expr, bool_expr, source_info=cfg.source_stack.get_source_info())
            else:
                raise ParseError("Expected '?', range expression, or expression after '=' in symbol statement",
                                 cfg.source_stack.get_source_info())

        return expr

    def __symbol_statement(self):
        expr = self.__symbol_access()

        if (self.look['type'] == TokenType.OPR_BEQUAL) or \
                (self.look['type'] == TokenType.OPR_EQUAL):
            expr = self.__speculate_parse(expr)
        elif self.__speculate_notequal_range_bypass():
            expr = tree.BypassNotIn(expr, self.__parse_notequal_range_bypass(expr),
                                    source_info=cfg.source_stack.get_source_info())
        elif self.__speculate_notequal_range():
            expr = tree.NotIn(expr, self.__parse_notequal_range(expr), source_info=cfg.source_stack.get_source_info())
        # TODO: FIX ABOVE THINGS FOR BYPASS STATEMENTS
        elif self.look['type'] == TokenType.OPR_BNOTEQUALTO:
            self.__match(TokenType.OPR_BNOTEQUALTO)
            expr = tree.ChannelBypassNotEqualTo(expr, self.__get_hex(), source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_NOTEQUALTO:
            self.__match(TokenType.OPR_NOTEQUALTO)
            fv_expr = tree.FinalValueExpression(self.__bool(), source_info=cfg.source_stack.get_source_info())
            expr = tree.ChannelNotEqualTo(expr, fv_expr, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_BLESSER:
            self.__match(TokenType.OPR_BLESSER)
            expr = tree.ChannelBypassLessThan(expr, self.__get_hex(), source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_LESSER:
            self.__match(TokenType.OPR_LESSER)
            fv_expr = tree.FinalValueExpression(self.__bool(), source_info=cfg.source_stack.get_source_info())
            expr = tree.ChannelLessThan(expr, fv_expr, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_BLEQUALTO:
            self.__match(TokenType.OPR_BLEQUALTO)
            expr = tree.ChannelBypassLessThanEqualTo(expr, self.__get_hex(),
                                                     source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_LEQUALTO:
            self.__match(TokenType.OPR_LEQUALTO)
            fv_expr = tree.FinalValueExpression(self.__bool(), source_info=cfg.source_stack.get_source_info())
            expr = tree.ChannelLessThanEqualTo(expr, fv_expr, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_BGREATER:
            self.__match(TokenType.OPR_BGREATER)
            expr = tree.ChannelBypassGreaterThan(expr, self.__get_hex(), source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_GREATER:
            self.__match(TokenType.OPR_GREATER)
            fv_expr = tree.FinalValueExpression(self.__bool(), source_info=cfg.source_stack.get_source_info())
            expr = tree.ChannelGreaterThan(expr, fv_expr, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_BGEQUALTO:
            self.__match(TokenType.OPR_BGEQUALTO)
            expr = tree.ChannelBypassGreaterThanEqualTo(expr, self.__get_hex(),
                                                        source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        elif self.look['type'] == TokenType.OPR_GEQUALTO:
            self.__match(TokenType.OPR_GEQUALTO)
            fv_expr = tree.FinalValueExpression(self.__bool(), source_info=cfg.source_stack.get_source_info())
            expr = tree.ChannelGreaterThanEqualTo(expr, fv_expr, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_QUESTION)
        else:
            raise ParseError(
                "Expected '=', '<>', '<', '<=', '>', '>=', or one of their bypass varieties in symbol statement",
                cfg.source_stack.get_source_info())

        return expr

    # <symbol_statement_list>  ::= <symbol_statement> &
    #                              <symbol_statement_list> | <symbol_statement>

    def __symbol_statement_list(self):
        """The symbol statement list implementation.
        
        This method handles symbol statement lists in the language. 
        The BNF form is:
        
            <symbol_statement_list>  ::= <symbol_statement> & 
                                         <symbol_statement_list> | 
                                         <symbol_statement>
        """
        self.symbol_list_type = None
        stmt_list = [self.__symbol_statement()]

        while self.look['type'] == TokenType.OPR_AMPERSAND:
            self.__match(TokenType.OPR_AMPERSAND)
            while self.look['type'] == TokenType.OPR_NEWLINE:
                self.__match(TokenType.OPR_NEWLINE)
            # 10/11/2014: ignore comments in symbols separated by &
            while self.look['type'] == TokenType.SPL_COMMENT:
                self.__match(TokenType.SPL_COMMENT)

            stmt_list.append(self.__symbol_statement())

        if self.symbol_list_type == 'spil':
            expr = tree.SPILSymbolStatementList(stmt_list, source_info=cfg.source_stack.get_source_info())
        elif self.symbol_list_type == 'rs422':
            expr = tree.RS422SymbolStatementList(stmt_list, source_info=cfg.source_stack.get_source_info())
        else:
            expr = tree.SymbolStatementList(stmt_list, source_info=cfg.source_stack.get_source_info())

        return expr

    # <basic_expression> ::= <symbol_statement> | <assignment>

    def __basic_expression(self):
        """The basic expression implementation.
        
        This method handles basic expressions in the language. 
        The BNF form is:
        
            <basic_expression> ::= <symbol_statement> | <assignment>
        """
        if self.look['type'] == TokenType.TYP_SYMBOL:
            expr = self.__symbol_statement_list()
        else:
            expr = self.__assignment()

        expr_root = tree.Expression(expr, source_info=cfg.source_stack.get_source_info())

        return expr_root

    # <operative_statement> ::= <basic_expression>

    def __operative_statement(self):
        """The operative statement implementation.
        
        This method handles operative statements in the language. 
        The BNF form is:
        
            <operative_statement> ::= <basic_expression>
        """
        expr_root = self.__basic_expression()

        try:
            self.__match(TokenType.OPR_NEWLINE)
        except ParseError:
            # good solution, initial
            #raise ParseError("Syntax error in input, possible causes include use of a non-symbol type in a symbolic context, use of '=' instead of ':=' in an assignment, or invocation of a non-function", source_info=cfg.source_stack.get_curr_source_info())

            # bad solution 1
            strange_requirement = tree.DelayedParseError("Syntax error in input (undefined symbol?)",
                                                         source_info=cfg.source_stack.get_source_info())

            self.__skip_till_EOL()

            return strange_requirement

        return expr_root

    def __locate_statement(self):
        """The locate statement implementation.
                                                                                                                             
        This method handles locate statements in the language.
        This can be used to find out from where names (variables, symbols, macros and functions) 
        that are currently loaded in AITESS came into existence.
        The BNF form is:
                                                                                                                             
            <locate_statement> ::= locate <name> (, <name>)*
        """
        self.__match(TokenType.KEY_LOCATE)

        loc_list = [self.look['text'].lower()]

        self.__move()

        while self.look['type'] == TokenType.OPR_COMMA:
            self.__match(TokenType.OPR_COMMA)
            loc_list.append(self.look['text'].lower())
            self.__move()

        loc_stmt = tree.Locate(loc_list, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return loc_stmt

    def __tpgph_statement(self):
        """The test paragraph statement (tpgph) implementation.
                                                                                                                             
        This method handles test paragraph statements (tpgph) in the language.
        This statement has no effect. 
        The BNF form is:
                                                                                                                             
            <tpgph_statement> ::= tpgph = .*
        """
        self.__match(TokenType.KEY_TPGPH)
        self.__match(TokenType.OPR_EQUAL)

        while self.look['type'] != TokenType.OPR_NEWLINE:
            self.__move()

        tpgph_stmt = tree.Empty(source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return tpgph_stmt

    def __step_statement(self):
        """The step statement implementation.
                                                                                                                             
        This method handles step statements in the language.
        This statement has no effect.
        The BNF form is:
                                                                                                                             
            <step_statement> ::= step = .*
        """
        self.__match(TokenType.KEY_STEP)
        self.__match(TokenType.OPR_EQUAL)

        while self.look['type'] != TokenType.OPR_NEWLINE:
            self.__move()

        step_stmt = tree.Empty(source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return step_stmt

    def __auto_statement(self):
        """The auto statement implementation.
                                                                                                                             
        This method handles auto statements that are used in the language.
        This statement executes batch files. 
        The BNF form is:
                                                                                                                             
            <auto_statement> ::= auto .*
        """
        self.__match(TokenType.KEY_AUTO)

        raise ParseError("Keyword 'auto' not expected in files invoked with '@'",
                         cfg.source_stack.get_source_info())

    def __man_statement(self):
        """The man statement implementation.
                                                                                                                             
        This method handles man statements that are used in the language.
        This statement toggles AITESS manual mode. Test plans and batch files cannot
        be executed in manual mode.
        The BNF form is:
                                                                                                                             
            <man_statement> ::= man
        """
        self.__match(TokenType.KEY_MAN)

        raise ParseError("Keyword 'man' not expected in files invoked with '@'",
                         cfg.source_stack.get_source_info())

    def __ltm_syntax_statement(self):
        """The ***** statement implementation.
                                                                                                                             
        This method handles auto statements that are incorrectly used in the language.
        This statement executes batch files. 
        The BNF form is:
                                                                                                                             
            <auto_statement> ::= auto .*
        """
        self.__match(TokenType.KEY_LTM_SYNTAX)

        if self.look['type'] == TokenType.KEY_ON:
            self.__match(TokenType.KEY_ON)
            if cfg.legacy_syntax:
                message = "ltm_syntax: Parser alread using legacy syntax"
            else:
                cfg.legacy_syntax = True
                message = "ltm_syntax: Parser switched to legacy syntax"
        elif self.look['type'] == TokenType.KEY_OFF:
            self.__match(TokenType.KEY_OFF)
            if cfg.legacy_syntax:
                cfg.legacy_syntax = False
                message = "ltm_syntax: Parser switched to new syntax"
            else:
                message = "ltm_syntax: Parser already using new syntax"
        elif self.look['type'] == TokenType.OPR_NEWLINE:
            if cfg.legacy_syntax:
                message = "ltm_syntax: Parser using legacy syntax"
            else:
                message = "ltm_syntax: Parser using new syntax"
        else:
            raise ParseError("Parameter 'on' or 'off' expected for statement 'ltm_syntax'",
                             cfg.source_stack.get_source_info())

        lym_syn_stmt = tree.LtmSytax(message, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return lym_syn_stmt

    # <frwait_statement> ::= frwait number-of-frames

    def __frwait_statement(self):
        """The frwait statement implementation.                                                                                                                                                           
        This method handles frwait statements in the language.
        The BNF form is:                                                                                                                                                             
            <frwait_statement> ::= frwait <integer>
        """
        self.__match(TokenType.KEY_FRWAIT)

        self.__match(TokenType.OPR_EQUAL)

        if self.look['type'] == TokenType.LIT_INT:
            expr = tree.Integer(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_INT)
        elif self.look['type'] == TokenType.LIT_FLOAT:
            expr = tree.Integer(int(self.look['attribute']), source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_FLOAT)
        else:
            raise ParseError("Parameter time expected as 'integer' for statement 'frwait'",
                             cfg.source_stack.get_source_info())

        frwait_stmt = tree.FrWait(expr, source_info=cfg.source_stack.get_source_info())
        self.__match(TokenType.OPR_NEWLINE)

        return frwait_stmt

    # <wait_statement> ::= wait seconds

    def __wait_statement(self):
        """The wait statement implementation.
        
        This method handles wait statements in the language. 
        The BNF form is:
        
            <wait_statement> ::= wait <float> | wait <integer>
        """
        self.__match(TokenType.KEY_WAIT)
        self.__match(TokenType.OPR_EQUAL)

        if self.look['type'] == TokenType.LIT_INT:
            expr = tree.Integer(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_INT)
        elif self.look['type'] == TokenType.LIT_FLOAT:
            expr = tree.Float(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_FLOAT)
        else:
            raise ParseError("Parameter time expected as 'integer' or 'float' for statement 'wait'",
                             cfg.source_stack.get_source_info())

        wait_stmt = tree.Wait(expr, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return wait_stmt

    # <display_statement> ::= display on | display off

    def __display_statement(self):
        """The display statement implementation.
        
        This method handles display statements in the language. 
        The BNF form is:
        
            <display_statement> ::= display on | display off
        """
        self.__match(TokenType.KEY_DISPLAY)

        if self.look['type'] == TokenType.KEY_ON:
            expr = tree.Integer(1, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.KEY_ON)
        elif self.look['type'] == TokenType.KEY_OFF:
            expr = tree.Integer(0, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.KEY_OFF)
        else:
            raise ParseError("Parameter 'on' or 'off' expected for statement 'display'",
                             cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        display_stmt = tree.Display(expr, source_info=cfg.source_stack.get_source_info())

        return display_stmt

    # <logging_statement> ::= logging on | logging off

    def __logging_statement(self):
        """The logging statement implementation.
        
        This method handles logging statements in the language. 
        The BNF form is:
        
            <logging_statement> ::= logging on | logging off
        """
        self.__match(TokenType.KEY_LOGGING)

        if self.look['type'] == TokenType.KEY_ON:
            expr = tree.Integer(1, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.KEY_ON)
        elif self.look['type'] == TokenType.KEY_OFF:
            expr = tree.Integer(0, source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.KEY_OFF)
        else:
            raise ParseError("Parameter 'on' or 'off' expected for statement 'logging'",
                             cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        logging_stmt = tree.Logging(expr, source_info=cfg.source_stack.get_source_info())

        return logging_stmt

    def __sym_decl_statement(self):
        cdef dict attributes = {}
        msgid_found = False

        self.__match(TokenType.KEY_SYM)

        self.__match(TokenType.OPR_EQUAL)

        # Obtain the next token's attribute which should be symbol name 
        # i.e. an identifier.
        symbol_name = self.look['attribute']

        symtab_entry = Symbol(symbol_name)

        if self.look['type'] == TokenType.TYP_SYMBOL:
            message = "Identifier '%s' redeclared as symbol" % symbol_name
            raise ParseError(message, cfg.source_stack.get_source_info())

        # Consume the identifier.
        self.__match(TokenType.TYP_UNKNOWN)

        try:
            while (self.look['type'] != TokenType.KEY_ENDSYM) and \
                    (self.look['type'] != TokenType.KEY_SYM) and \
                    (self.look['type'] != TokenType.SPL_EOF):
                if self.look['type'] == TokenType.OPR_NEWLINE:
                    self.__match(TokenType.OPR_NEWLINE)
                # skip comments in symbol declarations, assumption: they are of no use
                elif self.look['type'] == TokenType.SPL_COMMENT:
                    self.__match(TokenType.SPL_COMMENT)
                else:
                    if self.look['type'] == TokenType.TYP_UNKNOWN:
                        name = self.look['attribute']
                        self.__match(TokenType.TYP_UNKNOWN)
                        self.__match(TokenType.OPR_EQUAL)

                        if name.lower() == 'iotype':
                            symtab_entry.set_iotype(self.look['text'].lower())
                            if symtab_entry.get_iotype() == 'rs422':
                                symtab_entry.set_struct('in')
                            self.__move()
                        elif name.lower() == 'unit':
                            symtab_entry.set_unit(self.look['text'])
                            self.__move()
                        elif name.lower() == 'chan':
                            symtab_entry.set_chan(int(('0b' + str(self.look['text'])), 2))
                            self.__move()
                        elif (name.lower() == 'type') or (name.lower() == 'dtype'):
                            symtab_entry.set_dtype(self.look['text'].lower())
                            self.__move()
                        elif name.lower() == 'max':
                            if self.look['type'] == TokenType.OPR_LSQBRACKET:
                                self.__match(TokenType.OPR_LSQBRACKET)
                                expression = ''
                                while self.look['type'] != TokenType.OPR_RSQBRACKET:
                                    expression += self.look['text']
                                    self.__move()
                                self.__match(TokenType.OPR_RSQBRACKET)
                                symtab_entry.set_max(eval(expression))
                            else:
                                sign = 1
                                if self.look['type'] == TokenType.OPR_MINUS:
                                    self.__match(TokenType.OPR_MINUS)
                                    sign = -1
                                # Mod4: begin
                                elif self.look['type'] == TokenType.OPR_PLUS:
                                    self.__match(TokenType.OPR_PLUS)
                                    sign = 1
                                # Mod4: end
                                symtab_entry.set_max(sign * self.look['attribute'])
                                try:
                                    self.__match(TokenType.LIT_FLOAT)
                                except ParseError:
                                    self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'min':
                            if self.look['type'] == TokenType.OPR_LSQBRACKET:
                                self.__match(TokenType.OPR_LSQBRACKET)
                                expression = ''
                                while self.look['type'] != TokenType.OPR_RSQBRACKET:
                                    expression += self.look['text']
                                    self.__move()
                                self.__match(TokenType.OPR_RSQBRACKET)
                                symtab_entry.set_min(eval(expression))
                            else:
                                sign = 1
                                if self.look['type'] == TokenType.OPR_MINUS:
                                    self.__match(TokenType.OPR_MINUS)
                                    sign = -1
                                # Mod4: begin
                                elif self.look['type'] == TokenType.OPR_PLUS:
                                    self.__match(TokenType.OPR_PLUS)
                                    sign = 1
                                # Mod4: end
                                symtab_entry.set_min(sign * self.look['attribute'])
                                try:
                                    self.__match(TokenType.LIT_FLOAT)
                                except ParseError:
                                    self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'subsystem':
                            symtab_entry.set_subsystem(self.look['text'].lower())
                            self.__move()
                        elif name.lower() == 'struct':
                            symtab_entry.set_struct(self.look['text'].lower())
                            self.__move()
                        elif name.lower() == 'rdbk':
                            if int(('0b' + str(self.look['text'])), 2) == 0b1:
                                symtab_entry.set_struct('out')
                            else:
                                symtab_entry.set_struct('in')
                            self.__move()
                        elif name.lower() == 'stype':
                            symtab_entry.set_stype(self.look['text'].lower())
                            self.__move()
                        elif name.lower() == 'addr':
                            address = int(('0x' + str(self.look['text'])), 16)
                            symtab_entry.set_addr(address)
                            self.__move()
                        elif name.lower() == 'ofst1':
                            symtab_entry.set_ofst1(self.look['attribute'])
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'ofst2':
                            symtab_entry.set_ofst2(self.look['attribute'])
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'ofst3':
                            symtab_entry.set_ofst3(self.look['attribute'])
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'ofst4':
                            symtab_entry.set_ofst4(self.look['attribute'])
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'bias':
                            if self.look['type'] == TokenType.OPR_LSQBRACKET:
                                self.__match(TokenType.OPR_LSQBRACKET)
                                expression = ''
                                while self.look['type'] != TokenType.OPR_RSQBRACKET:
                                    expression += self.look['text']
                                    self.__move()
                                self.__match(TokenType.OPR_RSQBRACKET)
                                symtab_entry.set_bias_text(expression)
                                symtab_entry.set_bias(eval(expression))
                            else:
                                sign = 1
                                if self.look['type'] == TokenType.OPR_MINUS:
                                    self.__match(TokenType.OPR_MINUS)
                                    sign = -1
                                # Mod4: begin
                                elif self.look['type'] == TokenType.OPR_PLUS:
                                    self.__match(TokenType.OPR_PLUS)
                                    sign = 1
                                # Mod4: end
                                symtab_entry.set_bias(sign * self.look['attribute'])
                                try:
                                    self.__match(TokenType.LIT_FLOAT)
                                except ParseError:
                                    self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'slpe':
                            if self.look['type'] == TokenType.OPR_LSQBRACKET:
                                self.__match(TokenType.OPR_LSQBRACKET)
                                expression = ''
                                while self.look['type'] != TokenType.OPR_RSQBRACKET:
                                    expression += self.look['text']
                                    self.__move()
                                self.__match(TokenType.OPR_RSQBRACKET)
                                symtab_entry.set_slpe_text(expression)
                                symtab_entry.set_slpe(eval(expression))
                            else:
                                sign = 1
                                if self.look['type'] == TokenType.OPR_MINUS:
                                    self.__match(TokenType.OPR_MINUS)
                                    sign = -1
                                # Mod4: begin
                                elif self.look['type'] == TokenType.OPR_PLUS:
                                    self.__match(TokenType.OPR_PLUS)
                                    sign = 1
                                # Mod4: end
                                symtab_entry.set_slpe(sign * self.look['attribute'])
                                try:
                                    self.__match(TokenType.LIT_FLOAT)
                                except ParseError:
                                    self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'read':
                            symtab_entry.set_read(int(('0b' + str(self.look['text'])), 2))
                            self.__move()
                        elif name.lower() == 'wrte':
                            symtab_entry.set_wrte(int(('0b' + str(self.look['text'])), 2))
                            self.__move()
                        elif name.lower() == 'dest':
                            symtab_entry.set_dest(self.look['text'].lower())
                            self.__move()
                        elif name.lower() == 'mask':
                            symtab_entry.set_mask(int(('0x' + str(self.look['text'])), 16))
                            self.__move()
                        elif name.lower() == 'tolplus':
                            symtab_entry.set_tolplus(int(('0b' + str(self.look['text'])), 2))
                            self.__move()
                        elif name.lower() == 'tolminus':
                            symtab_entry.set_tolminus(int(('0b' + str(self.look['text'])), 2))
                            self.__move()
                        elif name.lower() == 'id':
                            symtab_entry.set_id_(self.look['attribute'])
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'msgid':
                            msgid_found = True
                            symtab_entry.set_id_(self.look['attribute'] + 1)
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'ofst':
                            symtab_entry.set_ofstx(self.look['attribute'])
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'mask1':
                            symtab_entry.set_mask1(int(('0x' + str(self.look['attribute'])), 16))
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'mask2':
                            symtab_entry.set_mask2(int(('0x' + str(self.look['attribute'])), 16))
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'mask3':
                            symtab_entry.set_mask3(int(('0x' + str(self.look['attribute'])), 16))
                            self.__match(TokenType.LIT_INT)
                        elif name.lower() == 'mask4':
                            symtab_entry.set_mask4(int(('0x' + str(self.look['attribute'])), 16))
                            self.__match(TokenType.LIT_INT)
                        else:
                            raise ParseError("Unknown symbol attribute '%s'" %
                                             name, cfg.source_stack.get_source_info())
                    else:
                        raise ParseError("Error in symbol declaration, token "
                                         "'%s' used as attribute" %
                                         TokenName[self.look['type']],
                                         cfg.source_stack.get_source_info())
        except (TypeError, ValueError):
            raise ParseError("General syntax error in symbol declaration statement", cfg.source_stack.get_source_info())

        try:
            ofsts_map = {5: 2, 6: 3, 7: 4, 8: 5, 12: 0, 9: 0, 10: 1}
            if msgid_found:
                symtab_entry.set_ofst1(ofsts_map[symtab_entry.get_ofst1()])
                symtab_entry.set_ofst2(
                    ofsts_map[symtab_entry.get_ofst2()] + 1 if symtab_entry.get_ofst2() == 12 else ofsts_map[
                        symtab_entry.get_ofst2()])
                symtab_entry.set_ofst3(ofsts_map[symtab_entry.get_ofst3()])
                symtab_entry.set_ofst4(
                    ofsts_map[symtab_entry.get_ofst4()] + 1 if symtab_entry.get_ofst4() == 12 else ofsts_map[
                        symtab_entry.get_ofst4()])
        except AttributeError:
            raise
        except KeyError:
            raise ParseError("Cannot map one of the offset values to new values symbol '%s'" %
                             symbol_name, cfg.source_stack.get_source_info())

        # Mod5: begin
        # Logic to unify handling of data type codes dis, dis_8, dis_16, dis_32, d8, d16, and d32
        # Mod5: end

        cfg.symbol_table.put_entry(symbol_name, symtab_entry)

        if self.look['type'] == TokenType.KEY_ENDSYM:
            self.__match(TokenType.KEY_ENDSYM)
            self.__match(TokenType.OPR_NEWLINE)

        return tree.Empty(source_info=cfg.source_stack.get_source_info())

    # <if_statement> ::= if <basic_expression> then <statement> fi 
    #                    | if <basic_expression> then <statement> else <statement> fi 
    # ****************************** FOR FUTURE ******************************
    #                    | if <basic_expression> then <statement> 
    #                        elif <basic_expression> then <statement> fi

    def __if_statement(self):
        """The if statement implementation.
        
        This method handles if statements in the language. 
        The BNF form is:
        
            <if_statement> ::= if <basic_expression> then <statement> fi |
                               if <basic_expression> then <statement> else <statement> fi |
                               if <basic_expression> then <statement> elif <basic_expression> then <statement>
                               else <statement> fi
        """
        gated_statement_list = []
        stmt_list = []

        self.__match(TokenType.KEY_IF)

        try:
            expr = self.__basic_expression()
        except ParseError:
            raise ParseError("Syntax error in conditional expression for "
                             "'if' statement", cfg.source_stack.get_source_info())

        self.__match(TokenType.KEY_THEN)

        while self.look['type'] != TokenType.KEY_ENDIF:
            if self.look['type'] == TokenType.SPL_EOF:
                raise ParseError("'end-of-file' while scanning for end of "
                                 "'if' statement, 'fi'", cfg.source_stack.get_source_info())
            elif self.look['type'] == TokenType.KEY_ELIF:
                self.__match(TokenType.KEY_ELIF)
                gated_statement_list.append([expr, filter(lambda n: not isinstance(n, tree.Empty), stmt_list)])

                try:
                    expr = self.__basic_expression()
                except ParseError:
                    raise ParseError("Syntax error in conditional expression for "
                                     "'if' statement", cfg.source_stack.get_source_info())

                stmt_list = []

                self.__match(TokenType.KEY_THEN)

                while self.look['type'] != TokenType.KEY_ENDIF:
                    if self.look['type'] in (TokenType.SPL_EOF, TokenType.KEY_ELSE, TokenType.KEY_ELIF):
                        break
                    else:
                        stmt_list.append(self.__statement())
            elif self.look['type'] == TokenType.KEY_ELSE:
                self.__match(TokenType.KEY_ELSE)
                gated_statement_list.append([expr, filter(lambda n: not isinstance(n, tree.Empty), stmt_list)])

                expr = tree.Integer(1)
                stmt_list = []

                while self.look['type'] != TokenType.KEY_ENDIF:
                    if self.look['type'] == TokenType.SPL_EOF:
                        break
                    else:
                        stmt_list.append(self.__statement())
            else:
                stmt_list.append(self.__statement())

        gated_statement_list.append([expr, filter(lambda n: not isinstance(n, tree.Empty), stmt_list)])

        self.__match(TokenType.KEY_ENDIF)
        self.__match(TokenType.OPR_NEWLINE)

        for gated_statement in gated_statement_list:
            gated_statement[1] = tree.Statement(gated_statement[1], source_info=cfg.source_stack.get_source_info())

        if_stmt = tree.If(gated_statement_list, source_info=cfg.source_stack.get_source_info())

        return if_stmt

    def __else_statement(self):
        self.__match(TokenType.KEY_ELSE)
        raise ParseError("'else' without a matching 'if'", cfg.source_stack.get_source_info())

    def __elif_statement(self):
        self.__match(TokenType.KEY_ELIF)
        raise ParseError("'elif' without a matching 'if'", cfg.source_stack.get_source_info())

    # <while_statement> ::= while <basic_expression> do <statement> od

    def __while_statement(self):
        """The while statement implementation.
        
        This method handles while loops in the language. 
        The BNF form is:
        
            <while_statement> ::= while <basic_expression> do <statement> od
        """
        stmt_list = []

        self.__match(TokenType.KEY_WHILE)

        try:
            expr = self.__basic_expression()
        except ParseError:
            raise ParseError("Syntax error in conditional expression for "
                             "'while' statement", cfg.source_stack.get_source_info())

        self.__match(TokenType.KEY_DO)

        self.in_loop += 1

        while self.look['type'] != TokenType.KEY_ENDWHILE:
            if self.look['type'] == TokenType.SPL_EOF:
                raise ParseError("'end-of-file' while scanning for end of "
                                 "'while' statement, 'od'", cfg.source_stack.get_source_info())
            else:
                stmt_list.append(self.__statement())

        self.in_loop -= 1

        self.__match(TokenType.KEY_ENDWHILE)
        self.__match(TokenType.OPR_NEWLINE)

        stmt_list = filter(lambda n: not isinstance(n, tree.Empty), stmt_list)
        stmt = tree.Statement(stmt_list, source_info=cfg.source_stack.get_source_info())

        while_stmt = tree.While(expr, stmt, source_info=cfg.source_stack.get_source_info())

        return while_stmt

    # <comment_statement> ::= ! .* <new_line>

    def __comment_statement(self):
        """The comment statement implementation.
        
        This method handles comments in the language. 
        The BNF form is:
        
            <comment_statement> ::= ! <message> <new_line>
        """
        text = self.look['attribute']

        #self.__match(TokenType.SPL_COMMENT)
        if self.look['type'] == TokenType.SPL_COMMENT:
            self.__move()

        cmnt_stmt = tree.Comment(text, source_info=cfg.source_stack.get_source_info())

        return cmnt_stmt

    # <print_statement> ::= print <expression_list>
    # <expression_list> ::= <expression> , <expression_list> |
    #                       <expression_list>

    def __print_statement(self):
        """The print statement implementation.
        
        This method implements the print statemnent.
        This statement evaluates and prints a comma separated list of basic expressions.
        The BNF form is:
        
            <print_statement> ::= print <expression_list>
            <expression_list> ::= <basic_expression> , <expression_list> | 
                                  <expression>
        """
        self.__match(TokenType.KEY_PRINT)
        expr_list = [self.__basic_expression()]

        while self.look['type'] == TokenType.OPR_COMMA:
            self.__match(TokenType.OPR_COMMA)
            expr_list.append(self.__basic_expression())

        prnt_stmt = tree.Print(expr_list, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return prnt_stmt

    # <break_statement> ::= break

    def __break_statement(self):
        """The break statement implementation.
        
        This method implements a break statement.
        It can be used to break from a while loop. 
        The BNF form is:
        
            <break_statement> ::= break
        """
        if not self.in_loop:
            raise ParseError("'break' outside 'while' statement",
                             cfg.source_stack.get_source_info())

        self.__match(TokenType.KEY_BREAK)

        brk_stmt = tree.Break(source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return brk_stmt

    # <continue_statement> ::= continue

    def __continue_statement(self):
        """The continue statement implementation.
        
        This method implements the continue statement.
        It can be used to skip the remainder of a while loop. 
        The BNF form is:
        
            <continue_statement> ::= continue
        """
        if not self.in_loop:
            raise ParseError("'continue' outside 'while' statement",
                             cfg.source_stack.get_source_info())

        self.__match(TokenType.KEY_CONTINUE)

        cont_stmt = tree.Continue(source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return cont_stmt

    def __return_statement(self):
        """The return statement implementation.
        
        This method handles the return statement.
        It can be used to return from a function. 
        The BNF form is:
        
            <return_statement> ::= return <expression> |
                                   return
        """
        if not self.in_func:
            raise ParseError("'return' outside 'function' statement",
                             cfg.source_stack.get_source_info())

        self.__match(TokenType.KEY_RETURN)

        if self.look['type'] == TokenType.OPR_NEWLINE:
            expr = None
        else:
            expr = self.__assignment()

        ret_stmt = tree.Return(expr, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return ret_stmt

    def __delete_parameters(self):
        if self.look['type'] in (
                TokenType.TYP_UNKNOWN, TokenType.TYP_VARIABLE, TokenType.TYP_SYMBOL, TokenType.TYP_MACRO,
                TokenType.TYP_FUNC):
            return self.look['text'].lower()
        elif self.look['type'] == TokenType.OPR_PARAMS:
            raise ParseError("Cannot delete scoped names", cfg.source_stack.get_source_info())
        else:
            raise ParseError("Syntax error in delete statement", cfg.source_stack.get_source_info())

    def __expand_parameters(self):
        if self.look['type'] in (TokenType.TYP_UNKNOWN, TokenType.TYP_MACRO, TokenType.TYP_FUNC):
            return self.look['text'].lower()
        else:
            raise ParseError("Syntax error in expand statement", cfg.source_stack.get_source_info())

    def __expand_statement(self):
        self.__match(TokenType.KEY_EXPAND)

        expand_list = [self.__expand_parameters()]

        self.__move()

        while self.look['type'] == TokenType.OPR_COMMA:
            self.__match(TokenType.OPR_COMMA)
            expand_list.append(self.__expand_parameters())
            self.__move()

        expand_list = tree.Expand(expand_list, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return expand_list

    # <wfc_statement> ::= wfc maxwait=<value> <symbol_statement_list>

    def __wfc_statement(self):
        """The while statement implementation.
        
        This method handles while loops in the language. 
        The BNF form is:
        
            <while_statement> ::= while <basic_expression> do <statement> od
        """
        # The timeoutval is used to specify the maximum number of 
        # frames to wait before the condition is automatically 
        # considered satisfied. This has a default minimum of 50 
        # and a maximum of 32767.
        self.__match(TokenType.KEY_WFC)

        if self.look['type'] == TokenType.RES_MAXWAIT:
            self.__match(TokenType.RES_MAXWAIT)
            self.__match(TokenType.OPR_EQUAL)

            if self.look['type'] == TokenType.LIT_INT:
                wait_expr = tree.Integer(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
                self.__match(TokenType.LIT_INT)
            elif self.look['type'] == TokenType.LIT_FLOAT:
                wait_expr = tree.Integer(int(self.look['attribute']), source_info=cfg.source_stack.get_source_info())
                self.__match(TokenType.LIT_FLOAT)
            else:
                raise ParseError("Value for 'maxwait' expected as 'integer' for statement 'wfc'",
                                 cfg.source_stack.get_source_info())
        else:
            wait_expr = tree.Integer(32767, source_info=cfg.source_stack.get_source_info())

        try:
            sym_stmt = self.__symbol_statement_list()
        except ParseError:
            raise ParseError("Syntax error in symbol statement for "
                             "'wfc' statement", cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        wfc_stmt = tree.Wfc(wait_expr, sym_stmt, source_info=cfg.source_stack.get_source_info())

        return wfc_stmt

    def __delete_statement(self):
        """The delete statement implementation.
                                                                                                                             
        This method handles delete statements in the language.
        This can be used to delete names (variables, symbols, macros and functions) 
        that are currently loaded in AITESS.
        The BNF form is:
                                                                                                                             
            <delete_statement> ::= delete <name> (, <name>)*
        """
        self.__match(TokenType.KEY_DELETE)

        del_list = [self.__delete_parameters()]

        self.__move()

        while self.look['type'] == TokenType.OPR_COMMA:
            self.__match(TokenType.OPR_COMMA)
            del_list.append(self.__delete_parameters())
            self.__move()

        del_stmt = tree.Delete(del_list, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return del_stmt

    def __tip_mrhp_statement(self):
        self.__match(TokenType.RES_MRHP)

        try:
            # The address.
            address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MRHP address", cfg.source_stack.get_source_info())

        mrhp_stmt = tree.TipMrhp(address, source_info=cfg.source_stack.get_source_info())

        return mrhp_stmt

    def __tip_mrfp_statement(self):
        self.__match(TokenType.RES_MRFP)

        try:
            # The address.
            address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MRFP address", cfg.source_stack.get_source_info())

        mrfp_stmt = tree.TipMrfp(address, source_info=cfg.source_stack.get_source_info())

        return mrfp_stmt

    def __tip_db_statement(self):
        self.__match(TokenType.RES_DB)

        try:
            # The start address.
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DB start address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DB end address", cfg.source_stack.get_source_info())

        db_stmt = tree.TipDb(start_address, end_address, source_info=cfg.source_stack.get_source_info())

        return db_stmt

    def __tip_dw_statement(self):
        self.__match(TokenType.RES_DW)

        try:
            # The start address.
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DW start address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DW end address", cfg.source_stack.get_source_info())

        dw_stmt = tree.TipDw(start_address, end_address, source_info=cfg.source_stack.get_source_info())

        return dw_stmt

    def __tip_dd_statement(self):
        self.__match(TokenType.RES_DD)

        try:
            # The start address.
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DD start address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DD end address", cfg.source_stack.get_source_info())

        dd_stmt = tree.TipDd(start_address, end_address, source_info=cfg.source_stack.get_source_info())

        return dd_stmt

    def __tip_mrhrp_statement(self):
        self.__match(TokenType.RES_MRHRP)

        try:
            # The start address.
            address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MRHRP address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            data = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MRHRP data", cfg.source_stack.get_source_info())

        mrhrp_stmt = tree.TipMrhrp(address, data, source_info=cfg.source_stack.get_source_info())

        return mrhrp_stmt

    def __tip_mrfrp_statement(self):
        self.__match(TokenType.RES_MRFRP)

        try:
            # The start address.
            address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MRFRP address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            data = self.__bool()  #self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MRFRP data", cfg.source_stack.get_source_info())

        mrfrp_stmt = tree.TipMrfrp(address, data, source_info=cfg.source_stack.get_source_info())

        return mrfrp_stmt

    def __tip_fb_statement(self):
        self.__match(TokenType.RES_FB)

        try:
            # The start address.
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FB start address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FB end address", cfg.source_stack.get_source_info())

        try:
            # The byte data.
            data = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FB data", cfg.source_stack.get_source_info())

        fb_stmt = tree.TipFb(start_address, end_address, data, source_info=cfg.source_stack.get_source_info())

        return fb_stmt

    def __tip_fw_statement(self):
        self.__match(TokenType.RES_FW)

        try:
            # The start address.
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FW start address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FW end address", cfg.source_stack.get_source_info())

        try:
            # The word data.
            data = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FW data", cfg.source_stack.get_source_info())

        fw_stmt = tree.TipFw(start_address, end_address, data, source_info=cfg.source_stack.get_source_info())

        return fw_stmt

    def __tip_fd_statement(self):
        self.__match(TokenType.RES_FD)

        try:
            # The start address.
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FD start address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FD end address", cfg.source_stack.get_source_info())

        try:
            # The double word data.
            data = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FD data", cfg.source_stack.get_source_info())

        fd_stmt = tree.TipFd(start_address, end_address, data, source_info=cfg.source_stack.get_source_info())

        return fd_stmt

    def __tip_lb_statement(self):
        self.__match(TokenType.RES_LB)

        try:
            # The start address.
            start_addr = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # LB start address", cfg.source_stack.get_source_info())

        # The byte data.
        data_list = []
        while self.look['type'] != TokenType.OPR_NEWLINE:
            data_list.append(self.__get_hex())

        if len(data_list) == 0:
            raise ParseError("Data parameters expected for TIP # LB statement",
                             cfg.source_stack.get_source_info())

        lb_stmt = tree.TipLb(start_addr, data_list, source_info=cfg.source_stack.get_source_info())

        return lb_stmt

    def __tip_lw_statement(self):
        self.__match(TokenType.RES_LW)

        try:
            # The start address.
            start_addr = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # LW start address", cfg.source_stack.get_source_info())

        # The byte data.
        data_list = []
        while self.look['type'] != TokenType.OPR_NEWLINE:
            data_list.append(self.__get_hex())

        if len(data_list) == 0:
            raise ParseError("Data parameters expected for TIP # LW statement",
                             cfg.source_stack.get_source_info())

        lw_stmt = tree.TipLw(start_addr, data_list, source_info=cfg.source_stack.get_source_info())

        return lw_stmt

    def __tip_ld_statement(self):
        self.__match(TokenType.RES_LD)

        try:
            # The start address.
            start_addr = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # LD start address", cfg.source_stack.get_source_info())

        # The byte data.
        data_list = []
        while self.look['type'] != TokenType.OPR_NEWLINE:
            data_list.append(self.__get_hex())

        if len(data_list) == 0:
            raise ParseError("Data parameters expected for TIP # LD statement",
                             cfg.source_stack.get_source_info())

        ld_stmt = tree.TipLd(start_addr, data_list, source_info=cfg.source_stack.get_source_info())

        return ld_stmt

    def __tip_cs_statement(self):
        if self.look['type'] == TokenType.RES_CS:
            self.__match(TokenType.RES_CS)
        elif self.look['type'] == TokenType.RES_CH:
            self.__match(TokenType.RES_CH)

        try:
            # The start address.
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # CS/CH start address", cfg.source_stack.get_source_info())

        try:
            # The end address.
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # CS/CH end address", cfg.source_stack.get_source_info())

        cs_stmt = tree.TipCs(start_address, end_address, source_info=cfg.source_stack.get_source_info())

        return cs_stmt

    def __tip_wdm_statement(self):
        self.__match(TokenType.RES_WDM)

        wdm_stmt = tree.TipWdm(source_info=cfg.source_stack.get_source_info())

        return wdm_stmt

    def __tip_dmas_statement(self):
        self.__match(TokenType.RES_DMAS)

        dmas_stmt = tree.TipDmas(source_info=cfg.source_stack.get_source_info())

        return dmas_stmt

    def __tip_dmar_statement(self):
        self.__match(TokenType.RES_DMAR)

        dmar_stmt = tree.TipDmar(source_info=cfg.source_stack.get_source_info())

        return dmar_stmt

    def __tip_epr_statement(self):
        self.__match(TokenType.RES_EPR)

        is_normal = True

        if self.look['type'] == TokenType.RES_N:
            self.__match(TokenType.RES_N)
        elif self.look['type'] == TokenType.RES_T:
            self.__match(TokenType.RES_T)
            is_normal = False

        if self.look['type'] == TokenType.RES_ENB:
            self.__match(TokenType.RES_ENB)
            if is_normal:
                return tree.TipEprNEnb(source_info=cfg.source_stack.get_source_info())
            else:
                return tree.TipEprTEnb(source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.RES_DSB:
            self.__match(TokenType.RES_DSB)
            if is_normal:
                return tree.TipEprNDsb(source_info=cfg.source_stack.get_source_info())
            else:
                return tree.TipEprTDsb(source_info=cfg.source_stack.get_source_info())
        elif self.look['type'] == TokenType.RES_ERS:
            self.__match(TokenType.RES_ERS)
            if is_normal:
                return tree.TipEprNErs(source_info=cfg.source_stack.get_source_info())
            else:
                return tree.TipEprTErs(source_info=cfg.source_stack.get_source_info())
        else:
            raise ParseError("Syntax error in TIP # EPR statement",
                             cfg.source_stack.get_source_info())

    def __tip_bo_statement(self):
        self.__match(TokenType.RES_BO)

        bo_stmt = tree.TipBo(source_info=cfg.source_stack.get_source_info())

        return bo_stmt

    def __tip_pr_statement(self):
        raise ParseError("TIP command PR not yet implemented", cfg.source_stack.get_source_info())

    def __tip_ha_statement(self):
        raise ParseError("TIP command HA not yet implemented", cfg.source_stack.get_source_info())

    def __tip_re_statement(self):
        raise ParseError("TIP command RE not yet implemented", cfg.source_stack.get_source_info())

    def __tip_df_statement(self):
        self.__match(TokenType.RES_DF)

        try:
            # The FIFO address
            fifo_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DF address", cfg.source_stack.get_source_info())

        try:
            # The number of locations
            count = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # DF count", cfg.source_stack.get_source_info())

        df_stmt = tree.TipDf(fifo_address, count, source_info=cfg.source_stack.get_source_info())

        return df_stmt

    def __tip_ffc_statement(self):
        self.__match(TokenType.RES_FFC)

        try:
            # The FIFO address
            fifo_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FFC address", cfg.source_stack.get_source_info())

        try:
            # The initial data
            data = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FFC constant data", cfg.source_stack.get_source_info())

        try:
            # The number of locations
            count = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FFC count", cfg.source_stack.get_source_info())

        ffc_stmt = tree.TipFfc(fifo_address, data, count, source_info=cfg.source_stack.get_source_info())

        return ffc_stmt

    def __tip_ffi_statement(self):
        self.__match(TokenType.RES_FFI)

        try:
            # The FIFO address
            fifo_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FFI address", cfg.source_stack.get_source_info())

        try:
            # The initial data
            initial_data = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FFI initial data", cfg.source_stack.get_source_info())

        try:
            # The number of locations
            count = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # FFI count", cfg.source_stack.get_source_info())

        ffi_stmt = tree.TipFfi(fifo_address, initial_data, count, source_info=cfg.source_stack.get_source_info())

        return ffi_stmt

    def __tip_mtd_statement(self):
        self.__match(TokenType.RES_MTD)

        try:
            # The start address
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTD start address", cfg.source_stack.get_source_info())

        try:
            # The end address
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTD end address", cfg.source_stack.get_source_info())

        try:
            # The bit
            bit = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTD march type", cfg.source_stack.get_source_info())

        mtd_stmt = tree.TipMtd(start_address, end_address, bit, source_info=cfg.source_stack.get_source_info())

        return mtd_stmt

    def __tip_mtw_statement(self):
        self.__match(TokenType.RES_MTW)

        try:
            # The start address
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTW start address", cfg.source_stack.get_source_info())

        try:
            # The end address
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTW end address", cfg.source_stack.get_source_info())

        try:
            # The bit
            bit = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTW march type", cfg.source_stack.get_source_info())

        mtw_stmt = tree.TipMtw(start_address, end_address, bit, source_info=cfg.source_stack.get_source_info())

        return mtw_stmt

    def __tip_mtb_statement(self):
        self.__match(TokenType.RES_MTB)

        try:
            # The start address
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTB start address", cfg.source_stack.get_source_info())

        try:
            # The end address
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTB end address", cfg.source_stack.get_source_info())

        try:
            # The bit
            bit = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # MTB march type", cfg.source_stack.get_source_info())

        mtb_stmt = tree.TipMtb(start_address, end_address, bit, source_info=cfg.source_stack.get_source_info())

        return mtb_stmt

    def __tip_vr_statement(self):
        self.__match(TokenType.RES_VR)

        try:
            # The start address
            start_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # VR start address", cfg.source_stack.get_source_info())

        try:
            # The end address
            end_address = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # VR end address", cfg.source_stack.get_source_info())

        try:
            # The data
            data = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in TIP # VR data pattern", cfg.source_stack.get_source_info())

        vr_stmt = tree.TipVr(start_address, end_address, data, source_info=cfg.source_stack.get_source_info())

        return vr_stmt

    def __tip_p_statement(self):
        self.__match(TokenType.RES_P)

        vr_stmt = tree.TipP(source_info=cfg.source_stack.get_source_info())

        return vr_stmt

    def __tip_pl_statement(self):
        self.__match(TokenType.RES_PL)

        pl_stmt = tree.TipPl(source_info=cfg.source_stack.get_source_info())

        return pl_stmt

    # <tip_statement> ::= tip <tip_command_group>

    def __tip_statement(self):
        """The tip statement implementation.
        
        This method implements the tip statement.
        The BNF form is:
        
            <tip_statement> ::= tip # <tip_command_group>
        """
        self.__match(TokenType.KEY_TIP)

        try:
            self.__match(TokenType.OPR_SHARP)
        except ParseError:
            raise ParseError("'#' expected after TIP", cfg.source_stack.get_source_info())

        # For optional mask and LRU
        mask = 0b1111

        if cfg.legacy_syntax:  # Old syntax
            try:
                if self.look['type'] == TokenType.SPL_ERROR:
                    mask_and_lru = self.look['text']
                    self.__move()
                    if len(mask_and_lru) == 6:
                        mask_text = mask_and_lru[:-2]
                        lru_text = mask_and_lru[-2:]
                        mask = int('0b' + str(mask_text),
                                   2)  # below exception handler will catch if this produces an error
                    else:
                        raise ParseError()  # below exception handler will catch this
            except (ValueError, ParseError):
                raise ParseError("Malformed mask and LRU string for TIP command",
                                 cfg.source_stack.get_source_info())

        tip_stmt = None

        if self.look['type'] == TokenType.RES_BO:
            tip_stmt = self.__tip_bo_statement()
        elif self.look['type'] == TokenType.RES_WDM:
            tip_stmt = self.__tip_wdm_statement()
        elif self.look['type'] == TokenType.RES_DMAS:
            tip_stmt = self.__tip_dmas_statement()
        elif self.look['type'] == TokenType.RES_DMAR:
            tip_stmt = self.__tip_dmar_statement()
        elif self.look['type'] == TokenType.RES_PR:
            tip_stmt = self.__tip_pr_statement()
        elif self.look['type'] == TokenType.RES_MRHP:
            tip_stmt = self.__tip_mrhp_statement()
        elif self.look['type'] == TokenType.RES_MRFP:
            tip_stmt = self.__tip_mrfp_statement()
        elif self.look['type'] == TokenType.RES_DB:
            tip_stmt = self.__tip_db_statement()
        elif self.look['type'] == TokenType.RES_DW:
            tip_stmt = self.__tip_dw_statement()
        elif self.look['type'] == TokenType.RES_DD:
            tip_stmt = self.__tip_dd_statement()
        elif self.look['type'] == TokenType.RES_MRHRP:
            tip_stmt = self.__tip_mrhrp_statement()
        elif self.look['type'] == TokenType.RES_MRFRP:
            tip_stmt = self.__tip_mrfrp_statement()
        elif self.look['type'] == TokenType.RES_FB:
            tip_stmt = self.__tip_fb_statement()
        elif self.look['type'] == TokenType.RES_FW:
            tip_stmt = self.__tip_fw_statement()
        elif self.look['type'] == TokenType.RES_FD:
            tip_stmt = self.__tip_fd_statement()
        elif self.look['type'] == TokenType.RES_LB:
            tip_stmt = self.__tip_lb_statement()
        elif self.look['type'] == TokenType.RES_LW:
            tip_stmt = self.__tip_lw_statement()
        elif self.look['type'] == TokenType.RES_LD:
            tip_stmt = self.__tip_ld_statement()
        elif (self.look['type'] == TokenType.RES_CS) or (self.look['type'] == TokenType.RES_CH):
            tip_stmt = self.__tip_cs_statement()
        elif self.look['type'] == TokenType.RES_EPR:
            tip_stmt = self.__tip_epr_statement()
        elif self.look['type'] == TokenType.RES_HA:
            tip_stmt = self.__tip_ha_statement()
        elif self.look['type'] == TokenType.RES_RE:
            tip_stmt = self.__tip_re_statement()
        elif self.look['type'] == TokenType.RES_DF:
            tip_stmt = self.__tip_df_statement()
        elif self.look['type'] == TokenType.RES_FFC:
            tip_stmt = self.__tip_ffc_statement()
        elif self.look['type'] == TokenType.RES_FFI:
            tip_stmt = self.__tip_ffi_statement()
        elif self.look['type'] == TokenType.RES_MTD:
            tip_stmt = self.__tip_mtd_statement()
        elif self.look['type'] == TokenType.RES_MTW:
            tip_stmt = self.__tip_mtw_statement()
        elif self.look['type'] == TokenType.RES_MTB:
            tip_stmt = self.__tip_mtb_statement()
        elif self.look['type'] == TokenType.RES_VR:
            tip_stmt = self.__tip_vr_statement()
        elif self.look['type'] == TokenType.RES_P:
            tip_stmt = self.__tip_p_statement()
        elif self.look['type'] == TokenType.RES_PL:
            tip_stmt = self.__tip_pl_statement()
        elif self.look['type'] == TokenType.OPR_NEWLINE:
            raise ParseError("TIP command expected after '#'",
                             cfg.source_stack.get_source_info())
        else:
            raise ParseError("Unknown type of TIP command",
                             cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        tip_stmt.add_mask(mask)

        return tip_stmt

    def __inclusion_statement(self):
        self.__match(TokenType.OPR_INCLUSION)

        filename = self.__get_text()

        rdfname = None

        if filename.count(":") == 1:
            (filename, rdfname) = filename.split(":")

        self.__match(
            TokenType.OPR_NEWLINE)  # hari 16/12/2014: fix for rdf file listing @filename comes after contents of filename

        if not filename:
            raise ParseError("File name expected in test plan file inclusion statement",
                             cfg.source_stack.get_source_info())

        if cfg.is_man_mode:
            raise ParseError("Cannot execute test plan files or load databases/macros in 'man' mode",
                             cfg.source_stack.get_source_info())

        self.look_stack.append(self.look)

        # Initialize the entire program's list of  statements.
        self.stmt_lst_with_listing_stack.append(self.stmt_lst_with_listing)
        self.stmt_lst_with_listing = []  # Inclusion statement clear
        # Initialize root of the program tree.
        prgm_root = None

        # Initialize visitors.
        tree_evaluator = evaluatetree.TreeEvaluator()

        # For file opening exceptions.
        try:
            # Open the temporary file for parsing.
            self.scan.open_file(RealTpfFile(filename))
        # For Scanner exceptions, pass that to the main GUI for handling.
        except ScanError:
            self.scan.close_file()
            raise

        # For tree building exceptions i.e. exceptions by the main parser.
        try:
            #
            status = cfg.progress_bar.start_animation('Parsing', '',
                                                      "Parsing file '%s'..." % str(filename).split('/')[-1:][0])
            if status:
                cfg.progress_bar.update_progress_message('')
            #

            # Perform the first move, i.e. of obtain the first token.
            self.scan.reset()
            self.__move()

            # Perform parsing until end-of-file is reached.
            while self.look['type'] != TokenType.SPL_EOF:
                self.stmt_lst_with_listing.append(self.__statement())

            self.stmt_lst_with_listing = filter(lambda n: not isinstance(n, tree.Empty), self.stmt_lst_with_listing)
            # Create a new node representing the statements of the program.
            # NOTE: The new TPF statements and their processed forms are saved in the below
            # statement so that even after the stack is poped this information is not lost.
            stmt = tree.Statement(self.stmt_lst_with_listing)
            # Create the 'program' node and add the statemet node as its child.
            # In effect, this creates the entire tree representation of the 
            # program and now this tree is available for traversal and evaluation.
            prgm_root = tree.Program(stmt, name=filename, user_rdfname=rdfname,
                                     source_info=cfg.source_stack.get_source_info())

            if status:
                cfg.progress_bar.stop_animation()

        # For Scanner and Parser exceptions, pass that to the main
        # GUI for handling.
        except (ScanError, ParseError, EvaluationError, UserExitError, ExitError, AssertError):
            # This exception occurred after the file was opened, so close
            # and delete it.
            if status:
                cfg.progress_bar.stop_animation()
            raise
        except KeyboardInterrupt:
            if status:
                cfg.progress_bar.stop_animation()
            raise ParseError("Parsing terminated through Ctrl-C", cfg.source_stack.get_source_info())
        except RuntimeError as e:
            if status:
                cfg.progress_bar.stop_animation()
            raise ParseError("Deeply nested test plan file inclusion, possibly cyclic (PYERR: %s)" % str(e),
                             cfg.source_stack.get_source_info())
        # For unknown exceptions, raise a parser exception.
        except BaseException as e:
            # This exception occured after the file was opened, so close
            # and delete it.
            if status:
                cfg.progress_bar.stop_animation()
            raise ParseError(GenerateExceptionMessage(), cfg.source_stack.get_source_info())
        finally:
            self.scan.close_file()
        # TODO: Fix closing of opened files
        # TODO: Fix this quick hack
        self.look = self.look_stack.pop()
        # For the answer to the question are we losing TPF processed data see NOTE above
        self.stmt_lst_with_listing = self.stmt_lst_with_listing_stack.pop()

        return prgm_root

    def __download_statement(self):
        """The download statement implementation
        
        This method handles download statements in the language. 
        The BNF form is:
        
            <download_statement> ::= download = <filename>
        """
        self.__match(TokenType.KEY_DOWNLOAD)

        user_mask = 0b1111

        if cfg.legacy_syntax:  # Old syntax
            self.__match(TokenType.RES_LRU)
            self.__match(TokenType.OPR_LBRACKET)
            try:
                user_mask = int(('0b' + str(self.look['text'])), 2)
            except ValueError:
                raise ParseError("Value not a binary literal",
                                 cfg.source_stack.get_source_info())
            self.__move()
            self.__match(TokenType.OPR_RBRACKET)
            try:
                self.__match(TokenType.OPR_EQUAL)
            except ParseError:
                raise ParseError("'=' expected after download", cfg.source_stack.get_source_info())

            if self.look['text'].upper() in ('F1', 'F2', 'F3', 'F4'):
                self.__move()
            else:
                raise ParseError("LRU name (F1, F2, F3 or F4) expected after '=' in download statement",
                                 cfg.source_stack.get_source_info())
            # expects corresponding .chk in the directory
            filename = tree.String("%s.chk" % self.__translate_vax_filespec()[:-4],
                                   source_info=cfg.source_stack.get_source_info())
        else:  # New syntax
            try:
                self.__match(TokenType.OPR_EQUAL)
            except ParseError:
                raise ParseError("'=' expected after download", cfg.source_stack.get_source_info())

            try:
                filename = self.__get_filename()
            except ParseError:
                raise ParseError("Empty filename for download statement", cfg.source_stack.get_source_info())

        if not filename:
            raise ParseError("File name expected in doenload statement",
                             cfg.source_stack.get_source_info())

        dwn_stmt = tree.Download(filename, user_mask, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return dwn_stmt

    def __upload_statement(self):
        """The upload statement implementation
        
        This method handles upload statements in the language. 
        The BNF form is:
        
            <upload_statement> ::= upload = <filename> , <start_address> , <end_address>
                                   upload = <filename> , [ <expression> ] , [ <expression> ]
        """
        self.__match(TokenType.KEY_UPLOAD)

        try:
            self.__match(TokenType.OPR_EQUAL)
        except ParseError:
            raise ParseError("'=' expected after upload", cfg.source_stack.get_source_info())

        try:
            filename = self.__get_filename()
        except ParseError:
            raise ParseError("Empty filename for upload statement", cfg.source_stack.get_source_info())

        try:
            self.__match(TokenType.OPR_COMMA)
        except ParseError:
            raise ParseError("',' expected after filename in upload statement", cfg.source_stack.get_source_info())

        try:
            start_addr = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in upload start address", cfg.source_stack.get_source_info())

        try:
            self.__match(TokenType.OPR_COMMA)
        except ParseError:
            raise ParseError("',' expected after start address in upload statement", cfg.source_stack.get_source_info())

        try:
            end_addr = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in upload end address", cfg.source_stack.get_source_info())

        if not filename:
            raise ParseError("File name expected in upload statement",
                             cfg.source_stack.get_source_info())

        up_stmt = tree.Upload(filename, start_addr, end_addr, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return up_stmt

    def __verify_statement(self):
        """The verify statement implementation
        
        This method handles verify statements in the language. 
        The BNF form is:
        
            <verify_statement> ::= verify = <filename> , <start_address> , <end_address> |
                                   verify = <filename> , [ <expression> ] , [ <expression> ]
        """
        self.__match(TokenType.KEY_VERIFY)

        try:
            self.__match(TokenType.OPR_EQUAL)
        except ParseError:
            raise ParseError("'=' expected after verify", cfg.source_stack.get_source_info())

        try:
            filename = self.__get_filename()
        except ParseError:
            raise ParseError("Empty filename for verify statement", cfg.source_stack.get_source_info())

        try:
            self.__match(TokenType.OPR_COMMA)
        except ParseError:
            raise ParseError("',' expected after filename in verify statement", cfg.source_stack.get_source_info())

        try:
            start_addr = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in verify start address", cfg.source_stack.get_source_info())

        try:
            self.__match(TokenType.OPR_COMMA)
        except ParseError:
            raise ParseError("',' expected after start address in verify statement", cfg.source_stack.get_source_info())

        try:
            end_addr = self.__get_hex()
        except ParseError:
            raise ParseError("Syntax error in verify end address", cfg.source_stack.get_source_info())

        if not filename:
            raise ParseError("File name expected in verify statement",
                             cfg.source_stack.get_source_info())

        vr_stmt = tree.Verify(filename, start_addr, end_addr, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return vr_stmt

    def __dchan_statement(self):
        """The dchan statement implementation
        
        This method handles dchan statements in the language. 
        The BNF form is:
        
            <dchan_statement> ::= dchan = (1|0)+ | 
                                  dchan = [ <expression> ]
        """
        self.__match(TokenType.KEY_DCHAN)

        try:
            self.__match(TokenType.OPR_EQUAL)
        except ParseError:
            raise ParseError("'=' expected after dchan", cfg.source_stack.get_source_info())

        try:
            global_mask = self.__get_bin()
        except ParseError:
            raise ParseError("Syntax error in dchan mask", cfg.source_stack.get_source_info())

        if isinstance(global_mask, tree.Binary) and global_mask.value not in range(16):
            raise ParseError("Invalid range for dchan mask value, should be "
                             "in range [0, 15]", cfg.source_stack.get_source_info())

        dchan_stmt = tree.Dchan(global_mask, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return dchan_stmt

    def __list_statement(self):
        """The list statement implementation
        
        This method handles handles list statements in the language.
        This can be used to list all names (variables, symbols, macros and functions) 
        or names matching a pattern that are currently loaded in AITESS.
        The BNF form is:
        
            <list_statement> ::= list <filename_pattern> : <name_pattern> |
                                 list <name_pattern> |
                                 list
        """
        self.__match(TokenType.KEY_LIST)

        list_spec = self.__get_text().split(':', 1)

        if len(list_spec) == 1:
            list_spec_filename = ''
            list_spec_name = list_spec[0].lower()
        else:
            list_spec_filename = list_spec[0]
            list_spec_name = list_spec[1].lower()

        list_spec_filename = list_spec_filename.replace('*', '.*')
        list_spec_name = list_spec_name.replace('*', '.*')

        search_stmt = tree.List(list_spec_filename, list_spec_name, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return search_stmt

    def __opmsg_statement(self):
        """The opmsg statement implementation.
        
        This method handles opmsg statements in the language. 
        It can be used to display a message (optional) to the user.
        The BNF form is:
        
            <opmsg_statement> ::= opmsg <message> |
                                  opmsg
        """
        self.__match(TokenType.KEY_OPMSG)

        if cfg.legacy_syntax:  # Old syntax
            # 28/01/2015: hari
            # RFA without a number dated 27/01/2015
            # "4. In test file OPMSG with ; is not working. OPMSG has to take all the characters."
            # the below code prints an additional ";" at the end.
            message = ""
            while self.look['text'] != '\n':
                message += self.__get_text(separated=True)
                if self.look['text'] == ';':
                    message += ';'
                    self.__move()
        else:
            message = self.__get_text(separated=True)

        opmsg_stmt = tree.OpMsg(message, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return opmsg_stmt

    def __opwait_statement(self):
        """The opwait statement implementation.
        
        This method handles opwait statements in the language. 
        It can be used to display a message (optional) and wait for user action.
        The BNF form is:
        
            <opwait_statement> ::= opwait <message> |
                                   opwait
        """
        self.__match(TokenType.KEY_OPWAIT)

        if cfg.legacy_syntax:  # Old syntax
            # 28/01/2015: hari
            # RFA without a number dated 27/01/2015
            # "4. In test file OPMSG with ; is not working. OPMSG has to take all the characters."
            # the below code prints an additional ";" at the end.
            message = ""
            while self.look['text'] != '\n':
                message += self.__get_text(separated=True)
                if self.look['text'] == ';':
                    message += ';'
                    self.__move()
        else:
            message = self.__get_text(separated=True)

        opwait_stmt = tree.OpWait(message, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return opwait_stmt

    def __exit_statement(self):
        """The exit statement implementation.
        
        This method handles exit statements in the language. 
        This statement can be used to exit a test plan file unconditionally.
        The BNF form is:
        
            <exit_statement> ::= exit
        """
        self.__match(TokenType.KEY_EXIT)

        exit_stmt = tree.Exit(source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return exit_stmt

    def __assert_statement(self):
        """The assert statement implementation.
        
        This method handles assert statements in the language.
        Assert statements can be used to exit a test plan file with a message (optional) 
        if their associated expression evaluates to false.
        The BNF form is:
        
            <assert_statement> ::= assert <basic_expression> , <string> |
                                   assert <basic_expression>
        """
        self.__match(TokenType.KEY_ASSERT)

        expr = self.__basic_expression()

        if self.look['type'] == TokenType.OPR_COMMA:
            self.__match(TokenType.OPR_COMMA)
            asrt_stmt = tree.Assert(expr, self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_STRING)
        else:
            asrt_stmt = tree.Assert(expr, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return asrt_stmt

    def __empty_statement(self):
        self.__match(TokenType.OPR_NEWLINE)
        try:
            stmt = tree.Empty(source_info=cfg.source_stack.get_source_info())
        except:
            stmt = tree.Empty()

        return stmt

    def __macroname_statement(self):
        """The macroname statement implementation.
        
        This method handles macro declaration statements in the language. 
        The BNF form is:
        
            <macroname_statement> ::= macroname = <identifier> <statement_list> endm
        """
        self.__match(TokenType.KEY_MACDECL)
        self.__match(TokenType.OPR_EQUAL)

        try:
            macro_name = self.look['attribute']
            self.__match(TokenType.TYP_UNKNOWN)
        except ParseError:
            raise ParseError("Illegal name for a new macro", cfg.source_stack.get_source_info())

        cfg.symbol_table.put_entry(macro_name, Macro(macro_name, []))

        self.__match(TokenType.OPR_NEWLINE)
        self.stmt_lst_with_listing_stack.append(self.stmt_lst_with_listing)
        self.stmt_lst_with_listing = []  # Inclusion statement clear

        try:
            while (self.look['type'] != TokenType.SPL_EOF) and \
                    (self.look['type'] != TokenType.KEY_ENDMACDECL) and \
                    (self.look['type'] != TokenType.KEY_MACDECL):
                self.stmt_lst_with_listing.append(self.__statement())
        except:
            cfg.symbol_table.del_entry(macro_name)
            raise

        self.stmt_lst_with_listing = filter(lambda n: not isinstance(n, tree.Empty), self.stmt_lst_with_listing)
        stmt = tree.Statement(self.stmt_lst_with_listing)

        if self.look['type'] == TokenType.KEY_ENDMACDECL:
            self.__match(TokenType.KEY_ENDMACDECL)
            self.__match(TokenType.OPR_NEWLINE)

        cfg.symbol_table.get_entry(macro_name).set_expansion(stmt)

        macro_body_listing = filter(lambda n: isinstance(n, tree.InputListing), self.stmt_lst_with_listing)
        self.stmt_lst_with_listing = self.stmt_lst_with_listing_stack.pop() + macro_body_listing

        return tree.Empty(source_info=cfg.source_stack.get_source_info())

    def __function_statement(self):
        """The function statement implementation.
        
        This method handles function declaration statements in the language. 
        The BNF form is:
        
            <function_statement> ::= function = <identifier> <statement_list> endf
        """
        # Mod2: begin
        is_silent = True
        # Mod2: end
        self.__match(TokenType.KEY_FUNCDECL)
        self.__match(TokenType.OPR_EQUAL)

        try:
            func_name = self.look['attribute']
            self.__match(TokenType.TYP_UNKNOWN)
        except ParseError:
            raise ParseError("Illegal name for a new function", cfg.source_stack.get_source_info())

        cfg.symbol_table.put_entry(func_name, Function(func_name, []))

        # Mod2: begin
        if self.look['type'] == TokenType.OPR_MULTIPLY:
            self.__match(TokenType.OPR_MULTIPLY)
            is_silent = False
        # Mod2: end
        self.__match(TokenType.OPR_NEWLINE)
        self.stmt_lst_with_listing_stack.append(self.stmt_lst_with_listing)
        self.stmt_lst_with_listing = []  # Inclusion statement clear

        self.in_func = True

        try:
            while self.look['type'] != TokenType.KEY_ENDFUNCDECL:
                if self.look['type'] == TokenType.SPL_EOF:
                    raise ParseError("'end-of-file' while scanning for end of "
                                     "'function', 'endf'", cfg.source_stack.get_source_info())
                elif self.look['type'] in (TokenType.KEY_SYM, TokenType.KEY_MACDECL, TokenType.KEY_FUNCDECL):
                    raise ParseError("Local declarations of type '%s' are not allowed" % (TokenName[self.look['type']]),
                                     cfg.source_stack.get_source_info())
                self.stmt_lst_with_listing.append(self.__statement())
        except:
            cfg.symbol_table.del_entry(func_name)
            raise

        self.stmt_lst_with_listing = filter(lambda n: not isinstance(n, tree.Empty), self.stmt_lst_with_listing)
        stmt = tree.Statement(self.stmt_lst_with_listing)

        self.in_func = False

        self.__match(TokenType.KEY_ENDFUNCDECL)

        # Mod2: begin
        func_subtree = tree.Function(func_name, stmt, silent=is_silent, source_info=cfg.source_stack.get_source_info())
        # Mod2: end

        cfg.symbol_table.get_entry(func_name).set_node(func_subtree)

        function_body_listing = filter(lambda n: isinstance(n, tree.InputListing), self.stmt_lst_with_listing)
        self.stmt_lst_with_listing = self.stmt_lst_with_listing_stack.pop() + function_body_listing

        return func_subtree

    def __macname_statement(self):
        """The macname statement implementation.
        
        This method handles macro invocation statements in the language. 
        The BNF form is:
        
            <macname_statement> ::= macname = <identifier>
        """
        if cfg.legacy_syntax:  # Old syntax
            try:
                self.__match(TokenType.KEY_MACINVOC_ALT)
            except ParseError:
                self.__match(TokenType.KEY_MACINVOC)
        else:  # New syntax
            if self.look['type'] == TokenType.KEY_MACINVOC_ALT:
                raise ParseError("'macn' is supported only in LTM syntax mode",
                                 cfg.source_stack.get_source_info())
            self.__match(TokenType.KEY_MACINVOC)

        self.__match(TokenType.OPR_EQUAL)

        try:
            macro_name = self.look['attribute']
            self.__match(TokenType.TYP_MACRO)
            self.__match(TokenType.OPR_NEWLINE)
        except ParseError:
            strange_requirement = tree.DelayedParseError(
                "Undefined macro '%s'" % (macro_name if macro_name else self.look['text']),
                source_info=cfg.source_stack.get_source_info())
            self.__skip_till_EOL()
            return strange_requirement

        return tree.MacroInvocation(macro_name, source_info=cfg.source_stack.get_source_info())

    def __help_statement(self):
        """The help statement implementation.
        
        This method handles help statements in the language.
        This statement can be used to display a help on various AITESS programming elements.
        The BNF form is:
                                                                                                                             
            <help_statement> ::= help <programming_element>
        """
        self.__match(TokenType.KEY_HELP)

        stmt_name = self.look['text']
        # no name mangling in Cython????
        if stmt_name != ';':
            method_name = '__%s_statement' % stmt_name
        else:
            method_name = '__help_statement'

        method = getattr(self, method_name, lambda: None)

        if not method.__doc__:
            cfg.output_queue.append(NormalMessage(stmt_name, "No help is associated with item '%s'" % stmt_name))
        else:
            cfg.output_queue.append(NormalMessage(stmt_name, method.__doc__))

        self.__move()

        return tree.Empty()

    def __pass_statement(self):
        """The macname statement implementation.
                                                                                                                            
        This method handles pass statements in the language.
        This statement skips a single frame.
        The BNF form is:
                                                                                                                             
            <pass_statement> ::= pass
        """
        self.__match(TokenType.KEY_PASS)
        return tree.Pass(source_info=cfg.source_stack.get_source_info())

    def __patch_statement(self):
        """The diffs statement implementation.
                                                                                                                             
        This method handles patch statements in the language.
        This statement can be used to generate a test plan file with tip # mrhrp 
        statements that patch the differing locations after the execution of a 
        verify command.
        The BNF form is:
                                                                                                                             
            <patch_statement> ::= patch <channel_number> 
        """
        self.__match(TokenType.KEY_PATCH)

        if self.look['type'] == TokenType.OPR_LSQBRACKET:
            self.__match(TokenType.OPR_LSQBRACKET)
            channel_number_expr = tree.FinalValueExpression(self.__bool(),
                                                            source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_RSQBRACKET)
        elif self.look['type'] == TokenType.LIT_INT:
            channel_number_expr = tree.Integer(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_INT)
        else:
            raise ParseError("Channel number not a numeric value", cfg.source_stack.get_source_info())

        pt_stmt = tree.Patch(channel_number_expr, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return pt_stmt

    def __diffs_statement(self):
        """The diffs statement implementation.
                                                                                                                             
        This method handles diffs statements in the language.
        This statement can be used to find the differing locations after the 
        execution of a verify command.
        The BNF form is:
                                                                                                                             
            <diffs_statement> ::= diffs <channel_number> |
                                  diffs [ <expression> ]
        """
        self.__match(TokenType.KEY_DIFFS)

        if self.look['type'] == TokenType.OPR_LSQBRACKET:
            self.__match(TokenType.OPR_LSQBRACKET)
            channel_number_expr = tree.FinalValueExpression(self.__bool(),
                                                            source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.OPR_RSQBRACKET)
        elif self.look['type'] == TokenType.LIT_INT:
            channel_number_expr = tree.Integer(self.look['attribute'], source_info=cfg.source_stack.get_source_info())
            self.__match(TokenType.LIT_INT)
        else:
            raise ParseError("Channel number not a numeric value", cfg.source_stack.get_source_info())

        df_stmt = tree.Diffs(channel_number_expr, source_info=cfg.source_stack.get_source_info())

        self.__match(TokenType.OPR_NEWLINE)

        return df_stmt

    def __info_statement(self):
        """The info statement implementation.
                                                                                                                             
        This method handles info statements in the language.
        This statement can be used to find the information about a particular name i.e.
        a variable, symbol, macro or a function name.
        The BNF form is:
                                                                                                                             
            <info_statement> ::= info <name>
        """
        self.__match(TokenType.KEY_INFO)
        info_name = self.look['text'].lower()
        self.__move()
        self.__match(TokenType.OPR_NEWLINE)
        return tree.Info(info_name, source_info=cfg.source_stack.get_source_info())

    def __statement(self):
        """The implementation of actions for test plan file statements.
        
        This function identifies the type of statement and calls the 
        respective action implementation function depending on the pass number.
        """
        if self.look['type'] == TokenType.SPL_COMMENT:
            stmt = self.__comment_statement()
        elif self.look['type'] == TokenType.KEY_DOWNLOAD:
            stmt = self.__download_statement()
        elif self.look['type'] == TokenType.KEY_PASS:
            stmt = self.__pass_statement()
        elif self.look['type'] == TokenType.KEY_DIFFS:
            stmt = self.__diffs_statement()
        elif self.look['type'] == TokenType.KEY_INFO:
            stmt = self.__info_statement()
        elif self.look['type'] == TokenType.KEY_UPLOAD:
            stmt = self.__upload_statement()
        elif self.look['type'] == TokenType.KEY_VERIFY:
            stmt = self.__verify_statement()
        elif self.look['type'] == TokenType.KEY_PATCH:
            stmt = self.__patch_statement()
        elif self.look['type'] == TokenType.KEY_DCHAN:
            stmt = self.__dchan_statement()
        elif self.look['type'] == TokenType.KEY_LIST:
            stmt = self.__list_statement()
        elif self.look['type'] == TokenType.KEY_DISPLAY:
            stmt = self.__display_statement()
        elif self.look['type'] == TokenType.KEY_LOGGING:
            stmt = self.__logging_statement()
        elif self.look['type'] == TokenType.KEY_SYM:
            stmt = self.__sym_decl_statement()
        elif self.look['type'] == TokenType.KEY_IF:
            stmt = self.__if_statement()
        elif self.look['type'] == TokenType.KEY_ELSE:
            stmt = self.__else_statement()
        elif self.look['type'] == TokenType.KEY_ELIF:
            stmt = self.__elif_statement()
        elif self.look['type'] == TokenType.KEY_WHILE:
            stmt = self.__while_statement()
        elif self.look['type'] == TokenType.KEY_BREAK:
            stmt = self.__break_statement()
        elif self.look['type'] == TokenType.KEY_CONTINUE:
            stmt = self.__continue_statement()
        elif self.look['type'] == TokenType.KEY_RETURN:
            stmt = self.__return_statement()
        elif self.look['type'] == TokenType.KEY_TIP:
            stmt = self.__tip_statement()
        elif self.look['type'] == TokenType.KEY_OPMSG:
            stmt = self.__opmsg_statement()
        elif self.look['type'] == TokenType.KEY_EXIT:
            stmt = self.__exit_statement()
        elif self.look['type'] == TokenType.KEY_ASSERT:
            stmt = self.__assert_statement()
        elif self.look['type'] == TokenType.KEY_OPWAIT:
            stmt = self.__opwait_statement()
        elif self.look['type'] == TokenType.OPR_NEWLINE:
            stmt = self.__empty_statement()
        elif self.look['type'] == TokenType.KEY_PRINT:
            stmt = self.__print_statement()
        elif self.look['type'] == TokenType.KEY_WAIT:
            stmt = self.__wait_statement()
        elif self.look['type'] == TokenType.KEY_DELETE:
            stmt = self.__delete_statement()
        elif self.look['type'] == TokenType.KEY_MACDECL:
            stmt = self.__macroname_statement()
        elif self.look['type'] == TokenType.KEY_FUNCDECL:
            stmt = self.__function_statement()
        elif self.look['type'] == TokenType.KEY_MACINVOC:
            stmt = self.__macname_statement()
        elif self.look['type'] == TokenType.KEY_MACINVOC_ALT:
            stmt = self.__macname_statement()
        elif self.look['type'] == TokenType.OPR_INCLUSION:
            stmt = self.__inclusion_statement()
        elif self.look['type'] == TokenType.KEY_HELP:
            stmt = self.__help_statement()
        elif self.look['type'] == TokenType.KEY_FRWAIT:
            stmt = self.__frwait_statement()
        elif self.look['type'] == TokenType.KEY_LOCATE:
            stmt = self.__locate_statement()
        elif self.look['type'] == TokenType.KEY_TPGPH:
            stmt = self.__tpgph_statement()
        elif self.look['type'] == TokenType.KEY_STEP:
            stmt = self.__step_statement()
        elif self.look['type'] == TokenType.KEY_AUTO:
            stmt = self.__auto_statement()
        elif self.look['type'] == TokenType.KEY_MAN:
            stmt = self.__man_statement()
        elif self.look['type'] == TokenType.KEY_LTM_SYNTAX:
            stmt = self.__ltm_syntax_statement()
        elif self.look['type'] == TokenType.KEY_EXPAND:
            stmt = self.__expand_statement()
        elif self.look['type'] == TokenType.KEY_WFC:
            stmt = self.__wfc_statement()
        elif self.look['type'] == TokenType.SPL_ERROR:
            self.__match(TokenType.SPL_ERROR)
            raise ParseError("Unexpected token encountered on/before '%s' in input" % (TokenName[self.look['type']]),
                             cfg.source_stack.get_source_info())
        else:
            stmt = self.__operative_statement()

            # in interactive mode print all evaluation results without an explicit print statement
            if not isinstance(stmt, tree.DelayedParseError) and not self.in_func and not isinstance(stmt.child,
                                                                                                    tree.SymbolStatementList) and not isinstance(
                stmt.child, tree.Assign) and isinstance(cfg.source_stack.get_source_id(), PseudoTpfFile):
                stmt = tree.Print([stmt], source_info=cfg.source_stack.get_source_info())

        return stmt

    def parse(self, file_name):
        """The main parser function.
        
        This function will perform the move to obtain the first token.
        It then repeatedly calls function '__statement' to parse the input 
        till it encounters an end-of-file.
        """
        self.in_func = False
        cfg.generate_rdf = False
        cfg.rdf_filename = ''
        cfg.source_stack.clear()
        # Initialize the entire program's list of  statements.
        stmt_list = []
        # Initialize root of the program tree.
        prgm_root = None

        self.stmt_lst_with_listing = []
        self.stmt_lst_with_listing_stack = []

        # Initialize visitors.
        tree_evaluator = evaluatetree.TreeEvaluator()

        # For file opening exceptions.
        try:
            # Open the temporary file for parsing.
            self.scan.open_file(file_name)
        # For Scanner exceptions, pass that to the main GUI for handling.
        except ScanError:
            self.scan.close_file()
            raise

        # For tree building exceptions i.e. exceptions by the main parser.
        try:
            # Perform the first move, i.e. of obtain the first token.
            self.scan.reset()
            self.__move()

            # Perform parsing until end-of-file is reached.
            while self.look['type'] != TokenType.SPL_EOF:
                stmt_list.append(self.__statement())
        # For Scanner and Parser exceptions, pass that to the main 
        # GUI for handling.
        except (ScanError, ParseError, EvaluationError, UserExitError, ExitError, AssertError):
            # This exception occured after the file was opened, so close 
            # and delete it.
            raise
        except KeyboardInterrupt:
            raise ParseError("Parsing terminated through Ctrl-C", cfg.source_stack.get_source_info())
        # For unknown exceptions, raise a parser exception.
        except BaseException as e:
            # This exception occurred after the file was opened, so close
            # and delete it.
            #raise # for debugging
            raise ParseError(GenerateExceptionMessage(), cfg.source_stack.get_source_info())
        finally:
            self.scan.close_file()

        stmt_list = filter(lambda n: not isinstance(n, tree.Empty), stmt_list)
        # Create a new node representing the statements of the program.
        stmt = tree.Statement(stmt_list)
        # Create the 'program' node and add the statemet node as its child.
        # In effect, this creates the entire tree representation of the 
        # program and now this tree is available for traversal and evaluation.
        prgm_root = tree.Program(stmt)

        # Compile the input file save it using pickle then load the compiled file using unpickle
        # Can be used in future to skip time consuming parsing step
        # BEGIN
        # import pickle
        # f = open('temp.tpc', 'wb')
        # p = pickle.Pickler(f, -1)
        # p.dump(prgm_root)
        # f.close()
        # 
        # f = open('temp.tpc', 'rb')
        # p = pickle.Unpickler(f)
        # prgm_root = p.load()
        # f.close()
        # END

        if self.skip_evaluation:
            return

        gc_was_enabled = gc.isenabled()
        if gc_was_enabled:
            gc.collect()
            gc.disable()

        # For tree evaluation exceptions.
        try:
            if cfg.is_high_priority:
                os.system("chrt -f -p 1 %d" % os.getpid())

            # Evaluate the created AST.
            if self.profile_level == 3:
                import trace
                t = trace.Trace(timing=True)
                t.runfunc(tree_evaluator.visit, prgm_root)
                t.results()
            elif self.profile_level == 2:
                import profile
                p = profile.Profile()
                p.runcall(tree_evaluator.visit, prgm_root)
                p.print_stats()
            elif self.profile_level == 1:
                from time import time
                t = time()
                tree_evaluator.visit(prgm_root)
                print 'tree evaluator took', 1000 * (time() - t), 'milli seconds'
            else:
                tree_evaluator.visit(prgm_root)

        # For Scanner and Parser exceptions, pass that to
        # the main GUI for handling.
        except (ScanError, ParseError, EvaluationError, UserExitError, ExitError, AssertError):
            raise

        # For unknown exceptions, raise a parser exception.
        except BaseException as e:
            #raise # for debugging
            raise EvaluationError(GenerateExceptionMessage(), SourceInfo('«stdin»', 1))
        finally:
            if cfg.is_high_priority:
                os.system("chrt -o -p 0 %d" % os.getpid())
            if gc_was_enabled:
                gc.enable()
            # This exception occurred after the file was opened and the
            # tree was created so, destroy the tree and close and delete 
            # the file.
            del prgm_root
