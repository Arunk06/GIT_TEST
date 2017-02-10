# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : progressbar
# File name		        : progressbar.py
# Usage			        : Displays a progress bar in the terminal.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#

from curses import *
from thread import *
from time import sleep


class ProgressBar(object):
    def __init__(self):
        self.show_progress = True
        self.progress_message = ''
        self.begin_animation = False
        self.end_animation = True

    def get_show_progress(self):
        return self.show_progress

    def set_show_progress(self, status):
        self.show_progress = status

    def update_progress_message(self, progress_message):
        self.progress_message = progress_message

    def start_animation(self, title, subtitle, message):
        if not self.begin_animation and self.end_animation:
            self.begin_animation = True
            self.end_animation = False
            start_new_thread(self.__progress_animation, (title, subtitle, message))
            return True
        else:
            return False

    def stop_animation(self):
        self.begin_animation = False
        while not self.end_animation:
            pass

    @staticmethod
    def __restrict_text_length(text, maxlen):
        if len(text) > maxlen:
            text = text[:maxlen - 3] + '...'

        return text

    def __progress_animation(self, title, subtitle, message):
        if not self.show_progress:
            self.end_animation = True
            return

        try:
            w = initscr()
            start_color()
            curs_set(0)
            noecho()
            cbreak()
            w.nodelay(1)

            if has_colors():
                bg1 = COLOR_BLACK
                init_pair(1, COLOR_WHITE, bg1)
                bg2 = COLOR_GREEN
                init_pair(2, COLOR_GREEN, bg2)
                bg3 = COLOR_WHITE
                init_pair(3, COLOR_WHITE, bg3)

            maxy = lambda: w.getmaxyx()[0]
            maxx = lambda: w.getmaxyx()[1]
            midx = lambda: maxx() / 2
            midy = lambda: maxy() / 2

            i = 0  # -2

            bar_length = 16

            w.clear()

            while True:
                title = self.__restrict_text_length(title, maxx())
                subtitle = self.__restrict_text_length(subtitle, maxx())
                message = self.__restrict_text_length(message, maxx())
                self.progress_message = self.__restrict_text_length(self.progress_message, maxx())

                w.attrset(color_pair(1))
                w.addstr(midy() - 5, midx() - len(title) / 2, title, A_BOLD | A_UNDERLINE)
                w.addstr(midy() - 4, midx() - len(subtitle) / 2, subtitle)
                w.addstr(midy() - 2, midx() - len(message) / 2, message)
                w.refresh()

                w.addstr(midy() + 2, 0, ' ' * maxx())
                w.refresh()

                w.addstr(midy() + 2, midx() - len(self.progress_message) / 2, self.progress_message)
                w.refresh()

                w.addstr(midy() - 0, midx() - bar_length / 2, '')
                w.refresh()

                # w.addstr(midy() - 1, midx() - bar_length / 2 - 1, '-------------------')
                # w.addstr(midy() - 0, midx() - bar_length / 2 - 1, '/                 /')
                # w.addstr(midy() + 1, midx() - bar_length / 2 - 1, '-------------------')

                w.attrset(color_pair(2) | A_BOLD)

                w.addch(midy() - 0, midx() - bar_length / 2, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 2, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 4, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 6, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 8, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 10, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 12, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 14, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 16, ' ')

                w.attrset(color_pair(3) | A_BOLD)
                w.addch(midy() - 0, midx() - bar_length / 2 + 2 * i % 18, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 2 * (i + 1) % 18, ' ')
                w.addch(midy() - 0, midx() - bar_length / 2 + 2 * (i + 2) % 18, ' ')

                w.refresh()

                sleep(0.05)

                i = (i + 1) % 9

                if not self.begin_animation:
                    break

            curs_set(1)
            echo()
            nocbreak()
            w.clear()
            w.refresh()
            endwin()
            self.end_animation = True
        except:
            pass

        exit_thread()
