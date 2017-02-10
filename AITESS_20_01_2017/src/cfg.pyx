# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : cfg
# File name		        : cfg.pyx
# Usage			        : The configuration file containing global variables.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 24/06/2015
#       Don't display the real version number and date, those are for internal reference.
#       Display fake version number instead.
#       Refer: IV & V Report No. ADA/LCA/IVV/FCS/57/2015 dated 09/06/2015
# Mod2: hari on 10/12/2015
#       AITESS should pickup config.dat from the working directory and should
#       use this as the active directory instead of /opt/aitess

"""The cfg module.

This is the global module for the AITESS.
"""

import os
import sys

from datatable import SymbolTable
from progressbar import ProgressBar
from sourceinfo import SourceStack

try:
    import shm
except ImportError:
    print '*********************************************************************'
    print '*** WARNING: shm module not found, using dummy shm module instead ***'
    print '*********************************************************************'
    import shm_dummy as shm

cdef extern from "":
    cdef char *GIT_VERSION
    cdef char *GIT_VERSION_LONG
    cdef char *__TIME__
    cdef char *__DATE__

# Set AITESS build version from Git.
aitess_version = GIT_VERSION
# Mod1: begin
fake_aitess_version = 'V1.0 R1'
# Mod1: end
aitess_version_long = GIT_VERSION_LONG
# Add the build time stamp too.
aitess_build_timestamp = "%s, %s" % (__DATE__, __TIME__)

# The symbol table an instance of class SymbolTable.
symbol_table = SymbolTable()

# For the animated progress bar.
progress_bar = ProgressBar()

# A stack for storing the active script file names and line numbers.
source_stack = SourceStack()

# Global state variables.
logging_state = True
display_state = True
generate_rdf = False

# Various AITESS input files.
# Mod2: begin
configuration_filename = '%s/config.dat' % os.getcwd()
if os.access(configuration_filename, os.R_OK):  # if config.dat is readable
    cached_configuration_filename = '%s/config.cache' % os.getcwd()
    logging_filename = '%s/aitess.log' % os.getcwd()
    man_mode_rdf_filename = '%s/manu.rdf' % os.getcwd()
    history_path = '%s/.aitesshistory' % os.getcwd()
else:
    configuration_filename = os.path.expanduser('~/aitess/config.dat')
    cached_configuration_filename = os.path.expanduser('~/aitess/config.cache')
    logging_filename = os.path.expanduser('~/aitess/aitess.log')
    man_mode_rdf_filename = os.path.expanduser('~/aitess/manu.rdf')
    history_path = os.path.expanduser("~/aitess/.aitesshistory")
    try:
        # make ~/aitess the working directory
        os.chdir(os.path.expanduser('~/aitess/'))
    except:
        pass

sys_startup_filename = 'startup.sys'
# Mod2: end
usr_startup_filename = 'startup.usr'

# The configuration object for handling 'config.dat' will store an instance of class ConfigFile.
config_file = None
rdf_filename = ''
tpf_filename = ''

# The queue where the output used for display and RDF generation is stored.
output_queue = []

# The global channelization for AITESS.
global_mask = 0b1111

# Should AITESS have compatibility with LTM may break certain new features
legacy_syntax = False

# Mode flags
is_auto_mode = False
is_man_mode = False
is_high_priority = False

# Colour constants
#GREEN = '\033[32m'
#GREEN1 = '\033[92m'LIGHT
#YELLOW = '\033[33m'
#YELLOW1 = '\033[93m'BRIGHT

# for pure terminals
NORMAL_GREEN = '\033[32m'
NORMAL_WHITE = '\033[37m'
NORMAL_PINK = '\033[35m'
NORMAL_RED = '\033[31m'
NORMAL_YELLOW = '\033[33m'

# for terminals inside GUI
BRIGHT_GREEN = '\033[92m'
BRIGHT_WHITE = '\033[97m'
BRIGHT_PINK = '\033[95m'
BRIGHT_RED = '\033[91m'
BRIGHT_YELLOW = '\033[93m'

GREEN = NORMAL_GREEN + BRIGHT_GREEN
WHITE = NORMAL_WHITE + BRIGHT_WHITE
PINK = NORMAL_PINK + BRIGHT_PINK
RED = NORMAL_RED + BRIGHT_RED
YELLOW = NORMAL_YELLOW + BRIGHT_YELLOW

BOLD = '\033[1m'
UNDERLINE = '\033[4m'

COLOR_END = '\033[0m'

def get_sysstartfile_path():
    return '%s/%s' % ('/'.join(sys.path[0].split("/")[:-1]), sys_startup_filename)

def get_usrstartfile_path():
    return '%s/%s' % (os.getcwd(), usr_startup_filename)

def get_logfile_path():
    if logging_filename[0] != '/':
        return '%s/%s' % ('/'.join(sys.path[0].split("/")[:-1]), logging_filename)
    else:
        return logging_filename
