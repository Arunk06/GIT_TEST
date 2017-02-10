# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : aitessapp
# File name		        : aitessapp.py
# Usage			        : For advanced command line interface in text mode.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 24/06/2015
#       Don't display the real version number and date, those are for internal reference.
#       Display fake version number instead.
#       Refer: IV & V Report No. ADA/LCA/IVV/FCS/57/2015 dated 09/06/2015
# Mod2: hari on 19/10/2015
#       Cache and log file will be now under the ownership of the current user not under
#       root
# Mod3: hari on 10/12/2015
#       AITESS should pickup config.dat from the working directory and should
#       use this as the active directory instead of /opt/aitess
# Mod4: hari on 10/12/2015
#       AITESS should pickup config.dat from the working directory and should
#       use this as the active directory instead of /opt/aitess
#       Line shifted to cfg.pyx
# Mod5: hari on 10/12/2015
#       Command for listing of configuration details

import atexit
import cPickle
import datetime
import glob
import os
import readline
import shlex
from parser import Parser  # For parser.

import cfg  # For globals.
import output
from completer import TextModeCompleter
from configfile import ConfigFile
from errorhandler import *  # For exception handling.
from inputal import PseudoTpfFile
from message import ErrorMessage
from tokens import TokenKeyword, TokenResword
from tokens import TokenType


