# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : tokens
# File name		        : tokens.py
# Usage			        : Definitions of tokens in AITESS.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#


class TokenType(object):
    """Token definition class.
    
    The tokens are defined as three digit numbers between 100 and 999.
    """
    # The symbols.
    TYP_UNKNOWN = 100
    TYP_SYMBOL = 101
    TYP_VARIABLE = 102
    TYP_MACRO = 103
    TYP_SYSFUNC = 104
    TYP_FUNC = 105

    # The operators.
    OPR_AMPERSAND = 201
    OPR_EQUAL = 202
    OPR_MINUS = 203
    OPR_PLUS = 204
    OPR_QUESTION = 205
    OPR_DQUOTE = 206
    OPR_EQUALTO = 207
    OPR_NOTEQUALTO = 208
    OPR_LESSER = 209
    OPR_GREATER = 210
    OPR_LEQUALTO = 211
    OPR_GEQUALTO = 212
    OPR_NEWLINE = 213
    OPR_LBRACKET = 214
    OPR_RBRACKET = 215
    OPR_COMMA = 216
    OPR_MULTIPLY = 217
    OPR_DIVIDE = 218
    OPR_LSQBRACKET = 219
    OPR_RSQBRACKET = 220
    OPR_SHARP = 221
    OPR_BEQUAL = 222
    OPR_BNOTEQUALTO = 223
    OPR_BLESSER = 224
    OPR_BGREATER = 225
    OPR_BLEQUALTO = 226
    OPR_BGEQUALTO = 227
    OPR_INCLUSION = 228
    OPR_PARAMS = 229
    OPR_MODULO = 230
    OPR_ASSIGN = 231
    OPR_LSHIFT = 232
    OPR_RSHIFT = 233

    # The keywords.
    KEY_IF = 300
    KEY_THEN = 301
    KEY_BREAK = 302
    KEY_LOGGING = 303
    KEY_DISPLAY = 304
    KEY_ON = 305
    KEY_OFF = 306
    KEY_SYM = 307
    KEY_ENDSYM = 308
    KEY_NOT = 309
    KEY_AND = 310
    KEY_OR = 311
    KEY_NOTB = 312
    KEY_ANDB = 313
    KEY_ORB = 314
    KEY_XORB = 315
    KEY_TRUE = 316
    KEY_FALSE = 317
    KEY_ENDIF = 318
    KEY_WHILE = 319
    KEY_ENDWHILE = 320
    KEY_DO = 321
    KEY_ELIF = 322
    KEY_CONTINUE = 323
    KEY_PRINT = 324
    KEY_TIP = 325
    KEY_ELSE = 326
    KEY_WAIT = 327
    KEY_DOWNLOAD = 328
    KEY_DCHAN = 329
    KEY_LIST = 330
    KEY_OPMSG = 331
    KEY_EXIT = 332
    KEY_ASSERT = 333
    KEY_OPWAIT = 334
    KEY_DELETE = 335
    KEY_MACDECL = 336
    KEY_ENDMACDECL = 337
    KEY_MACINVOC = 338
    KEY_HELP = 339
    KEY_UPLOAD = 340
    KEY_VERIFY = 341
    KEY_FUNCDECL = 342
    KEY_ENDFUNCDECL = 343
    KEY_RETURN = 344
    KEY_PASS = 345
    KEY_DIFFS = 346
    KEY_INFO = 347
    KEY_FRWAIT = 348
    KEY_LOCATE = 349
    KEY_PATCH = 350
    KEY_TPGPH = 351
    KEY_STEP = 352
    KEY_MACINVOC_ALT = 353
    KEY_AUTO = 354
    KEY_MAN = 355
    KEY_LTM_SYNTAX = 356
    KEY_EXPAND = 357
    KEY_WFC = 358

    # The reserved words
    RES_BO = 400
    RES_PR = 401
    RES_MRHP = 402
    RES_MRFP = 403
    RES_DB = 404
    RES_DW = 405
    RES_DD = 406
    RES_MRHRP = 407
    RES_MRFRP = 408
    RES_FB = 409
    RES_FW = 410
    RES_FD = 411
    RES_LB = 412
    RES_LW = 413
    RES_LD = 414
    RES_CS = 415
    RES_EPR = 416
    RES_ERS = 417
    RES_HA = 418
    RES_RE = 419
    RES_WDM = 420
    RES_N = 421
    RES_T = 422
    RES_ENB = 423
    RES_DSB = 424
    RES_DMAS = 424
    RES_DMAR = 426
    RES_CH = 427
    RES_DF = 428
    RES_FFC = 429
    RES_FFI = 430
    RES_MTD = 431
    RES_MTW = 432
    RES_MTB = 433
    RES_VR = 434
    RES_P = 435
    RES_LRU = 436
    RES_PL = 437
    RES_MAXWAIT = 438

    # The literals.
    LIT_INT = 500
    LIT_FLOAT = 501
    LIT_BIN = 502
    LIT_HEX = 503
    LIT_OCT = 504
    LIT_NUMBER = 505
    LIT_STRING = 506

    # Special tokens.
    SPL_COMMENT = 900
    SPL_ERROR = 950
    SPL_EOF = 999


