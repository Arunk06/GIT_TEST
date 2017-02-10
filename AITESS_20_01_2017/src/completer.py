# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : completer
# File name		        : completer.py
# Usage			        : Provides command auto-completion features to AITESS.
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#

import glob
from rlcompleter import Completer


class TextModeCompleter(Completer):
    def __init__(self):
        Completer.__init__(self)
        self.matches = []
        self.items = dict()

    def add_item(self, text):
        self.items[text] = None

    def add_items(self, text_list):
        map(self.add_item, text_list)

    def clear(self):
        self.items.clear()

    def complete(self, text, state):
        if state == 0:
            self.matches = self.global_matches(text)
        try:
            return self.matches[state]
        except IndexError:
            return None

    def global_matches(self, text):
        matches = []

        n = len(text)

        # filename auto completions
        for word in self.items.keys() + glob.glob(text + '*'):
            if (word[:n] == text.lower()) or (word[:n] == text):
                matches.append(word)

        return matches