class AITESSApp(object):
    def __init__(self):
        self.config_file = None
        self.p = None
        self.auto_mode_depth = 0  # nesting of 'auto' calls
        self.batchmode = False
        self.shm_open_status = None
        # Mod5: begin
        self.system_commands_list = ['auto', 'clear', 'purge_file', 'purge_configuration', 'reload_configuration',
                                     'progress_animation', 'skip_evaluation', 'shm_info', 'shm_clear', 'edit_symbol',
                                     'list_configuration', 'high_priority', 'profile_level']
        # Mod5: end

        cached_configuration_loaded = False
        cfg.progress_bar.set_show_progress(True)
        # Mod1: begin
        cfg.progress_bar.start_animation('Advanced Integrated Test Environment System Software',
                                         'Version %s, Developed by FCTS Division, ADE' %
                                         cfg.fake_aitess_version, 'Loading AITESS...')
        # Mod1: end
        self.begin_step_message()
        self.completer = TextModeCompleter()
        # Below code is required, otherwise autocomplete wont work for / and directory or file names.
        readline.set_completer_delims("`~!@#$%^&*()-=+[{]}\|;:'\",<>? \t\n")
        readline.set_completer(self.completer.complete)
        readline.parse_and_bind('tab: complete')

        # Mod4: begin
        if os.path.exists(cfg.history_path):
            readline.read_history_file(cfg.history_path)
        # Mod4: end

        atexit.register(self.__save_history)

        self.init_readconfigfile('Reading configuration file \'%s\' into memory...' %
                                 (os.path.basename(cfg.configuration_filename)))
        cfg.shm.init_apgio_dicts()

        self.init_shm('Opening shared memory...')
        self.init_parser('Initializing parser...')

        self.__show_shm_status()

        if cfg.config_file.get_value("usecache") == "true":
            if os.access(cfg.cached_configuration_filename, os.F_OK):
                cache_load_success = self.__load_cached_configuration('Loading information cached from \'%s\'...' %
                                                                      (os.path.basename(cfg.configuration_filename)))
                if cache_load_success:
                    cached_configuration_loaded = True
                else:
                    cfg.symbol_table.clear()
                    cfg.symbol_table.update_cache_version()
                    self.init_execconfigfile('AITESS version change re-caching the information...')
                    self.__cache_configuration()
            else:
                self.init_execconfigfile(
                    'Executing contents of configuration file \'%s\' and caching the information...' %
                    (os.path.basename(cfg.configuration_filename)))
                self.__cache_configuration()
        else:
            self.init_execconfigfile('Executing contents of configuration file \'%s\'...' %
                                     (os.path.basename(cfg.configuration_filename)))
            self.__cache_configuration()

        cfg.progress_bar.stop_animation()
        self.__load_startup_files()

        if cached_configuration_loaded:
            self.__print_in_pink("Message: Using cached 'config.dat'")
            sys.stdout.flush()

        self.__configure_UUT()
        self.__check_configuration()

        sys.stdout.flush()

    def __show_shm_status(self):
        shm_info = cfg.shm.info_shm()

        # self.__print_in_yellow("SharedMemory: in 0x%08x, out 0x%08x, task 0x%08x, err 0x%08x" % (
        #    shm_info["in"], shm_info["out"], shm_info["task"], shm_info["error"]))

        for memory in ("in", "out", "task", "error"):
            if not self.shm_open_status[memory]:
                self.__print_in_red("SharedMemory: Memory allocation failed for %s\n" % memory)

    @staticmethod
    def __print_in_yellow(text, bold=False, underline=False):
        bold_seq = cfg.BOLD if bold else ""
        underline_seq = cfg.UNDERLINE if underline else ""
        sys.stdout.write(bold_seq + underline_seq + cfg.BRIGHT_YELLOW + text + "\n" + cfg.COLOR_END)

    @staticmethod
    def __print_in_pink(text, bold=False, underline=False):
        bold_seq = cfg.BOLD if bold else ""
        underline_seq = cfg.UNDERLINE if underline else ""
        sys.stdout.write(bold_seq + underline_seq + cfg.BRIGHT_PINK + text + "\n" + cfg.COLOR_END)

    @staticmethod
    def __print_in_red(text, bold=False, underline=False):
        bold_seq = cfg.BOLD if bold else ""
        underline_seq = cfg.UNDERLINE if underline else ""
        sys.stdout.write(bold_seq + underline_seq + cfg.BRIGHT_RED + text + "\n" + cfg.COLOR_END)

    def __configure_UUT(self):
        if cfg.config_file.is_configured_for_ADC():
            cfg.shm.set_UUT(1)
            self.__print_in_pink("Message: AITESS configured for ADC")
        elif cfg.config_file.is_configured_for_LADC():
            cfg.shm.set_UUT(3)
            self.__print_in_pink("Message: AITESS configured for LADC")
        elif cfg.config_file.is_configured_for_DFCC():
            cfg.shm.set_UUT(2)
            self.__print_in_pink("Message: AITESS configured for DFCC Mk1")
        elif cfg.config_file.is_configured_for_DFCC_MK1A():
            cfg.shm.set_UUT(2)  # Be careful UUT code is 2 for MK1 and MK1A
            self.__print_in_pink("Message: AITESS configured for DFCC Mk1A")
        elif cfg.config_file.is_configured_for_DFCC_MK2():
            cfg.shm.set_UUT(2)  # Be careful UUT code is 2 for MK1 and MK2
            self.__print_in_pink("Message: AITESS configured for DFCC Mk2")
        else:  # defaults to LADC
            cfg.shm.set_UUT(3)
            self.__print_in_pink("Message: UUT not/incorrectly specified, AITESS configured for LADC/DFCC Mk1")

    def __show_prompt(self):
        if self.batchmode:
            text = sys.stdin.readline()
            sys.stdout.write("\n>>> %s" % text)
            return text
        else:
            if not cfg.display_state and cfg.is_man_mode:
                status = cfg.BRIGHT_RED + '(DISP=OFF, MODE=MAN)' + cfg.COLOR_END
            elif not cfg.display_state:
                status = cfg.BRIGHT_RED + '(DISP=OFF)' + cfg.COLOR_END
            elif cfg.is_man_mode:
                status = cfg.BRIGHT_RED + '(MODE=MAN)' + cfg.COLOR_END
            else:
                status = ''
            return str(raw_input('%s>>> ' % status))

    def __log_file_open(self):
        now = datetime.datetime.now()
        self.log_file = open(cfg.get_logfile_path(), 'a')
        # Mod2: begin
        try:
            os.chown(cfg.get_logfile_path(), int(os.getenv("SUDO_UID")), int(os.getenv("SUDO_GID")))
        except TypeError:  # If we are not running under "sudo", environment variables "SUDO_GID" and
            pass  # "SUDO_GID" will not be set and there is no point in changing the ownership
        # Mod2: end
        self.log_file.write('<BEG>Session began on %s at %s.\n' % (now.strftime("%d/%m/%Y"), now.strftime("%H:%M:%S")))

    def __log_file_close(self):
        now = datetime.datetime.now()
        self.log_file.write('<END>Session ended on %s at %s.\n' % (now.strftime("%d/%m/%Y"), now.strftime("%H:%M:%S")))
        self.log_file.close()

    def __log_file_write(self, text):
        if cfg.logging_state:
            now = datetime.datetime.now()
            self.log_file.write("[%s]>>> %s\n" % (now.strftime("%H:%M:%S"), text))

    def __load_startup_files(self):
        if os.access(cfg.get_sysstartfile_path(), os.F_OK):
            self.__setup_environment(cfg.get_sysstartfile_path())
        if os.access(cfg.get_usrstartfile_path(), os.F_OK):
            self.__setup_environment(cfg.get_usrstartfile_path())

    def __check_configuration(self):
        config_items = ["sysdbfpath", "sysdbf", "sysmacpath", "sysmacfile", "syslibpath", "syslibfile",
                        "usrdbfpath", "usrdbf", "usrmacpath", "usrmacfile", "usrlibpath", "usrlibfile",
                        "tpfpath", "rdfpath", "downloadpath", "uploadpath"]

        for item in config_items:
            original_value = cfg.config_file.get_value(item, filter_=False)
            filtered_value = cfg.config_file.get_value(item)
            if original_value != filtered_value:
                self.__print_in_pink("config.dat: '%s=%s' => '%s=%s'\n" %
                                     (item, original_value, item,
                                      '«nil»' if len(filtered_value) == 0 else filtered_value))

        sys.stdout.flush()

    @staticmethod
    def __cache_configuration():
        f = open(cfg.cached_configuration_filename, 'wb')
        # Mod2: begin
        try:
            os.chown(cfg.cached_configuration_filename, int(os.getenv("SUDO_UID")), int(os.getenv("SUDO_GID")))
        except TypeError:  # If we are not running under "sudo", environment variables "SUDO_GID" and
            pass  # "SUDO_GID" will not be set and there is no point in changing the ownership
        # Mod2: end
        p = cPickle.Pickler(f, -1)
        p.dump(cfg.symbol_table)
        f.close()

    def __load_cached_configuration(self, begin_message, end_message=None):
        self.begin_step_message(begin_message)
        f = open(cfg.cached_configuration_filename, 'rb')
        p = cPickle.Unpickler(f)
        cfg.symbol_table = p.load()
        f.close()
        self.end_step_message(end_message)
        if cfg.symbol_table.get_cache_version() == cfg.aitess_version_long:
            return True
        else:
            return False

    # Mod4: begin
    @staticmethod
    def __save_history(history_path=cfg.history_path):
        # Mod4: end
        try:
            readline.write_history_file(history_path)
            os.chown(history_path, int(os.getenv("SUDO_UID")), int(os.getenv("SUDO_GID")))
        except:
            pass

    def __get_path_files(self):
        """
        For getting a list of file names from download and test plan files directory for autocompletion
        """
        filename_list = (glob.glob(self.config_file.get_value("tpfpath") + '*') +
                         glob.glob(self.config_file.get_value("downloadpath") + '*'))

        return map(lambda x: x.split('/')[-1], filename_list)

    def __execute_config_entries(self, path_name, file_name, message_title):
        """Executes a configuration entry.

        This method executes configuration entry specified in path_name.
        """
        if (len(self.config_file.get_value(path_name)) > 0) and (len(self.config_file.get_value(file_name)) > 0):
            init_file = self.config_file.get_value(path_name) + self.config_file.get_value(file_name)
            self.__setup_environment(init_file, message_title)

    def __process_command_list_configuration(self):
        nil_text = cfg.RED + '«nil»' + cfg.COLOR_END
        option_names_list = ["project", "uut", "usecache", "rdfversions", "sysdbfpath", "sysdbf",
                             "sysmacpath", "sysmacfile", "syslibpath", "syslibfile", "usrdbfpath",
                             "usrdbf", "usrmacpath", "usrmacfile", "usrlibpath", "usrlibfile",
                             "tpfpath", "rdfpath", "downloadpath", "uploadpath"]

        sys.stdout.write("Configuration information\n"
                         "—————————————————————————\n")
        sys.stdout.write("  From file '%s'\n" % cfg.configuration_filename)

        for option_name in option_names_list:
            option_value = self.config_file.get_value(option_name)
            if len(option_value) == 0:
                option_value = nil_text
            sys.stdout.write("     %-13s = %s\n" % (option_name, option_value))

    @staticmethod
    def __process_command_edit_configuration():
        sys.stdout.write("Editing the configuration from the application is no longer supported.\n"
                         "The correct procedure is to exit AITESS go to the directory containing the\n"
                         "configuration file and edit the 'config.dat' file using any text editor of\n"
                         "your choice, save the file and restart AITESS and type 'reload_configuration'\n"
                         "in the AITESS prompt.\n")

    def __process_command_reload_configuration(self, text_parts):
        if len(text_parts) == 1:
            self.reload_config()
        else:
            output.print_response(
                ErrorMessage('', "Error: System command 'reload_configuration' expects no parameters."))

    @staticmethod
    def __process_command_high_priority(text_parts):
        if len(text_parts) == 1:
            if cfg.is_high_priority:
                sys.stdout.write("high_priority is 'on'\n")
            else:
                sys.stdout.write("high_priority is 'off'\n")
        elif len(text_parts) == 2:
            if text_parts[1] == 'on':
                cfg.is_high_priority = True
                sys.stdout.write("high_priority set to 'on'\n")
            elif text_parts[1] == 'off':
                cfg.is_high_priority = False
                sys.stdout.write("high_priority set to 'off'\n")
            else:
                output.print_response(
                    ErrorMessage('', "Error: Unknown parameter '%s' for system command 'high_priority'." %
                                 text_parts[1]))
        else:
            output.print_response(
                ErrorMessage('', "Error: System command 'high_priority' expects zero/one parameter(s)."))

    def __process_command_profile_level(self, text_parts):
        if len(text_parts) == 1:
            sys.stdout.write("profile_level is %d\n" % self.p.get_profile_level())
        elif len(text_parts) == 2:
            if text_parts[1] in ('0', '1', '2', '3'):
                profile_level = int(text_parts[1])
                self.p.set_profile_level(profile_level)
                sys.stdout.write("profile_level set to %d\n" % profile_level)
            else:
                output.print_response(
                    ErrorMessage('', "Error: Unknown parameter '%s' for system command "
                                     "'profile_level'." % text_parts[1]))
        else:
            output.print_response(
                ErrorMessage('', "Error: System command 'profile_level' expects zero/one parameter(s)."))

    @staticmethod
    def __process_command_progress_animation(text_parts):
        if len(text_parts) == 1:
            if cfg.progress_bar.get_show_progress():
                sys.stdout.write("progress_animation is 'on'\n")
            else:
                sys.stdout.write("progress_animation is 'off'\n")
        elif len(text_parts) == 2:
            if text_parts[1] == 'on':
                cfg.progress_bar.set_show_progress(True)
                sys.stdout.write("progress_animation set to 'on'\n")
            elif text_parts[1] == 'off':
                cfg.progress_bar.set_show_progress(False)
                sys.stdout.write("progress_animation set to 'off'\n")
            else:
                output.print_response(
                    ErrorMessage('', "Error: Unknown parameter '%s' for system command "
                                     "'progress_animation'." % text_parts[1]))
        else:
            output.print_response(
                ErrorMessage('', "Error: System command 'progress_animation' expects zero/one parameter(s)."))

    def __process_command_edit_symbol(self, text_parts):
        if len(text_parts) == 3:
            self.edit_symbol(text_parts[1].lower(), text_parts[2].lower())
        else:
            output.print_response(
                ErrorMessage('', "Error: System command 'edit_symbol' expects two parameters."))

    @staticmethod
    def __process_command_shm_clear(text_parts):
        if len(text_parts) == 1:
            cfg.shm.clear_shm()
            sys.stdout.write("Shared memory cleared\n")
        else:
            output.print_response(ErrorMessage('', "Error: System command 'shm_clear' has no parameters."))

    def __process_command_shm_info(self, text_parts):
        if len(text_parts) == 1:
            shm_info = cfg.shm.info_shm()
            self.__print_in_yellow("Shared memory information", bold=True, underline=True)
            self.__print_in_yellow("  in     = 0x%08x" % shm_info["in"])
            self.__print_in_yellow("  out    = 0x%08x" % shm_info["out"])
            self.__print_in_yellow("  task   = 0x%08x" % shm_info["task"])
            self.__print_in_yellow("  err    = 0x%08x" % shm_info["error"])
        else:
            output.print_response(ErrorMessage('', "Error: System command 'shm_info' has no parameters."))

    def __process_command_skip_evaluation(self, text_parts):
        if len(text_parts) == 1:
            if self.p.get_skip_evaluation():
                sys.stdout.write("skip_evaluation is 'on'\n")
            else:
                sys.stdout.write("skip_evaluation is 'off'\n")
        elif len(text_parts) == 2:
            if text_parts[1] == 'on':
                self.p.set_skip_evaluation(True)
                sys.stdout.write("skip_evaluation set to 'on'\n")
            elif text_parts[1] == 'off':
                self.p.set_skip_evaluation(False)
                sys.stdout.write("skip_evaluation set to 'off'\n")
            else:
                output.print_response(
                    ErrorMessage('', "Error: Unknown parameter '%s' for system command 'skip_evaluation'." %
                                 text_parts[1]))
        else:
            output.print_response(
                ErrorMessage('', "Error: System command 'skip_evaluation' expects zero/one parameter(s)."))

    def __process_command_purge_configuration(self, text_parts):
        if len(text_parts) == 1:
            self.purge_config()
        else:
            output.print_response(
                ErrorMessage('', "Error: System command 'purge_configuration' expects no parameters."))

    @staticmethod
    def __process_command_man(text_parts):
        if len(text_parts) == 1:
            if cfg.is_auto_mode:
                output.print_response(
                    ErrorMessage('', "Error: Cannot enter 'man' mode while executing in 'auto' mode."))
            elif cfg.is_man_mode:  # leaving man mode
                output.man_file_close()
                cfg.is_man_mode = False
            else:  # entering man mode
                try:
                    output.man_file_open()
                except IOError as e:
                    # An IO error exception indicates that there might be some
                    # file permission problem.
                    message = "Error: Cannot enter 'man' mode since RDF file '%s' cannot be cleared, %s." \
                              % (cfg.man_mode_rdf_filename, e.strerror.lower())
                    output.print_response(ErrorMessage('', message))
                else:
                    cfg.is_man_mode = True
        else:
            output.print_response(ErrorMessage('', "Error: System command 'man' expects no parameters."))

    def __process_command_auto(self, text, text_parts):
        if len(text_parts) == 2:
            if cfg.is_man_mode:
                output.print_response(
                    ErrorMessage('', "Error: Cannot enter 'auto' mode while executing in 'man' mode."))
            else:
                # we need file names in correct case
                original_text_parts = shlex.split(str(text), posix=False)
                # auto is transient mode - we turn it on, execute batch, then we turn it off
                cfg.is_auto_mode = True
                self.auto_mode_depth += 1
                self.call_batchfile(original_text_parts[1])
                self.auto_mode_depth -= 1
                # auto is transient mode - we turn it on, execute batch, then we turn it off
                if self.auto_mode_depth == 0:
                    cfg.is_auto_mode = False
        else:
            output.print_response(ErrorMessage('', "Error: System command 'auto' expects one parameter."))

    def __process_command_purge(self, text, text_parts):
        if len(text_parts) == 2:
            # we need file names in correct case
            original_text_parts = shlex.split(str(text), posix=False)
            self.purge_file(original_text_parts[1])
        else:
            while True:
                num = 0
                purge_map = {}
                sources = cfg.symbol_table.get_external_sources()
                sources.sort()
                for s in sources:
                    num += 1
                    purge_map[num] = s

                self.__print_in_red("\nPurge File", bold=True, underline=True)
                for k in purge_map.keys():
                    print "%3d : %s" % (k, purge_map[k])

                try:
                    choice = int(raw_input("Enter file number to purge or 0 to exit: "))
                except ValueError:
                    sys.stdout.write('Error: Expected a number.\n')
                    continue

                if choice in purge_map.keys():
                    self.purge_file(purge_map[choice])
                elif choice == 0:
                    break
                else:
                    sys.stdout.write('Error: Invalid choice.\n')

    @staticmethod
    def __check_log_file_size():
        if os.path.exists(cfg.get_logfile_path()) and (os.path.getsize(cfg.get_logfile_path()) > 1024 * 1024):
            while True:
                choice = raw_input("Log file '%s' size is greater than 1MB, clear it (Y/N)? " % cfg.logging_filename)
                if choice.lower() == 'y':
                    os.remove(cfg.get_logfile_path())
                    break
                elif choice.lower() == 'n':
                    break

    def __setup_environment(self, init_file, message_title='Environment Initialization Error'):
        """Sets up the the initial environment for AITESS

        This method sets up the initial environment for AITESS. It does this
        by executing the test plan file pointed to by 'init_file'. Any error
        encountered while processing this file is reported.
        """
        try:
            self.execute_file(init_file)
            # FIXED: Comments displayed at startup
            map(lambda m: output.print_response(m) if m.can_display() else None, cfg.output_queue)
            cfg.output_queue = []
        except (ScanError, ParseError, EvaluationError) as e:
            cfg.progress_bar.stop_animation()
            self.show_init_error(message_title, str(e))
        except ExitError:
            cfg.progress_bar.stop_animation()
            self.show_init_error(message_title, "Exit Warning: Startup script exited")
        except UserExitError:
            cfg.progress_bar.stop_animation()
            self.show_init_error(message_title, "User Exit Warning: Startup script exited")
        except AssertError:
            cfg.progress_bar.stop_animation()
            self.show_init_error(message_title, "Assert Error: Assertion failure in startup script")
        except BaseException:
            cfg.progress_bar.stop_animation()
            self.show_init_error(message_title, GenerateExceptionMessage())

    def execute_config(self, show_messages=True):
        """Executes the configuration from memory.

        This method excutes configuration entries from memory by calling
        __execute_config_entries.
        """
        current_display_state = cfg.display_state
        cfg.display_state = False

        if show_messages:
            self.begin_step_message("Loading system database file...")
        self.__execute_config_entries('sysdbfpath', 'sysdbf',
                                      'Configuration File Error: System Database File')
        if show_messages:
            self.end_step_message()

        if show_messages:
            self.begin_step_message("Loading user database file...")
        self.__execute_config_entries('usrdbfpath', 'usrdbf',
                                      'Configuration File Error: User Database File')
        if show_messages:
            self.end_step_message()

        if show_messages:
            self.begin_step_message("Loading system macro file...")
        self.__execute_config_entries('sysmacpath', 'sysmacfile',
                                      'Configuration File Error: System Macro File')
        if show_messages:
            self.end_step_message()

        if show_messages:
            self.begin_step_message("Loading user macro file...")
        self.__execute_config_entries('usrmacpath', 'usrmacfile',
                                      'Configuration File Error: User Macro File')
        if show_messages:
            self.end_step_message()

        if show_messages:
            self.begin_step_message("Loading system library file...")
        self.__execute_config_entries('syslibpath', 'syslibfile',
                                      'Configuration File Error: System Library File')
        if show_messages:
            self.end_step_message()

        if show_messages:
            self.begin_step_message("Loading user library file...")
        self.__execute_config_entries('usrlibpath', 'usrlibfile',
                                      'Configuration File Error: User Library File')
        if show_messages:
            self.end_step_message()

        cfg.display_state = current_display_state

    def init_readconfigfile(self, begin_message, end_message=None):
        self.begin_step_message(begin_message)
        try:
            self.config_file = ConfigFile(cfg.configuration_filename)
            cfg.config_file = self.config_file
        except BaseException as e:
            cfg.progress_bar.stop_animation()
            self.show_init_error('Environment Initialization Error',
                                 "ConfigurationFileError: %s, AITESS cannot continue without fixing the error" % str(e))
            exit(-1)
        self.end_step_message(end_message)

    def init_execconfigfile(self, begin_message, end_message=None):
        """Executes the configuration file contents.

        This initialization method executes configuration file entries from
        memory showing appropriate progress messages.
        """
        self.begin_step_message(begin_message)
        self.execute_config()
        self.end_step_message(end_message)

    def init_environment(self, begin_message, end_message=None):
        self.begin_step_message(begin_message)
        self.__setup_environment(cfg.get_sysstartfile_path())
        self.end_step_message(end_message)

    def init_parser(self, begin_message, end_message=None):
        self.begin_step_message(begin_message)
        self.p = Parser()
        self.end_step_message(end_message)

    def init_shm(self, begin_message, end_message=None):
        self.begin_step_message(begin_message)
        self.shm_open_status = cfg.shm.open_shm()
        self.end_step_message(end_message)

    def validate_input(self, text):
        """Validates the input.

        This method checks whether the user entered input is valid. Any input
        containing invalid characters are identified as invalid input and the
        user is notified.
        """
        output.man_file_write(text)
        self.__log_file_write(text)
        return text.strip()

    def execute_command(self, command):
        """Sets up the the initial environment for AITESS

        This method sets up the initial environment for AITESS. It does this
        by executing the test plan file pointed to by 'init_file'. Any error
        encountered while processing this file is reported.
        """
        self.p.parse(PseudoTpfFile(command))

    def execute_file(self, file_name):
        """Sets up the the initial environment for AITESS

        This method sets up the initial environment for AITESS. It does this
        by executing the test plan file pointed to by 'init_file'. Any error
        encountered while processing this file is reported.
        """
        self.p.parse(PseudoTpfFile('@' + file_name))

    @staticmethod
    def show_init_error(title, message):
        sys.stdout.write(ErrorMessage('', title + ' : ' + message).to_text() + "\n")

    @staticmethod
    def begin_step_message(message=None):
        if message is None:
            cfg.progress_bar.update_progress_message('')
        else:
            cfg.progress_bar.update_progress_message(message)

    def end_step_message(self, message=None):
        pass

    def purge_file(self, filename):
        while True:
            choice = raw_input(cfg.BOLD + cfg.BRIGHT_RED + cfg.UNDERLINE + "Warning!!!" + cfg.COLOR_END + "\n" +
                               cfg.BOLD + cfg.BRIGHT_RED +
                               "This will clear all entries including session variables, functions, macros, symbols "
                               "etc. which were loaded from the file '%s' (if present).\nDo you wish to continue (Y/N)"
                               "? " % filename + cfg.COLOR_END)
            if choice.lower() == 'y':
                sys.stdout.write("Trying to purge names loaded from file '%s'..." % filename)
                try:
                    cfg.symbol_table.purge_file(filename)
                except TypeError as e:
                    sys.stdout.write("\n" + str(e) + "\n")
                else:
                    sys.stdout.write("done.")
                self.completer.clear()  # clear everything in autocomplete including the unloaded names
                break
            elif choice.lower() == 'n':
                break

    def call_batchfile(self, filename):
        filename = cfg.config_file.get_tpfpath(filename)

        try:
            f = open(filename, "rt")
            lines = f.readlines()
        except IOError as e:
            # An IO error exception indicates that there might be some 
            # file permission problem.
            message = "Error: Batch file '%s' I/O error, %s." \
                      % (filename, e.strerror.lower())
            output.print_response(ErrorMessage('', message))
            return

        for line in lines:
            sys.stdout.write(">>> %s" % line)
            self.process_commands(line=line, callbatch=True)

        f.close()

    def purge_config(self):
        while True:
            choice = raw_input(cfg.BOLD + cfg.BRIGHT_RED + cfg.UNDERLINE + "Warning!!!" + cfg.COLOR_END + "\n" +
                               cfg.BOLD + cfg.BRIGHT_RED +
                               "This will clear all symbol table entries. All entries including session variables, "
                               "functions, macros, symbols etc. will be lost.\nDo you wish to continue (Y/N)? " +
                               cfg.COLOR_END)
            if choice.lower() == 'y':
                sys.stdout.write("Purging internal symbol table...")
                cfg.symbol_table.clear()
                self.completer.clear()
                break
            elif choice.lower() == 'n':
                break

    @staticmethod
    def edit_symbol(symbol_name, symbol_attribute):
        nil_text = cfg.RED + '«nil»' + cfg.COLOR_END
        try:
            e = cfg.symbol_table.get_entry(symbol_name)
        except KeyError:
            output.print_response(ErrorMessage('', "Error: Name not found."))
            return

        if e.get_type() == TokenType.TYP_SYMBOL:
            try:
                if symbol_attribute == 'chan':
                    e.chan = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                 bin(e.chan) if e.chan is not None else nil_text)), 2)
                elif symbol_attribute == 'addr':
                    e.addr = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                 hex(e.addr) if e.addr is not None else nil_text)), 16)
                elif symbol_attribute in ('type', 'dtype'):
                    dtype = str(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                e.dtype if e.dtype is not None else nil_text))).lower()
                    if dtype in ('ffp', 'dword', 'word', 'byte', 'u32', 'u16', 'u8', 'dpi', 'spi', 's32', 's16', 's8',
                                 'ssi', 'dis_32', 'd32', 'dis_16', 'd16', 'dis', 'dis_8', 'd8', 'u24', 's24'):
                        e.set_dtype(dtype)
                    else:
                        raise ValueError
                elif symbol_attribute == 'min':
                    e.min_ = eval(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.min_ if e.min_ is not None else nil_text)))
                elif symbol_attribute == 'max':
                    e.max_ = eval(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.max_ if e.max_ is not None else nil_text)))
                elif symbol_attribute == 'ofst1':
                    e.ofst1 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.ofst1 if e.ofst1 is not None else nil_text)))
                elif symbol_attribute == 'ofst2':
                    e.ofst2 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.ofst2 if e.ofst2 is not None else nil_text)))
                elif symbol_attribute == 'ofst3':
                    e.ofst3 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.ofst3 if e.ofst3 is not None else nil_text)))
                elif symbol_attribute == 'ofst4':
                    e.ofst4 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.ofst4 if e.ofst4 is not None else nil_text)))
                elif symbol_attribute == 'slpe':
                    e.slpe = eval(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.slpe if e.slpe is not None else nil_text)))
                    e.slpe_text = ''
                elif symbol_attribute == 'bias':
                    e.bias = eval(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  e.bias if e.bias is not None else nil_text)))
                    e.bias_text = ''
                elif symbol_attribute == 'mask':
                    e.mask = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                 hex(e.mask) if e.mask is not None else nil_text)), 16)
                elif symbol_attribute == 'id':
                    e.id_ = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                e.id_ if e.id_ is not None else nil_text)))
                elif symbol_attribute == 'ofst':
                    e.ofstx = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  hex(e.ofstx) if e.ofstx is not None else nil_text)
                                            ), 16)
                elif symbol_attribute == 'mask1':
                    e.mask1 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  hex(e.mask1) if e.mask1 is not None else nil_text)
                                            ), 16)
                elif symbol_attribute == 'mask2':
                    e.mask2 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  hex(e.mask2) if e.mask2 is not None else nil_text)
                                            ), 16)
                elif symbol_attribute == 'mask3':
                    e.mask3 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  hex(e.mask3) if e.mask3 is not None else nil_text)
                                            ), 16)
                elif symbol_attribute == 'mask4':
                    e.mask4 = int(raw_input('%s => %s[=%s]=? ' % (symbol_name, symbol_attribute,
                                                                  hex(e.mask4) if e.mask4 is not None else nil_text)
                                            ), 16)
                else:
                    output.print_response(
                        ErrorMessage('', "Error: Invalid attribute or editing of attribute not supported."))
                    return
            except (ValueError, SyntaxError, NameError, ZeroDivisionError):
                output.print_response(
                    ErrorMessage('', "Error: Attribute value not updated due to incorrect/empty given value."))
                return
        else:
            output.print_response(ErrorMessage('', "Error: Name not a symbol."))
            return

        sys.stdout.write("Updated the atrribute value.\n")

    def reload_config(self):
        while True:
            choice = raw_input(cfg.BOLD + cfg.BRIGHT_RED + cfg.UNDERLINE + "Warning!!!" + cfg.COLOR_END + "\n" +
                               cfg.BOLD + cfg.BRIGHT_RED +
                               "This will clear all symbol table entries and reload them from the configuration file. "
                               "All entries including session variables, functions, macros, symbols etc. will be lost."
                               "\nDo you wish to continue (Y/N)? " + cfg.COLOR_END)
            if choice.lower() == 'y':
                sys.stdout.write('Purging and reloading internal symbol table...\n')
                # Mod1: begin
                cfg.progress_bar.start_animation('Advanced Integrated Test Environment System Software',
                                                 'Version %s, Developed by FCTS Division, ADE' %
                                                 cfg.fake_aitess_version, 'Reloading configuration...')
                # Mod1: end
                self.begin_step_message()

                try:
                    os.remove(cfg.cached_configuration_filename)  # remove the cached configuration file
                except:
                    pass

                cfg.symbol_table.clear()
                self.completer.clear()

                # read in the configuration file again
                self.init_readconfigfile('Reading configuration file \'%s\' into memory...' %
                                         (os.path.basename(cfg.configuration_filename)))
                cfg.shm.init_apgio_dicts()

                if cfg.config_file.get_value("usecache") == "true":
                    self.init_execconfigfile(
                        'Executing contents of configuration file \'%s\' and caching the information...' %
                        (os.path.basename(cfg.configuration_filename)))
                    self.__cache_configuration()
                else:
                    self.init_execconfigfile('Executing contents of configuration file \'%s\'...' %
                                             (os.path.basename(cfg.configuration_filename)))
                    self.__cache_configuration()  # Always cache

                cfg.progress_bar.stop_animation()
                self.__load_startup_files()
                self.__configure_UUT()
                self.__check_configuration()
                break
            elif choice.lower() == 'n':
                break

    def interactive_processing(self):
        try:
            self.__check_log_file_size()
            self.__log_file_open()
            for text in sys.stdin:
                sys.stdout.write("\n>>> %s" % text)
                self.p.parse(PseudoTpfFile(text))
                output.print_output_queue()
            self.__log_file_close()
        except (InputError, ScanError, ParseError, EvaluationError, ExitError, UserExitError, AssertError) as e:
            output.print_output_queue()
            output.print_response(ErrorMessage('', str(e)))
        except KeyboardInterrupt:
            output.print_output_queue()
            output.print_response(ErrorMessage('', "Error: Execution terminated through Ctrl-C."))
        except BaseException:
            output.print_output_queue()
            output.print_response(ErrorMessage('', GenerateExceptionMessage()))

    def process_commands(self, line=None, callbatch=False):
        while True:
            try:
                cfg.rdf_filename = ''  # clear RDF file name
                self.completer.clear()
                self.completer.add_items(TokenKeyword.keys() + TokenResword.keys() + self.system_commands_list +
                                         self.__get_path_files())
                self.completer.add_items(cfg.symbol_table.keys())
                if not callbatch:
                    self.auto_mode_depth = 0
                    text = self.__show_prompt()
                else:
                    text = line
            except KeyboardInterrupt:
                sys.stdout.write('\n')
                continue
            except EOFError:
                output.man_file_write('exit (^D)')
                output.man_file_close()
                self.__log_file_write('exit (^D)')
                sys.stdout.write('\n')
                return 0

            try:
                text = self.validate_input(text)
                try:
                    text_parts = shlex.split(text.lower(), posix=False)
                except ValueError:  # unbalanced quotes
                    text_parts = [text.lower()]

                if not text:
                    if callbatch:  # for batch call exit after each executed command
                        return 0
                    else:  # for interactive mode continue in loop
                        continue
                elif text_parts[0] == 'exit':
                    if len(text_parts) > 1:
                        output.print_response(ErrorMessage('', "Error: System command 'exit' has no parameters."))
                    else:
                        return 0
                elif text_parts[0] == 'clear':
                    if len(text_parts) > 1:
                        output.print_response(ErrorMessage('', "Error: System command 'clear' has no parameters."))
                    else:
                        sys.stdout.write('\x1b[H\x1b[2J\r')
                        # Clear should have a 'continue' otherwise a new line will be inserted
                        # by the end of this loop but in batch mode if we do 'continue' the loop
                        # will be infinite due to text being assigned 'clear' again and again.
                        if callbatch:  # for batch call exit after each executed command
                            return 0
                        else:  # for interactive mode continue in loop
                            continue
                elif text_parts[0] == 'purge_file':
                    self.__process_command_purge(text, text_parts)
                elif text_parts[0] == 'auto':
                    self.__process_command_auto(text, text_parts)
                elif text_parts[0] == 'man':
                    self.__process_command_man(text_parts)
                elif text_parts[0] == 'purge_configuration':
                    self.__process_command_purge_configuration(text_parts)
                elif text_parts[0] == 'reload_configuration':
                    self.__process_command_reload_configuration(text_parts)
                elif text_parts[0] == 'edit_configuration':
                    self.__process_command_edit_configuration()
                # Mod5: begin
                elif text_parts[0] == 'list_configuration':
                    self.__process_command_list_configuration()
                # Mod5: end
                elif text_parts[0] == 'high_priority':
                    self.__process_command_high_priority(text_parts)
                elif text_parts[0] == 'progress_animation':
                    self.__process_command_progress_animation(text_parts)
                elif text_parts[0] == 'skip_evaluation':
                    self.__process_command_skip_evaluation(text_parts)
                elif text_parts[0] == 'shm_info':
                    self.__process_command_shm_info(text_parts)
                elif text_parts[0] == 'shm_clear':
                    self.__process_command_shm_clear(text_parts)
                elif text_parts[0] == 'edit_symbol':
                    self.__process_command_edit_symbol(text_parts)
                elif text_parts[0] == 'profile_level':
                    self.__process_command_profile_level(text_parts)
                elif text:
                    # Perform the parsing.
                    self.p.parse(PseudoTpfFile(text))
                    output.print_output_queue()
            except (InputError, ScanError, ParseError, EvaluationError, ExitError, UserExitError, AssertError) as e:
                output.print_output_queue()
                output.print_response(ErrorMessage('', str(e)))
            except KeyboardInterrupt:
                output.print_output_queue()
                output.print_response(ErrorMessage('', "Error: Execution terminated through Ctrl-C."))
            except BaseException:
                output.print_output_queue()
                output.print_response(ErrorMessage('', GenerateExceptionMessage()))

            try:
                # Do not print new line for line comments
                if not text.startswith("!") or text.startswith("!#"):
                    sys.stdout.write('\n')
            except KeyboardInterrupt:
                output.print_output_queue()
                output.print_response(ErrorMessage('', "Error: Processing terminated through Ctrl-C."))

            if callbatch:  # Don't loop
                return 0

    def start(self, batchmode=False):
        self.batchmode = batchmode
        self.__check_log_file_size()
        self.__log_file_open()
        self.process_commands()
        self.__log_file_close()