TokenName = {  # The symbols.
    TokenType.TYP_UNKNOWN: 'untyped',
    TokenType.TYP_SYMBOL: 'symbol',
    TokenType.TYP_VARIABLE: 'variable',
    TokenType.TYP_MACRO: 'macro',
    TokenType.TYP_SYSFUNC: 'system function',
    TokenType.TYP_FUNC: 'function',

    # The operators.
    TokenType.OPR_AMPERSAND: '&',
    TokenType.OPR_EQUAL: '=',
    TokenType.OPR_MINUS: '-',
    TokenType.OPR_PLUS: '+',
    TokenType.OPR_QUESTION: '?',
    TokenType.OPR_DQUOTE: '"',
    TokenType.OPR_EQUALTO: '==',
    TokenType.OPR_NOTEQUALTO: '<>',
    TokenType.OPR_LESSER: '<',
    TokenType.OPR_GREATER: '>',
    TokenType.OPR_LEQUALTO: '<=',
    TokenType.OPR_GEQUALTO: '>=',
    TokenType.OPR_NEWLINE: '«newline»',
    TokenType.OPR_LBRACKET: '(',
    TokenType.OPR_RBRACKET: ')',
    TokenType.OPR_COMMA: ',',
    TokenType.OPR_MULTIPLY: '*',
    TokenType.OPR_DIVIDE: '/',
    TokenType.OPR_LSQBRACKET: '[',
    TokenType.OPR_RSQBRACKET: ']',
    TokenType.OPR_SHARP: '#',
    TokenType.OPR_BEQUAL: '="',
    TokenType.OPR_BNOTEQUALTO: '<>"',
    TokenType.OPR_BLESSER: '<"',
    TokenType.OPR_BGREATER: '>"',
    TokenType.OPR_BLEQUALTO: '<="',
    TokenType.OPR_BGEQUALTO: '>="',
    TokenType.OPR_INCLUSION: '@',
    TokenType.OPR_PARAMS: '$',
    TokenType.OPR_MODULO: '%',
    TokenType.OPR_ASSIGN: ':=',
    TokenType.OPR_LSHIFT: '<<',
    TokenType.OPR_RSHIFT: '>>',

    # The keywords.
    TokenType.KEY_IF: 'if',
    TokenType.KEY_THEN: 'then',
    TokenType.KEY_BREAK: 'break',
    TokenType.KEY_CONTINUE: 'continue',
    TokenType.KEY_LOGGING: 'logging',
    TokenType.KEY_DISPLAY: 'display',
    TokenType.KEY_ON: 'on',
    TokenType.KEY_OFF: 'off',
    TokenType.KEY_SYM: 'symb',
    TokenType.KEY_ENDSYM: 'ends',
    TokenType.KEY_NOT: 'not',
    TokenType.KEY_AND: 'and',
    TokenType.KEY_OR: 'or',
    TokenType.KEY_NOTB: 'notb',
    TokenType.KEY_ANDB: 'andb',
    TokenType.KEY_ORB: 'orb',
    TokenType.KEY_XORB: 'xorb',
    TokenType.KEY_TRUE: 'true',
    TokenType.KEY_FALSE: 'false',
    TokenType.KEY_ENDIF: 'fi',
    TokenType.KEY_WHILE: 'while',
    TokenType.KEY_ENDWHILE: 'od',
    TokenType.KEY_DO: 'do',
    TokenType.KEY_ELIF: 'elif',
    TokenType.KEY_PRINT: 'print',
    TokenType.KEY_TIP: 'tip',
    TokenType.KEY_ELSE: 'else',
    TokenType.KEY_WAIT: 'wait',
    TokenType.KEY_DOWNLOAD: 'download',
    TokenType.KEY_DCHAN: 'dchan',
    TokenType.KEY_LIST: 'list',
    TokenType.KEY_OPMSG: 'opmsg',
    TokenType.KEY_EXIT: 'exit',
    TokenType.KEY_ASSERT: 'assert',
    TokenType.KEY_OPWAIT: 'opwait',
    TokenType.KEY_DELETE: 'delete',
    TokenType.KEY_MACDECL: 'macroname',
    TokenType.KEY_ENDMACDECL: 'endm',
    TokenType.KEY_MACINVOC: 'macname',
    TokenType.KEY_HELP: 'help',
    TokenType.KEY_UPLOAD: 'upload',
    TokenType.KEY_VERIFY: 'verify',
    TokenType.KEY_FUNCDECL: 'function',
    TokenType.KEY_ENDFUNCDECL: 'endf',
    TokenType.KEY_RETURN: 'return',
    TokenType.KEY_PASS: 'pass',
    TokenType.KEY_DIFFS: 'diffs',
    TokenType.KEY_INFO: 'info',
    TokenType.KEY_FRWAIT: 'frwait',
    TokenType.KEY_LOCATE: 'locate',
    TokenType.KEY_PATCH: 'patch',
    TokenType.KEY_TPGPH: 'tpgph',
    TokenType.KEY_STEP: 'step',
    TokenType.KEY_MACINVOC_ALT: 'macn',
    TokenType.KEY_AUTO: 'auto',
    TokenType.KEY_MAN: 'man',
    TokenType.KEY_LTM_SYNTAX: 'ltm_syntax',
    TokenType.KEY_EXPAND: 'expand',
    TokenType.KEY_WFC: 'wfc',

    TokenType.RES_BO: 'bo',
    TokenType.RES_PR: 'pr',
    TokenType.RES_MRHP: 'mrhp',
    TokenType.RES_MRFP: 'mrfp',
    TokenType.RES_DB: 'db',
    TokenType.RES_DW: 'dw',
    TokenType.RES_DD: 'dd',
    TokenType.RES_MRHRP: 'mrhrp',
    TokenType.RES_MRFRP: 'mrfrp',
    TokenType.RES_FB: 'fb',
    TokenType.RES_FW: 'fw',
    TokenType.RES_FD: 'fd',
    TokenType.RES_LB: 'lb',
    TokenType.RES_LW: 'lw',
    TokenType.RES_LD: 'ld',
    TokenType.RES_CS: 'cs',
    TokenType.RES_EPR: 'epr',
    TokenType.RES_ERS: 'ers',
    TokenType.RES_HA: 'ha',
    TokenType.RES_RE: 're',
    TokenType.RES_WDM: 'wdm',
    TokenType.RES_DMAS: 'dmas',
    TokenType.RES_DMAR: 'dmar',
    TokenType.RES_N: 'n',
    TokenType.RES_T: 't',
    TokenType.RES_ENB: 'enb',
    TokenType.RES_DSB: 'dsb',
    TokenType.RES_CH: 'ch',
    TokenType.RES_DF: 'df',
    TokenType.RES_FFC: 'ffc',
    TokenType.RES_FFI: 'ffi',
    TokenType.RES_MTD: 'mtd',
    TokenType.RES_MTW: 'mtw',
    TokenType.RES_MTB: 'mtb',
    TokenType.RES_VR: 'vr',
    TokenType.RES_P: 'p',
    TokenType.RES_LRU: 'lru',
    TokenType.RES_PL: 'pl',
    TokenType.RES_MAXWAIT: 'maxwait',

    # The literals.
    TokenType.LIT_INT: 'integer literal',
    TokenType.LIT_FLOAT: 'floating-point literal',
    TokenType.LIT_BIN: 'binary literal',
    TokenType.LIT_HEX: 'hexadecimal literal',
    TokenType.LIT_OCT: 'octal literal',
    TokenType.LIT_NUMBER: 'numeric literal',
    TokenType.LIT_STRING: 'string literal',

    # Special tokens.
    TokenType.SPL_COMMENT: '!',
    TokenType.SPL_ERROR: 'invalid char',
    TokenType.SPL_EOF: 'EOF'}

