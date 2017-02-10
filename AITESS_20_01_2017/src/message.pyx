# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : message
# File name		        : message.pyx
# Usage			        : Provides formatted output for AITESS responses and RDF files.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 22/06/2015
#       RDF header should include RDF path.
#       Refer: IV & V Report No. ADA/LCA/IVV/FCS/57/2015 dated 09/06/2015
# Mod2: hari on 07/07/2015
#       Discrete as well as floats with only zeros after decimal point
#       will be shown as integer.
# Mod3: hari on 10/12/2015
#       Fixed a bug in printing floating point numbers for which only the
#       integer portion was printed.
# Mod4: hari on 29/01/2016
#       Fixed a bug in printing floating point numbers where for large (E > +5) 
#       and small (E < -5) floating point numbers the output is not shown using
#       exponent notation
# Mod5: hari on 13/04/2016
#       All issues with printing of non-bypassed numeric values resolved.
#
"""
Created on Jul 11, 2011

@author: root

Types of messages

1) Normal Message:
    A plain text pre-formatted with appropriate context information

2) Error Message:
    A plain text pre-formatted with appropriate context information,
    that will be displayed as an error message

2) Symbol Message:
    A message that is a tuple of the below format:
        (
            <bypass flag>,
            <frame number>,
            (read value1, read value2, read value3, read value4),
            (status code1, status code2, status code3, status code4)
            (comparison value1, comparison value2, comparison value3, comparison value4)
        )

3) Contiguous Write Message:
    A message of the following format:
        (
            <start address>,
            <end address>,
            (<status message1>, <status message2>, <status message3>, <status message4>)
        )

4) Read Message ():
    A message of the following format:
        (
            (
                <address1>,
                (read value11, read value12, read value13, read value14),
                (status code11, status code12, status code13, status code14)
            ),
            (
                <address2>,
                (read value21, read value22, read value23, read value24),
                (status code21, status code22, status code23, status code24)
            ),
            ...,
            ...
        )

cpoke - start address, end address, value
cpeek - address, value; address value; ...
ncpoke - address, value; address value; ...
ncpeek - address, value; address value; ...
"""
from cpython cimport bool

import datetime
import re

import cfg


class MessageQueue(list):
    def __init__(self):
        super(MessageQueue, self).__init__()

    def enque(self, message):
        self.insert(0, message)

    def deque(self):
        return self.pop()


cdef class Message(object):
    """
    classdocs
    """
    cdef public bool display
    cdef public bool generate_rdf
    cdef public object command
    cdef public object response
    def __init__(self, command, response, bool display=True, bool generate_rdf=False):
        """
        Constructor
        """
        self.display = display
        self.generate_rdf = generate_rdf
        self.command = command
        self.response = response

    cpdef bool can_display(self):
        return self.display

    cpdef bool can_generate_rdf(self):
        return self.generate_rdf

    cpdef str text_start(self):
        return ""

    cpdef str text_end(self):
        return ""

cdef class ProgramMessage(Message):
    cpdef str to_text(self):
        return ''

    cpdef str to_rdf(self):
        now = datetime.datetime.now()
        rdf_src = "Z> \n"
        rdf_src += "Z> Project               : %s\n" % cfg.config_file.get_value('project')
        rdf_src += "Z> System database file  : %s\n" % (
            cfg.config_file.get_value('sysdbfpath') + cfg.config_file.get_value('sysdbf'))
        rdf_src += "Z> User database file    : %s\n" % (
            cfg.config_file.get_value('usrdbfpath') + cfg.config_file.get_value('usrdbf'))
        rdf_src += "Z> System macro file     : %s\n" % (
            cfg.config_file.get_value('sysmacpath') + cfg.config_file.get_value('sysmacfile'))
        rdf_src += "Z> User macro file       : %s\n" % (
            cfg.config_file.get_value('usrmacpath') + cfg.config_file.get_value('usrmacfile'))
        # Mod1: begin
        rdf_src += "Z> Test plan file        : %s\n" % self.command
        rdf_src += "Z> Result data file      : %s\n" % self.response
        # Mod1: end
        rdf_src += "Z> Date of execution     : %s\n" % now.strftime("%d/%m/%Y")
        rdf_src += "Z> Time of execution     : %s\n" % now.strftime("%H:%M:%S")
        rdf_src += "Z> "

        return rdf_src

