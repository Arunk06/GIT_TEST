# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : main
# File name		        : main.py
# Usage			        : Entry point for AITESS execution.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 22/06/2015
#       Don't display the real version number and date, those are for internal reference.
#       Display fake version number instead.
#       Refer: IV & V Report No. ADA/LCA/IVV/FCS/57/2015 dated 09/06/2015

"""The main module.
"""
import sys

import cfg
from aitessapp import AITESSApp

sys.setrecursionlimit(1024 * 12)
sys.setcheckinterval(4)  # (400000)

if __name__ == '__main__':
    print cfg.BOLD + \
          cfg.BRIGHT_GREEN + "+---------------------------------------------------------------+" + cfg.COLOR_END
    print cfg.BOLD + \
          cfg.BRIGHT_GREEN + "|      Advanced Integrated Test Environment System Software     |" + cfg.COLOR_END
    # Mod1: begin
    print cfg.BOLD + \
          cfg.BRIGHT_GREEN + "|                        Version %-23s        |" % cfg.fake_aitess_version + cfg.COLOR_END
    # Mod1: end
    print cfg.BOLD + \
          cfg.BRIGHT_GREEN + "|                     By FCTS Division, ADE.                    |" + cfg.COLOR_END
    print cfg.BOLD + \
          cfg.BRIGHT_GREEN + "+---------------------------------------------------------------+" + cfg.COLOR_END

    aitess = AITESSApp()
    if (len(sys.argv) > 1) and (sys.argv[1] == '-i'):
        aitess.start(batchmode=True)
    else:
        aitess.start()
    cfg.shm.close_shm()