# Mapping of keyword lexemes to token definitions.
TokenKeyword = {'if': TokenType.KEY_IF, 'then': TokenType.KEY_THEN,
                'logging': TokenType.KEY_LOGGING, 'display': TokenType.KEY_DISPLAY,
                'on': TokenType.KEY_ON, 'off': TokenType.KEY_OFF,
                'symb': TokenType.KEY_SYM, 'or': TokenType.KEY_OR,
                'and': TokenType.KEY_AND, 'not': TokenType.KEY_NOT,
                'xorb': TokenType.KEY_XORB, 'orb': TokenType.KEY_ORB,
                'andb': TokenType.KEY_ANDB, 'notb': TokenType.KEY_NOTB,
                'true': TokenType.KEY_TRUE, 'false': TokenType.KEY_FALSE,
                'fi': TokenType.KEY_ENDIF, 'while': TokenType.KEY_WHILE,
                'do': TokenType.KEY_DO, 'od': TokenType.KEY_ENDWHILE,
                'break': TokenType.KEY_BREAK, 'elif': TokenType.KEY_ELIF,
                'continue': TokenType.KEY_CONTINUE, 'print': TokenType.KEY_PRINT,
                'tip': TokenType.KEY_TIP, 'else': TokenType.KEY_ELSE,
                'wait': TokenType.KEY_WAIT,
                'download': TokenType.KEY_DOWNLOAD, 'dchan': TokenType.KEY_DCHAN,
                'list': TokenType.KEY_LIST, 'opmsg': TokenType.KEY_OPMSG,
                'exit': TokenType.KEY_EXIT, 'assert': TokenType.KEY_ASSERT,
                'opwait': TokenType.KEY_OPWAIT, 'delete': TokenType.KEY_DELETE,
                'macroname': TokenType.KEY_MACDECL, 'endm': TokenType.KEY_ENDMACDECL,
                'macname': TokenType.KEY_MACINVOC, 'help': TokenType.KEY_HELP,
                'upload': TokenType.KEY_UPLOAD, 'ends': TokenType.KEY_ENDSYM,
                'verify': TokenType.KEY_VERIFY, 'function': TokenType.KEY_FUNCDECL,
                'endf': TokenType.KEY_ENDFUNCDECL, 'return': TokenType.KEY_RETURN,
                'pass': TokenType.KEY_PASS, 'diffs': TokenType.KEY_DIFFS,
                'info': TokenType.KEY_INFO, 'frwait': TokenType.KEY_FRWAIT,
                'locate': TokenType.KEY_LOCATE, 'patch': TokenType.KEY_PATCH,
                'tpgph': TokenType.KEY_TPGPH, 'step': TokenType.KEY_STEP,
                'macn': TokenType.KEY_MACINVOC_ALT, 'auto': TokenType.KEY_AUTO,
                'man': TokenType.KEY_MAN, 'ltm_syntax': TokenType.KEY_LTM_SYNTAX,
                'expand': TokenType.KEY_EXPAND, 'wfc': TokenType.KEY_WFC}