# Completed
cdef class SymbolMessage(Message):
    """
        Reponse format:
                (
                    (
                        <bypass flag 1>, 
                        <frame number 1>, 
                        (<read value 11>, <read value 12>, <read value 13>, <<read value 14>), 
                        (<status code 11>, <status code 12>, <status code 13>, <status code 14>), 
                        (<compare value 11>, <compare value 12>, <compare value 13>, <compare value 14>)
                    ), 
                    (
                        <bypass flag 2>, 
                        <frame number 2>, 
                        (<read value 21>, <read value 22>, <read value 23>, <<read value 24>), 
                        (<status code 21>, <status code 22>, <status code 23>, <status code 24>), 
                        (<compare value 21>, <compare value 22>, <compare value 23>, <compare value 24>)
                    ), 
                    ...,
                    ...
                )
        Used for symbol statements (compare value is optional)
    """
    def __init__(self, command, response, bool display=True, bool generate_rdf=False):
        """
        Constructor
        """
        super(SymbolMessage, self).__init__(command, response, display, generate_rdf)

    # Mod5: begin
    cdef inline formatter(self, value):
        str_value = '%s' % value
        reg_exp = re.compile(r"\A[+-]?([0-9]+)\.([0-9]+)\Z")
        search = reg_exp.search(str_value)
        if search:  # if value is of format x.y
            groups = search.groups()
            formatted_value = "%.3f" % value
            return formatted_value.rstrip('0')
        else:
            return str_value
    # Mod5: end

    cdef inline get_bypass_formatted_value(self, bypass, value):
        if bypass:
            try:
                return '0x%x' % value
            except TypeError:  # for "unused"
                return value
        else:
            # Mod5: begin
            return self.formatter(value)
            # Mod5: end

    cpdef str build_text_line(self, c, r):
        color = [cfg.BRIGHT_GREEN for channel in xrange(4)]
        color = [(cfg.BRIGHT_PINK if (r['status'][channel] & 0xff00) else color[channel]) for channel in xrange(4)]
        color = [(cfg.BRIGHT_RED if (not r['compare'][channel]) or (r['status'][channel] & 0xff) else color[channel])
                 for channel in xrange(4)]
        value = [('offline' if (r['status'][channel] & 0xff) else self.get_bypass_formatted_value(r['bypass'],
                                                                                                  r['value'][channel]))
                 for channel in xrange(4)]
        color = [cfg.BRIGHT_WHITE if value[i] == 'unused' else color[i] for i in xrange(4)]

        return '%-30s\n<%11d> (%s%11s%s, %s%11s%s, ' \
               '%s%11s%s, %s%11s%s) %s%s%s' % (
                   c.split('\n')[-1], r['frame'],
                   color[0], value[0], cfg.COLOR_END,
                   color[1], value[1], cfg.COLOR_END,
                   color[2], value[2], cfg.COLOR_END,
                   color[3], value[3], cfg.COLOR_END,
                   cfg.BRIGHT_YELLOW, r['unit'], cfg.COLOR_END)

    def build_rdf_line(self, c, r):
        # 26/11/2014: Warning for out of range from symbol declaration max and min
        #             values not required for AETS MK1
        #             Decided by: GSV and SSS
        response_code = ''
        if any([(r['status'][channel] & 0xff) for channel in xrange(4)]):
            response_code = '%sD*' % response_code
        else:
            response_code = ('%sD*' % response_code) if not all(filter(lambda a: a != 'unused', r['compare'])) else (
                '%sR' % response_code)

        value = [('offline' if (r['status'][channel] & 0xff) else self.get_bypass_formatted_value(r['bypass'],
                                                                                                  r['value'][channel]))
                 for channel in xrange(4)]

        # 28/01/2015: hari
        # RFA without a number dated 27/01/2015
        # "1.a. Format/Information to be made same as ETS system for better readability for
        # EX: Signal names are written twice with "written" every channel. Each line is
        # written with R and C etc."
        # DO NOT DELETE BEGIN
        #return 'C> %-30s\n%s> (%11s, %11s, %11s, %11s) %s' % (
        #        c.split('\n')[-1], response_code, value[0],
        #        value[1], value[2], value[3], r['unit'])
        # DO NOT DELETE END
        is_write = any([True if v == "written" else False for v in value])
        if is_write:
            # No output in RDF for writes
            return ''
        else:
            # 28/01/2015: hari
            # RFA without a number dated 27/01/2015
            # "1.b. Printing of * to be done for every failed channel with line D"
            star = ["*" if (r['compare'][channel] != "unused") and (
                (not r['compare'][channel]) or (r['status'][channel] & 0xff)) else "" for channel in xrange(4)]
            return 'S> %-30s\n%s> (%s%11s, %s%11s, %s%11s, %s%11s) %s' % (
                c.split('\n')[-1], response_code, star[0], value[0],
                star[1], value[1], star[2], value[2], star[3], value[3], r['unit'])

    cpdef str to_text(self):
        text_src = map(self.build_text_line, self.command, self.response)
        return '\n'.join(text_src)

    cpdef str to_rdf(self):
        rdf_src = map(self.build_rdf_line, self.command, self.response)
        rdf_src = filter(None, rdf_src)  # To remove empty ('') lines
        return '\n'.join(rdf_src)

