# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : configfile
# File name		        : configfile.py
# Usage			        : For handling the "config.dat" file.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 27/03/2015
#       RDF file versioning to be made optional because AIRDATS-E
#       does not want it (requested by SED, Chandrashekhar)
# Mod2: hari on 23/06/2015
#       RDF file name can now be specified with path
# Mod3: hari on 26/06/2015
#       RHS (i.e. whatever comes after '=') of options can now be empty
# Mod4: hari on 09/02/2016
#       Incorporation of download and upload for Motorola
#       S-Record file

import os
import re


class ConfigFile(object):
    def __init__(self, cfgfile_name):
        self.cfgfile_list = []
        # Mod3: begin
        self.reg_exp1 = re.compile(
            r"\A(((\w+\s*=\s*(?:\w|/|\.|-)+)?\s*(!.*))|((\w+\s*=\s*(?:\w|/|\.|-)*)\s*(!.*)?)|(\s*))\Z")
        # Mod3: end
        self.reg_exp2 = re.compile(r"!")
        self.reg_exp3 = re.compile(r"=")
        self.reg_exp4 = re.compile(r"\A\s*!\$")

        self.cfgfile_name = cfgfile_name

        self.__generate_list()

    def __generate_list(self):
        self.cfgfile = open(self.cfgfile_name, 'r')

        line_num = 0
        line = ' '

        while line:
            line_num += 1
            line = self.cfgfile.readline()

            line1 = line.strip()

            if not self.reg_exp1.match(line1):
                raise Exception("Syntax error on line number " + str(line_num) + " in configuration file")

            self.cfgfile_list.append(line1)

        self.cfgfile.close()

    def __filter_value(self, option, value):
        if (option == "sysdbf") and (
                    (len(self.get_value("sysdbfpath")) == 0) or not os.access(self.get_value("sysdbfpath") + value,
                                                                              os.F_OK)):
            return ""
        elif (option == "sysmacfile") and (
                    (len(self.get_value("sysmacpath")) == 0) or not os.access(self.get_value("sysmacpath") + value,
                                                                              os.F_OK)):
            return ""
        elif (option == "syslibfile") and (
                    (len(self.get_value("syslibpath")) == 0) or not os.access(self.get_value("syslibpath") + value,
                                                                              os.F_OK)):
            return ""
        elif (option == "usrdbf") and (
                    (len(self.get_value("usrdbfpath")) == 0) or not os.access(self.get_value("usrdbfpath") + value,
                                                                              os.F_OK)):
            return ""
        elif (option == "usrmacfile") and (
                    (len(self.get_value("usrmacpath")) == 0) or not os.access(self.get_value("usrmacpath") + value,
                                                                              os.F_OK)):
            return ""
        elif (option == "usrlibfile") and (
                    (len(self.get_value("usrlibpath")) == 0) or not os.access(self.get_value("usrlibpath") + value,
                                                                              os.F_OK)):
            return ""
        elif (option == "sysdbfpath") and not os.access(value, os.F_OK):
            return ""
        elif (option == "sysmacpath") and not os.access(value, os.F_OK):
            return ""
        elif (option == "syslibpath") and not os.access(value, os.F_OK):
            return ""
        elif (option == "usrdbfpath") and not os.access(value, os.F_OK):
            return ""
        elif (option == "usrmacpath") and not os.access(value, os.F_OK):
            return ""
        elif (option == "usrlibpath") and not os.access(value, os.F_OK):
            return ""
        elif (option in ("tpfpath", "rdfpath", "downloadpath", "uploadpath")) and not os.access(value, os.F_OK):
            return os.path.expanduser("~") + "/"
        elif option == "usecache":
            return "true" if (value.lower() == "true") else "false"
        # Mod1: begin
        elif option == "rdfversions":
            return "true" if (value.lower() == "true") else "false"
        # Mod1: end
        else:
            return value

    def get_value(self, option, filter_=True):
        value = ""

        for line in self.cfgfile_list:
            line1 = self.reg_exp2.split(line)
            line2 = self.reg_exp3.split(line1[0])

            line2 = map(str.strip, line2)
            line2[0] = line2[0].lower()

            if line2[0] == option.lower():
                value = line2[1]
                break

        if filter_:
            if option not in ("project", "uut"):
                value = self.__filter_value(option.lower(), value)

        return value

    def is_configured_for_ADC(self):
        return self.get_value("uut") == "adc"

    def is_configured_for_LADC(self):
        # Mod4: begin
        return (self.get_value("uut") == "ladc")# or (self.get_value("uut") not in ("adc", "dfcc", "dfcc_mk2"))
        # Mod4: end

    def is_configured_for_DFCC(self):
        return (self.get_value("uut") == "dfcc") or (self.get_value("uut") == "dfcc_mk1")

    def is_configured_for_DFCC_MK1A(self):
        return self.get_value("uut") == "dfcc_mk1a"

    # Mod4: begin
    def is_configured_for_DFCC_MK2(self):
        return self.get_value("uut") == "dfcc_mk2"

    # Mod4: end

    def get_tpfpath(self, filename):
        filename = os.path.expanduser(filename)

        if filename.startswith('./'):
            return "%s/%s" % (os.getcwd(), filename[2:])

        if not filename.startswith('/'):
            return "%s%s" % (self.get_value('tpfpath'), filename)

        return filename

    def get_rdfpath(self, filename):
        # Mod2: begin
        filename = os.path.expanduser(filename)

        if filename.startswith('./'):
            return "%s/%s" % (os.getcwd(), filename[2:])

        if not filename.startswith('/'):
            return "%s%s" % (self.get_value('rdfpath'), filename)

        return filename
        # Mod2: end

    def get_downloadpath(self, filename):
        if not filename.startswith('/'):
            return "%s%s" % (self.get_value('downloadpath'), filename)

        return filename

    def get_uploadpath(self, filename):
        if not filename.startswith('/'):
            return "%s%s" % (self.get_value('uploadpath'), filename)

        return filename