TokenResword = {'bo': TokenType.RES_BO, 'pr': TokenType.RES_PR,
                'mrhp': TokenType.RES_MRHP, 'mrfp': TokenType.RES_MRFP,
                'db': TokenType.RES_DB, 'dw': TokenType.RES_DW,
                'dd': TokenType.RES_DD, 'mrhrp': TokenType.RES_MRHRP,
                'mrfrp': TokenType.RES_MRFRP, 'fb': TokenType.RES_FB,
                'fw': TokenType.RES_FW, 'fd': TokenType.RES_FD,
                'lb': TokenType.RES_LB, 'lw': TokenType.RES_LW,
                'ld': TokenType.RES_LD, 'cs': TokenType.RES_CS,
                'epr': TokenType.RES_EPR, 'ers': TokenType.RES_ERS,
                'ha': TokenType.RES_HA, 're': TokenType.RES_RE,
                'wdm': TokenType.RES_WDM, 'dmas': TokenType.RES_DMAS,
                'dmar': TokenType.RES_DMAR, 'n': TokenType.RES_N,
                't': TokenType.RES_T, 'enb': TokenType.RES_ENB,
                'dsb': TokenType.RES_DSB, 'ch': TokenType.RES_CH,
                'df': TokenType.RES_DF, 'ffc': TokenType.RES_FFC,
                'ffi': TokenType.RES_FFI, 'mtd': TokenType.RES_MTD,
                'mtw': TokenType.RES_MTW, 'vr': TokenType.RES_VR,
                'p': TokenType.RES_P, 'lru': TokenType.RES_LRU,
                'pl': TokenType.RES_PL, 'mtb': TokenType.RES_MTB,
                'maxwait': TokenType.RES_MAXWAIT}


class Token(dict):
    def __init__(self, _type=None, attribute=None, text='', **kwargs):
        super(Token, self).__init__(**kwargs)
        self['type'] = _type
        self['attribute'] = attribute
        self['text'] = text
