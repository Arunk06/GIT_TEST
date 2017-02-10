# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : scanner
# File name		        : scanner.pyx
# Usage			        : Definitions of AITESS scanner.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#

import cfg  # For global variables.
from errorhandler import ScanError
from sourceinfo import SourceInfo
from tokens import Token, TokenType, TokenKeyword, TokenResword


class Scanner(object):
    """
    
    """
    # The constructor
    def __init__(self):
        self.reset()

    def __speculating(self):
        return len(self.markers) > 0

    def __read_ahead(self):
        """Reads a single character from the opened temporary file and 
        returns it.
        
        This function reads a single character from the temporary file and 
        returns it.If the end of file is reached an empty string is returned.
        """
        # Read the current character from the file and return it.
        ch = cfg.source_stack.get_source_id().next_char()

        self.coloumn_number += 1

        if (ch == '\n') or (ch == ';'):
            self.coloumn_number = 0

        return ch

    def __move_back(self):
        """Moves back the file pointer by one position.
        
        In the process of identifying a token, the scanner also consumes 
        a character that is part of the next token. To get back this character,
        we need to move back the file pointer by one position.
        """
        cfg.source_stack.get_source_id().roll_back()
        self.coloumn_number -= 1

    def __skip_spaces(self):
        spaces = ''
        # For skipping  all blank spaces.
        while self.peek.isspace() and self.peek != '\n':
            spaces += self.peek
            self.peek = self.__read_ahead()

    def __bin_number(self, num_lexeme):
        num_str = '0b'
        self.peek = self.__read_ahead()

        while self.peek.isalnum():
            num_str += self.peek
            self.peek = self.__read_ahead()

        try:
            num_val = int(num_str, 2)
            return Token(TokenType.LIT_BIN, num_val, (num_lexeme + num_str[2:]))
        except:
            return Token(TokenType.SPL_ERROR, None, (num_lexeme + num_str[2:]))
        finally:
            self.__move_back()

    def __hex_number(self, num_lexeme):
        num_str = '0x'
        self.peek = self.__read_ahead()

        while self.peek.isalnum():
            num_str += self.peek
            self.peek = self.__read_ahead()

        try:
            num_val = int(num_str, 16)
            return Token(TokenType.LIT_HEX, num_val, (num_lexeme + num_str[2:]))
        except:
            return Token(TokenType.SPL_ERROR, None, (num_lexeme + num_str[2:]))
        finally:
            self.__move_back()

    def __oct_number(self, num_lexeme):
        num_str = '0o'
        self.peek = self.__read_ahead()

        while self.peek.isalnum():
            num_str += self.peek
            self.peek = self.__read_ahead()

        try:
            num_val = int(num_str, 8)
            return Token(TokenType.LIT_OCT, num_val, (num_lexeme + num_str[2:]))
        except:
            return Token(TokenType.SPL_ERROR, None, (num_lexeme + num_str[2:]))
        finally:
            self.__move_back()

    def __number(self):
        num_lexeme = ''
        num_str = ''
        frac_str = ''
        exp_str = ''

        # If the number starts with a '0'.
        if self.peek == '0':
            num_lexeme += self.peek
            # Get next character.
            self.peek = self.__read_ahead()
            # If that charcter is 'b', then it is a binary number.
            if self.peek.lower() == 'b':
                num_lexeme += self.peek
                return self.__bin_number(num_lexeme)
            elif self.peek.lower() == 'x':
                num_lexeme += self.peek
                return self.__hex_number(num_lexeme)
            elif self.peek.lower() == 'o':
                num_lexeme += self.peek
                return self.__oct_number(num_lexeme)
            else:
                # Retract file pointer twice so that we get to '0'.
                self.__move_back()
                self.__move_back()

            self.peek = self.__read_ahead()

        # decimal begin
        while self.peek.isalnum():  #self.peek.isdigit():
            # if there is an 'E', it might be a number with an exponent part 
            # hand it down below
            if self.peek.lower() == 'e':
                break
            num_str += self.peek
            self.peek = self.__read_ahead()

        num_lexeme = num_str

        if (self.peek != '.') and (self.peek.lower() != 'e'):
            try:
                num_val = int(num_str)
                return Token(TokenType.LIT_INT, num_val, num_str)
            except:
                return Token(TokenType.SPL_ERROR, None, num_str)
            finally:
                self.__move_back()
        # decimal end

        if self.peek == '.':
            num_lexeme += self.peek
            # skip the decimal
            self.peek = self.__read_ahead()

            while self.peek.isdigit():
                frac_str += self.peek
                self.peek = self.__read_ahead()

            num_lexeme += frac_str

            if self.peek.lower() != 'e':
                try:
                    num_val = float('%s.%s' % (num_str, frac_str))
                    return Token(TokenType.LIT_FLOAT, num_val, num_lexeme)
                except:
                    return Token(TokenType.SPL_ERROR, None, num_lexeme)
                finally:
                    self.__move_back()

        if self.peek.lower() == 'e':
            num_lexeme += self.peek
            # skip the 'e'
            self.peek = self.__read_ahead()

            if self.peek in ('-', '+'):
                exp_str += self.peek
                self.peek = self.__read_ahead()

            while self.peek.isalnum():
                exp_str += self.peek
                self.peek = self.__read_ahead()

            num_lexeme += exp_str

            try:
                num_val = float('%s.%sE%s' % (num_str, frac_str, exp_str))
                return Token(TokenType.LIT_FLOAT, num_val, num_lexeme)
            except:
                return Token(TokenType.SPL_ERROR, None, num_lexeme)
            finally:
                self.__move_back()

        raise ScanError("__number(): Scanner routine encountered trouble", cfg.source_stack.get_source_info())

    def __identifier(self):
        # The name of the identifier.
        id_name = ''
        while self.peek.isalnum() or self.peek == '_':
            id_name += self.peek
            self.peek = self.__read_ahead()

        # Retract file pointer.
        self.__move_back()

        return id_name

    def __string(self):
        str_val = ""
        self.peek = self.__read_ahead()
        while self.peek != "'":
            if self.peek == "\\":
                self.peek = self.__read_ahead()

                if self.peek == "'":
                    str_val += "'"
                elif self.peek == "\\":
                    str_val += "\\"
                elif self.peek == "n":
                    str_val += "\n"
                elif self.peek == "t":
                    str_val += "\t"
                elif self.peek == "r":
                    str_val += "\r"
                elif self.peek == "a":
                    str_val += "\a"
                elif self.peek == "b":
                    str_val += "\b"
                elif self.peek == "v":
                    str_val += "\v"
                else:
                    str_val += "\\" + self.peek
            elif self.peek == '\n':
                raise ScanError("EOL encountered while scanning for end of string literal '''",
                                cfg.source_stack.get_source_info())
            else:
                str_val += self.peek

            self.peek = self.__read_ahead()

            if (self.peek == '') or (self.peek == '\x00'):
                raise ScanError("EOF encountered while scanning for end of string literal '''",
                                cfg.source_stack.get_source_info())

        return str_val

    def __line_comment(self):
        comment_val = '!'
        self.peek = self.__read_ahead()

        while (self.peek != '\n') and (self.peek != ';') and (self.peek != '') and (self.peek != '\x00'):
            comment_val += self.peek
            self.peek = self.__read_ahead()

        if (self.peek == ';') and (comment_val != '!'):
            self.__move_back()

        return True, comment_val

    def __block_comment(self):
        skip_comment = True

        if self.coloumn_number == 2:
            skip_comment = False

        comment_val = '!#'
        self.peek = self.__read_ahead()

        while True:
            comment_val += self.peek

            if self.peek == '\n':
                cfg.source_stack.get_source_info(copy=False).increment_lineno()

            if (self.peek == '') or (self.peek == '\x00'):
                raise ScanError("EOF encountered inside block comment", cfg.source_stack.get_source_info())

            if (len(comment_val) >= 2) and (comment_val[-2:] == '#!'):
                self.peek = self.__read_ahead()  # make peek equal to the next character after '!' of '*!'
                break

            self.peek = self.__read_ahead()

        return skip_comment, comment_val

    def __get_token(self):
        """Returns the next token.
        
        Searches the character stream for a token and return the token once it 
        is found.
        """
        comment_val = ''
        # Read a single character from the file.
        self.peek = self.__read_ahead()

        self.__skip_spaces()

        while self.peek == '!':
            self.peek = self.__read_ahead()
            if self.peek == '#':
                skip_comment, comment_val = self.__block_comment()
            else:
                self.__move_back()
                skip_comment, comment_val = self.__line_comment()

            self.__skip_spaces()

        # For recognising numeric token.
        if self.peek.isdigit():
            return self.__number()
            # For recognising label, identifier and keywords token.
        elif self.peek.isalpha() or self.peek == '_':
            id_name = self.__identifier()
            _id_name = id_name.lower()

            # If the lexeme corresponds to a keyword.
            if _id_name in TokenKeyword.keys():
                # Return the token representing the keyword.
                return Token(TokenKeyword[_id_name], None, id_name)

            # If the lexeme corresponds to a reserved word.
            if _id_name in TokenResword.keys():
                # Return the token representing the reserved word.
                return Token(TokenResword[_id_name], None, id_name)

            # Check the type of name and return. 
            return Token(cfg.symbol_table.get_type(_id_name), _id_name, id_name)
        elif self.peek == '\'':
            str_val = self.__string()
            # The length of the string is the actual string length plus 2 for 
            # the opening and closing quotes.
            return Token(TokenType.LIT_STRING, str_val, ("'%s'" % str_val))
        elif self.peek == '$':
            return Token(TokenType.OPR_PARAMS, None, '$')
        # For end of file stream.
        elif (self.peek == '') or (self.peek == '\x00'):  # TODO: Note the second condition
            #self.__move_back() # Hari: 03/12/2014 why should it move back? let's see without it
            return Token(TokenType.SPL_EOF, None, '')
        elif self.peek == '&':
            return Token(TokenType.OPR_AMPERSAND, None, '&')
        elif (self.peek == '\n') or (self.peek == ';'):
            # increment line number only for explicit new lines
            if self.peek == '\n':
                cfg.source_stack.get_source_info(copy=False).increment_lineno()

            return Token(TokenType.OPR_NEWLINE, comment_val, self.peek)
        elif self.peek == '=':
            if cfg.legacy_syntax:  # Old syntax
                self.peek = self.__read_ahead()
                number_of_moves = 0
                while self.peek.isspace():
                    number_of_moves += 1
                    self.peek = self.__read_ahead()
                if self.peek == '"':
                    return Token(TokenType.OPR_BEQUAL, None, '="')
                while number_of_moves:
                    number_of_moves -= 1
                    self.__move_back()
            else:  # New syntax
                self.peek = self.__read_ahead()
            if self.peek == '=':
                return Token(TokenType.OPR_EQUALTO, None, '==')
            elif self.peek == '"':
                return Token(TokenType.OPR_BEQUAL, None, '="')
            else:
                self.__move_back()
                return Token(TokenType.OPR_EQUAL, None, '=')
        elif self.peek == ':':
            self.peek = self.__read_ahead()
            if self.peek == '=':
                return Token(TokenType.OPR_ASSIGN, None, ':=')
            else:
                self.__move_back()  # hari: On 17/Dec/2012 hungry colon bug :-) fixed
                return Token(TokenType.SPL_ERROR, ':', ':')
        elif self.peek == '<':
            self.peek = self.__read_ahead()
            if self.peek == '>':
                self.peek = self.__read_ahead()
                if self.peek == '"':
                    return Token(TokenType.OPR_BNOTEQUALTO, None, '<>"')
                else:
                    self.__move_back()
                    return Token(TokenType.OPR_NOTEQUALTO, None, '<>')
            elif self.peek == '=':
                self.peek = self.__read_ahead()
                if self.peek == '"':
                    return Token(TokenType.OPR_BLEQUALTO, None, '<="')
                else:
                    self.__move_back()
                    return Token(TokenType.OPR_LEQUALTO, None, '<=')
            elif self.peek == '"':
                return Token(TokenType.OPR_BLESSER, None, '<"')
            elif self.peek == '<':
                return Token(TokenType.OPR_LSHIFT, None, '<<')
            else:
                self.__move_back()
                return Token(TokenType.OPR_LESSER, None, '<')
        elif self.peek == '>':
            self.peek = self.__read_ahead()
            if self.peek == '=':
                self.peek = self.__read_ahead()
                if self.peek == '"':
                    return Token(TokenType.OPR_BGEQUALTO, None, '>="')
                else:
                    self.__move_back()
                    return Token(TokenType.OPR_GEQUALTO, None, '>=')
            elif self.peek == '"':
                return Token(TokenType.OPR_BGREATER, None, '>"')
            elif self.peek == '>':
                return Token(TokenType.OPR_RSHIFT, None, '>>')
            else:
                self.__move_back()
                return Token(TokenType.OPR_GREATER, None, '>')
        elif self.peek == '+':
            return Token(TokenType.OPR_PLUS, None, '+')
        elif self.peek == '-':
            return Token(TokenType.OPR_MINUS, None, '-')
        elif self.peek == '#':
            return Token(TokenType.OPR_SHARP, None, '#')
        elif self.peek == '?':
            return Token(TokenType.OPR_QUESTION, None, '?')
        elif self.peek == '(':
            return Token(TokenType.OPR_LBRACKET, None, '(')
        elif self.peek == ')':
            return Token(TokenType.OPR_RBRACKET, None, ')')
        elif self.peek == ',':
            return Token(TokenType.OPR_COMMA, None, ',')
        elif self.peek == '*':
            return Token(TokenType.OPR_MULTIPLY, None, '*')
        elif self.peek == '/':
            return Token(TokenType.OPR_DIVIDE, None, '/')
        elif self.peek == '%':
            return Token(TokenType.OPR_MODULO, None, '%')
        elif self.peek == '[':
            return Token(TokenType.OPR_LSQBRACKET, None, '[')
        elif self.peek == ']':
            return Token(TokenType.OPR_RSQBRACKET, None, ']')
        elif self.peek == '@':
            return Token(TokenType.OPR_INCLUSION, None, '@')
        else:  # For unknown character in file stream.
            return Token(TokenType.SPL_ERROR, self.peek, self.peek)

    def __end_of_buffer(self):
        return (self.index + 1) == len(self.lookahead)

    def open_file(self, file_):
        """Opens the temporary file.
        
        Opens the temporary file generated by the pre-processor.
        This file is used by the scanner.
        """
        # Open the temporary file which is created by pre-processor.
        cfg.source_stack.push(source_id=file_,
                              source_info=SourceInfo(name=file_.get_name(), lineno=1, max_lines=file_.get_line_count()))
        cfg.source_stack.get_source_id().open()

    def close_file(self):
        """Closes the temporary file.
        """
        # Closes the temporary file.
        cfg.source_stack.get_source_id().close()
        cfg.source_stack.pop()

    def reset(self):
        self.lookahead = []
        self.markers = []
        self.index = -1
        self.coloumn_number = 0

    def mark(self):
        self.markers.append(self.index)

    def release(self):
        self.index = self.markers.pop() - 1

    def get_token(self):
        if not self.__end_of_buffer():
            self.index += 1  # provided we release just before marked position
        elif self.__speculating():
            self.lookahead.append(self.__get_token())
            self.index += 1
        else:
            self.index = 0
            self.lookahead = [self.__get_token()]

        return self.lookahead[self.index]