# Completed
cdef class TipSingleMessage(Message):
    """
        Response format:
            (
                <start address>, 
                <end address>, 
                (<status message 1>, <status message 2>, <status message 3>, <status message 4>), 
                (<status code 1>, <status code 2>, <status code 3>, <status code 4>)
            )
        Used for contiguous poke type tip commands
    """
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(TipSingleMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str build_text_line(self, r):
        color = [(cfg.BRIGHT_RED if r['status'][channel] else cfg.BRIGHT_GREEN) for channel in xrange(4)]
        value = [('offline' if r['status'][channel] else r['value'][channel]) for channel in xrange(4)]
        color = [cfg.BRIGHT_WHITE if value[i] == 'unused' else color[i] for i in xrange(4)]

        return '<%11s - %11s> (%s%11s%s, %s%11s%s, %s%11s%s, %s%11s%s)' % (
            ('0x%x' % r['start_address']), ('0x%x' % r['end_address']),
            color[0], value[0], cfg.COLOR_END, color[1], value[1], cfg.COLOR_END,
            color[2], value[2], cfg.COLOR_END, color[3], value[3], cfg.COLOR_END)

    cpdef str build_rdf_line(self, r):
        # 28/01/2015: hari
        # RFA without a number dated 27/01/2015
        # "1.a. Format/Information to be made same as ETS system for better readability for
        # EX: Signal names are written twice with "written" every channel. Each line is
        # written with R and C etc."
        # DO NOT DELETE BEGIN
        #response_code = 'D*' if any(r['status']) else 'R'
        # DO NOT DELETE END
        response_code = 'D*' if any(r['status']) else 'D'
        value = [('offline' if r['status'][channel] else r['value'][channel]) for channel in xrange(4)]

        # 28/01/2015: hari
        # RFA without a number dated 27/01/2015
        # "1.a. Format/Information to be made same as ETS system for better readability for
        # EX: Signal names are written twice with "written" every channel. Each line is
        # written with R and C etc."
        # DO NOT DELETE BEGIN
        #return '%s> <%11s - %11s> (%11s, %11s, %11s, %11s)' % (
        #        response_code, ('0x%x' % r['start_address']), ('0x%x' % r['end_address']), value[0], value[1],
        #        value[2], value[3])
        # DO NOT DELETE END
        is_write = any([True if v == "written" else False for v in value])
        if is_write:
            return ""
        else:
            return '%s> <%11s - %11s> (%11s, %11s, %11s, %11s)' % (
                response_code, ('0x%x' % r['start_address']), ('0x%x' % r['end_address']), value[0], value[1],
                value[2], value[3])

    cpdef str to_text(self):
        text_src = map(self.build_text_line, self.response)
        return '%-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(text_src))

    cpdef str to_rdf(self):
        # filter to remove '' which will be returned by build_rdf_line() for writes (see above)
        rdf_src = filter(None, map(self.build_rdf_line, self.response))
        return 'S> %-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(rdf_src))

cdef class TipSingleWriteMessage(TipSingleMessage):
    cpdef str to_rdf(self):
        return ''

# Completed
cdef class TipMultipleMessage(Message):
    """
        Response format:
            (
                (
                    <address 1>, 
                    (<read value 11>, <read value 12>, <read value 13>, <read value 14>), 
                    (<status code 11>, <status code 12>, <status code 13>, <status code 14>)
                ), 
                (
                    <address 2>, 
                    (<read value 21>, <read value 22>, <read value 23>, <read value 24>), 
                    (<status code 21>, <status code 22>, <status code 23>, <status code 24>)
                ), 
                ...,
                ...
            )
        Used for non-contiguous poke, contiguous peek, and non-contiguous peek type tip commands
    """
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(TipMultipleMessage, self).__init__(command, response, display, generate_rdf)

    # For handling unused during masking
    cpdef str get_formatted_value(self, value):
        try:
            return '0x%x' % value
        except TypeError:
            return value

    cpdef str build_text_line(self, r):
        try:
            color = [cfg.BRIGHT_GREEN for channel in xrange(4)]
            color = [(cfg.BRIGHT_RED if (not r['compare'][channel]) or (r['status'][channel]) else color[channel]) for
                     channel in xrange(4)]
        except KeyError:
            color = [(cfg.BRIGHT_RED if r['status'][channel] else cfg.BRIGHT_GREEN) for channel in xrange(4)]  # org

        value = [('offline' if r['status'][channel] else self.get_formatted_value(r['value'][channel])) for channel in
                 xrange(4)]
        color = [cfg.BRIGHT_WHITE if value[i] == 'unused' else color[i] for i in xrange(4)]

        return '<%11s> (%s%11s%s, %s%11s%s, %s%11s%s, %s%11s%s)' % (
            ('0x%x' % r['address']),
            color[0], value[0], cfg.COLOR_END,
            color[1], value[1], cfg.COLOR_END,
            color[2], value[2], cfg.COLOR_END,
            color[3], value[3], cfg.COLOR_END)

    cpdef str build_rdf_line(self, r):
        # RFA without a number dated 27/01/2015
        # "1.a. Format/Information to be made same as ETS system for better readability for
        # EX: Signal names are written twice with "written" every channel. Each line is
        # written with R and C etc."
        # DO NOT DELETE BEGIN
        #try:
        #    response_code = 'D*' if any(r['status']) or (not all(r['compare'])) else 'R' # org
        #except KeyError:
        #    response_code = 'D*' if any(r['status']) else 'R' # org
        # DO NOT DELETE END
        try:
            response_code = 'D*' if any(r['status']) or (not all(r['compare'])) else 'D'  # org
        except KeyError:
            response_code = 'D*' if any(r['status']) else 'D'  # org

        value = [('offline' if r['status'][channel] else self.get_formatted_value(r['value'][channel])) for channel in
                 xrange(4)]

        # 28/01/2015: hari
        # RFA without a number dated 27/01/2015
        # "1.a. Format/Information to be made same as ETS system for better readability for
        # EX: Signal names are written twice with "written" every channel. Each line is
        # written with R and C etc."
        # DO NOT DELETE BEGIN
        #return '%s> <%11s> (%11s, %11s, %11s, %11s)' % (response_code, ('0x%x' % r['address']),
        #        value[0], value[1], value[2], value[3])
        # DO NOT DELETE END
        is_write = any([True if v == "written" else False for v in value])
        if is_write:
            return ""
        else:
            return '%s> <%11s> (%11s, %11s, %11s, %11s)' % (response_code, ('0x%x' % r['address']),
                                                            value[0], value[1], value[2], value[3])

    cpdef str to_text(self):
        text_src = map(self.build_text_line, self.response)
        return '%-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(text_src))

    cpdef str to_rdf(self):
        rdf_src = map(self.build_rdf_line, self.response)
        return 'S> %-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(rdf_src))

cdef class TipMultipleWriteMessage(TipMultipleMessage):
    cpdef str to_rdf(self):
        return ''

cdef class TipMultipleFloatMessage(TipMultipleMessage):
    cpdef str get_formatted_value(self, value):
        return str(value)

cdef class TipMultipleFloatWriteMessage(TipMultipleFloatMessage):
    cpdef str to_rdf(self):
        return ''

cdef class DownloadMessage(Message):
    """
        Response format:
            (
                (
                    <start address 11>, 
                    <end address 12>, 
                    (<status message 11>, <status message 12>, <status message 13>, <status message 14>), 
                    (<status code 11>, <status code 12>, <status code 13>, <status code 14>)
                ), 
                (
                    <start address 21>, 
                    <end address 22>, 
                    (<status message 21>, <status message 22>, <status message 23>, <status message 24>), 
                    (<status code 21>, <status code 22>, <status code 23>, <status code 24>)
                ), 
                ...,
                ...
            )
        Used for download and upload commands
    """
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(DownloadMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str build_text_line(self, r):
        color = [(cfg.BRIGHT_RED if r['status'][channel] else cfg.BRIGHT_GREEN) for channel in xrange(4)]
        value = [('offline' if r['status'][channel] else r['value'][channel]) for channel in xrange(4)]
        color = [cfg.BRIGHT_WHITE if value[i] == 'unused' else color[i] for i in xrange(4)]

        return '<%11s - %11s> (%s%11s%s, %s%11s%s, %s%11s%s, %s%11s%s)' % (
            ('0x%x' % r['start_address']), ('0x%x' % r['end_address']),
            color[0], value[0], cfg.COLOR_END, color[1], value[1], cfg.COLOR_END,
            color[2], value[2], cfg.COLOR_END, color[3], value[3], cfg.COLOR_END)

    cpdef str build_rdf_line(self, r):
        value = [('offline' if r['status'][channel] else r['value'][channel]) for channel in xrange(4)]

        return 'D> <%11s - %11s> (%11s, %11s, %11s, %11s)' % (
            ('0x%x' % r['start_address']), ('0x%x' % r['end_address']), value[0], value[1],
            value[2], value[3])

    cpdef str to_text(self):
        text_src = map(self.build_text_line, self.response)
        return '%-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(text_src))

    cpdef str to_rdf(self):
        rdf_src = map(self.build_rdf_line, self.response)
        return 'S> %s\n%s' % (self.command.split('\n')[-1], '\n'.join(rdf_src))

cdef class UploadMessage(DownloadMessage):
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(UploadMessage, self).__init__(command, response, display, generate_rdf)

cdef class VerifyMessage(Message):
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(VerifyMessage, self).__init__(command, response, display, generate_rdf)

    # For handling unused during masking
    cpdef str get_formatted_value(self, value):
        if value == "unused":
            return value
        else:
            differences = len(value['differences'])
            if differences == 0:
                return 'passed'
            else:
                return '%d diff(s)' % len(value['differences'])

    cpdef str build_text_line(self):
        color = [
            (cfg.BRIGHT_RED if (r != "unused") and ((len(r['differences']) > 0) or r['status']) else cfg.BRIGHT_GREEN)
            for r in self.response['channels']]
        value = [('offline' if (r != "unused") and r['status'] else self.get_formatted_value(r)) for r in
                 self.response['channels']]
        color = [cfg.BRIGHT_WHITE if value[i] == 'unused' else color[i] for i in xrange(4)]

        return '<%11s - %11s> (%s%11s%s, %s%11s%s, %s%11s%s, %s%11s%s)' % (
            ('0x%x' % self.response['start_address']), ('0x%x' % self.response['end_address']),
            color[0], value[0], cfg.COLOR_END, color[1], value[1], cfg.COLOR_END,
            color[2], value[2], cfg.COLOR_END, color[3], value[3], cfg.COLOR_END)

    def build_rdf_line(self):
        filtered_response = filter(lambda a: a != 'unused',
                                   self.response['channels'])  # ({'status': 0L, 'differences': {}},)
        status = [r['status'] for r in filtered_response]
        diffs = [len(r['differences']) for r in filtered_response]
        star_char = '*' if any(diffs) or any(status) else ''
        value = [('offline' if (r != "unused") and r['status'] else self.get_formatted_value(r)) for r in
                 self.response['channels']]

        return 'D%s> <%11s - %11s> (%11s, %11s, %11s, %11s)' % (
            star_char, ('0x%x' % self.response['start_address']), ('0x%x' % self.response['end_address']), value[0],
            value[1], value[2], value[3])

    cpdef str to_text(self):
        text_src = self.build_text_line()
        return '%-30s\n%s' % (self.command.split('\n')[-1], text_src)

    cpdef str to_rdf(self):
        rdf_src = self.build_rdf_line()
        return 'S> %s\n%s' % (self.command.split('\n')[-1], rdf_src)

# Completed
cdef class SimpleMessage(Message):
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(SimpleMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str to_text(self):
        return '%s%s%s' % (self.text_start(), self.response, self.text_end())

    cpdef str to_rdf(self):
        return 'S> %s\nR> %s' % (self.command.split('\n')[-1], self.response)

# Completed
cdef class WarningMessage(SimpleMessage):
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(WarningMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str text_start(self):
        return cfg.NORMAL_YELLOW

    cpdef str text_end(self):
        return cfg.COLOR_END

# Completed
cdef class ErrorMessage(SimpleMessage):
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(ErrorMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str text_start(self):
        return cfg.BRIGHT_RED

    cpdef str text_end(self):
        return cfg.COLOR_END

    cpdef str to_text(self):
        return '%s%s%s' % (self.text_start(), self.response, self.text_end())

    cpdef str to_rdf(self):
        return 'S> %s\nD*> %s' % (self.command.split('\n')[-1], self.response)

# Completed
cdef class NormalMessage(SimpleMessage):
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(NormalMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str text_start(self):
        return ''

    cpdef str text_end(self):
        return ''

cdef class ListingMessage(SimpleMessage):
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(ListingMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str text_start(self):
        return ''

    cpdef str text_end(self):
        return ''

    cpdef str to_rdf(self):
        temp = str(self.command).strip()
        if (len(temp) == 0) or temp.startswith('!'):
            # For handling block comments enclosed in '!#' and '#!'
            self.command = self.command.replace('\n', '\nB> ')
            return 'B> %s' % self.command
        else:
            return 'S> %s' % self.command

# Completed
cdef class CommentMessage(SimpleMessage):
    def __init__(self, command, response, display=False, generate_rdf=False):
        """
        Constructor
        """
        super(CommentMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str text_start(self):
        return ''

    cpdef str text_end(self):
        return ''

    cpdef str to_rdf(self):
        return '%s' % self.response

# Completed
cdef class TipStatusMessage(Message):
    """
        Response format:
            (
                <start address>, 
                <end address>, 
                (<status message 1>, <status message 2>, <status message 3>, <status message 4>), 
                (<status code 1>, <status code 2>, <status code 3>, <status code 4>)
            )
        Used for contiguous poke type tip commands
    """
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(TipStatusMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str build_text_line(self, r):
        color = [(cfg.BRIGHT_RED if r['status'][channel] else cfg.BRIGHT_GREEN) for channel in xrange(4)]
        value = [(('offline' if r['status'][channel] else 'online') if r['value'][channel] != 'unused' else 'unused')
                 for channel in xrange(4)]

        # for white 'unused'
        color = [cfg.BRIGHT_WHITE if value[i] == 'unused' else color[i] for i in xrange(4)]
        return '<%11s> (%s%11s%s, %s%11s%s, %s%11s%s, %s%11s%s)' % (('0x%x' % r['address']),
                                                                    color[0], value[0], cfg.COLOR_END, color[1],
                                                                    value[1], cfg.COLOR_END,
                                                                    color[2], value[2], cfg.COLOR_END, color[3],
                                                                    value[3], cfg.COLOR_END)

    cpdef str build_rdf_line(self, r):
        response_code = 'D*' if any(r['status']) else 'D'
        value = [('offline' if r['status'][channel] else 'online') for channel in xrange(4)]

        return '%s> <%11s> (%11s, %11s, %11s, %11s)' % (
            response_code, ('0x%x' % r['address']), value[0], value[1],
            value[2], value[3])

    cpdef str to_text(self):
        text_src = map(self.build_text_line, self.response)
        return '%-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(text_src))

    cpdef str to_rdf(self):
        rdf_src = map(self.build_rdf_line, self.response)

        return 'S> %-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(rdf_src))

# Completed
cdef class TipBitMarchMessage(Message):
    """
        Response format:
            (
                <start address>,
                <end address>,
                (<status message 1>, <status message 2>, <status message 3>, <status message 4>),
                (<status code 1>, <status code 2>, <status code 3>, <status code 4>)
            )
        Used for contiguous poke type tip commands
    """
    def __init__(self, command, response, display=True, generate_rdf=False):
        """
        Constructor
        """
        super(TipBitMarchMessage, self).__init__(command, response, display, generate_rdf)

    cpdef str build_text_line(self, r):
        color = [(cfg.BRIGHT_RED if (r['status'][channel] or r['value'][channel]) else cfg.BRIGHT_GREEN) for channel in
                 xrange(4)]
        value = [('offline' if r['status'][channel] else (
            r['value'][channel] if r['value'][channel] == "unused" else (
                'failed' if r['value'][channel] else 'passed')))
                 for channel in xrange(4)]
        color = [cfg.BRIGHT_WHITE if value[i] == 'unused' else color[i] for i in xrange(4)]

        return '<%11s - %11s> (%s%11s%s, %s%11s%s, %s%11s%s, %s%11s%s)' % (
            ('0x%x' % r['start_address']), ('0x%x' % r['end_address']),
            color[0], value[0], cfg.COLOR_END, color[1], value[1], cfg.COLOR_END,
            color[2], value[2], cfg.COLOR_END, color[3], value[3], cfg.COLOR_END)

    cpdef str build_rdf_line(self, r):
        response_code = 'D*' if (any(r['status']) or any(r['value'])) else 'D'
        value = [('offline' if r['status'][channel] else (
            r['value'][channel] if r['value'][channel] == "unused" else (
                'failed' if r['value'][channel] else 'passed')))
                 for channel in xrange(4)]

        is_write = any([True if v == "written" else False for v in value])
        if is_write:
            return ""
        else:
            return '%s> <%11s - %11s> (%11s, %11s, %11s, %11s)' % (
                response_code, ('0x%x' % r['start_address']), ('0x%x' % r['end_address']), value[0], value[1],
                value[2], value[3])

    cpdef str to_text(self):
        text_src = map(self.build_text_line, self.response)
        return '%-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(text_src))

    cpdef str to_rdf(self):
        # filter to remove '' which will be returned by build_rdf_line() for writes (see above)
        rdf_src = filter(None, map(self.build_rdf_line, self.response))
        return 'S> %-30s\n%s' % (self.command.split('\n')[-1], '\n'.join(rdf_src))
