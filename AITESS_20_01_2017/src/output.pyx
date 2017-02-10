# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : output
# File name		        : output.pyx
# Usage			        : Handles output to terminal and various RDF files.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 23/06/2015
#       Fixed a bug where once if display is turned off then nothing is printed
#       not even outputs with deliberate display on
# Mod2: hari on 19/10/2015
#       RDF files (including manu.rdf) will be now under the ownership of the 
#       current user not under root

import datetime
import sys

import cfg
from message import ErrorMessage

# Mod2: begin
import os

# Mod2: end

man_file = None

def man_file_open():
    global man_file
    now = datetime.datetime.now()
    man_file = open(cfg.man_mode_rdf_filename, 'w')
    # Mod2: begin
    try:
        os.chown(cfg.man_mode_rdf_filename, int(os.getenv("SUDO_UID")), int(os.getenv("SUDO_GID")))
    except TypeError:  # If we are not running under "sudo", environment variables "SUDO_GID" and
        pass  # "SUDO_GID" will not be set and there is no point in changing the ownership
    # Mod2: end

    rdf_text = "Z> \n"
    rdf_text += "Z> Project               : %s\n" % cfg.config_file.get_value('project')
    rdf_text += "Z> System database file  : %s\n" % (
        cfg.config_file.get_value('sysdbfpath') + cfg.config_file.get_value('sysdbf'))
    rdf_text += "Z> User database file    : %s\n" % (
        cfg.config_file.get_value('usrdbfpath') + cfg.config_file.get_value('usrdbf'))
    rdf_text += "Z> System macro file     : %s\n" % (
        cfg.config_file.get_value('sysmacpath') + cfg.config_file.get_value('sysmacfile'))
    rdf_text += "Z> User macro file       : %s\n" % (
        cfg.config_file.get_value('usrmacpath') + cfg.config_file.get_value('usrmacfile'))
    rdf_text += "Z> Test plan file        : %s\n" % '«stdin»'
    rdf_text += "Z> Result data file      : %s\n" % cfg.man_mode_rdf_filename
    rdf_text += "Z> Date of execution     : %s\n" % now.strftime("%d/%m/%Y")
    rdf_text += "Z> Time of execution     : %s\n" % now.strftime("%H:%M:%S")
    rdf_text += "Z> "
    man_file.write("%s\n" % rdf_text)

def man_file_close():
    global man_file
    now = datetime.datetime.now()

    if cfg.is_man_mode and man_file:
        man_file.close()

def man_file_write(text):
    global man_file
    if cfg.is_man_mode:
        man_file.write("S> %s\n" % text)

def print_response(message):
    # Mod1: begin
    global man_file

    text = message.to_text()

    if cfg.is_man_mode:
        rdf_text = message.to_rdf()
        if len(rdf_text) > 0:
            man_file.write("%s\n" % rdf_text)

    if len(text) > 0:
        sys.stdout.write(text + '\n')
        sys.stdout.flush()
# Mod1: end

def write_response(f, message):
    text = message.to_rdf()
    if len(text) > 0:
        f.write(text + '\n')

def print_output_queue():
    global man_file
    map(lambda m: print_response(m) if m.can_display() else None, cfg.output_queue)

    if cfg.rdf_filename:
        try:
            f = open(cfg.rdf_filename, 'a')
            # Mod2: begin
            try:
                os.chown(cfg.rdf_filename, int(os.getenv("SUDO_UID")), int(os.getenv("SUDO_GID")))
            except TypeError:  # If we are not running under "sudo", environment variables "SUDO_GID" and
                pass  # "SUDO_GID" will not be set and there is no point in changing the ownership
            # Mod2: end
            map(lambda m: write_response(f, m) if m.can_generate_rdf() else None, cfg.output_queue)
            f.close()
        except IOError as e:
            # An IO error exception indicates that there might be some 
            # file permission problem.
            message = "Error: RDF file '%s' I/O error, %s" \
                      % (cfg.rdf_filename, e.strerror.lower())
            print_response(ErrorMessage('', message))

    cfg.output_queue = []
