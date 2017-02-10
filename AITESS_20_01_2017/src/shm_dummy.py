# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : shm_dummy
# File name		        : shm_dummy.py
# Usage			        : Provides dummy shared memory functions for execution in development environment
# Authors		        : Hari Kiran K (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#

boot_message_addr = 0x0


# cpdef init_apgio_dicts():
def init_apgio_dicts():
    pass


# cpdef clear_shm():
def clear_shm():
    pass


# cpdef info_shm():
def info_shm():
    return {"in": 0x0, "out": 0x0, "task": 0x0, "error": 0x0}


# cpdef open_shm():
def open_shm():
    return {"in": True, "out": True, "task": True, "error": True}


# cpdef close_shm():
def close_shm():
    pass


# cpdef set_UUT(unsigned char UUT_code):
def set_UUT(arg):
    pass


# cpdef inline tuple boot():
def boot():
    return {'frame': 12345678, 'start_address': 0xb, 'end_address': 0xe,
            'value': ("booted", "booted", "booted", "booted"), 'status': (0, 0, 0, 0)},


# cpdef inline reset_active_buffer_lookup():
def reset_active_buffer_lookup():
    pass


# cpdef inline unsigned char get_active_buffer_lookup(unsigned char channel, unsigned char id_):
def get_active_buffer_lookup(arg1, arg2):
    return 1


# cpdef inline set_active_buffer(unsigned char channel, unsigned char id_, unsigned char buffer_):
def set_active_buffer(arg1, arg2, arg3):
    pass


# cpdef switch_buffers(list nodes):
def switch_buffers(arg):
    pass


# cpdef inline dict write_simproc(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_simproc(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_simproc(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_simproc(symbol, user_mask, user_offset, bypass):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_dpfs(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_dpfs(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_dpfs(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_dpfs(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_rs422in(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_rs422in(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_rs422in(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_rs422in(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_rs422out(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_rs422out(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_rs422out(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_rs422out(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_rs422task(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_rs422task(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_rs422task(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_rs422task(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_rs422error(object symbol, unsigned int user_mask, unsigned int user_offset,
# bool bypass, data):
def write_rs422error(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_rs422error(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_rs422error(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_mil1553btask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_mil1553btask(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_mil1553btask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass,
def write_mil1553btask(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_mil1553bin(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_mil1553bin(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_mil1553bout(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_mil1553bout(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_mil1553bin(object symbol, unsigned int user_mask, unsigned int user_offset,
# bool bypass, data):
def write_mil1553bin(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_mil1553bout(object symbol, unsigned int user_mask, unsigned int user_offset,
# bool bypass, data):
def write_mil1553bout(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef bit_march_test(unsigned long start_address, unsigned long end_address, unsigned char data_type,
def bit_march_test(arg1, arg2, arg3, arg4):
    return {'start_address': 0x0, 'end_address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef tuple reg_poke_nc(tuple address_datatype_data, hide_write=False):
def reg_poke_nc(arg1, arg2=False):
    return {'frame': 12345678, 'address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef tuple poke_nc(tuple address_datatype_data):
def poke_nc(arg):
    return {'frame': 12345678, 'address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef tuple peek_nc(tuple address_datatype):
def peek_nc(arg):
    return {'frame': 12345678, 'address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef tuple peek_c(unsigned long start_address, unsigned long end_address, unsigned char data_type):
def peek_c(arg1, arg2, arg3):
    return {'frame': 12345678, 'address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef tuple poke_c(unsigned long start_address, unsigned long end_address, unsigned long data,
# unsigned char data_type):
def poke_c(arg1, arg2, arg3, arg4):
    return {'frame': 12345678, 'start_address': 0x0, 'end_address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef inline set_symbolmask(unsigned char global_mask, unsigned char user_mask, unsigned char system_mask):
def set_symbolmask(arg1, arg2, arg3):
    pass


# cpdef inline dict read_ccdltask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_ccdltask(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_ccdltask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_ccdltask(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_ccdlin(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_ccdlin(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_ccdlin(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_ccdlin(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict read_ccdlout(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
def read_ccdlout(arg1, arg2, arg3, arg4):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef inline dict write_ccdlout(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
def write_ccdlout(arg1, arg2, arg3, arg4, arg5):
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef tuple download_from_file(str file_name):
def download_from_file(arg):
    return {'start_address': 0x0, 'end_address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef tuple find_checksum(unsigned long start_address, unsigned long end_address):
def find_checksum(arg1, arg2):
    return {'start_address': 0x0, 'end_address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef tuple upload_to_file(unsigned long start_address, unsigned long end_address, str file_name):
def upload_to_file(arg1, arg2, arg3):
    return {'start_address': 0x0, 'end_address': 0x0, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},


# cpdef dict verify_memory(unsigned long start_address, unsigned long end_address, str file_name):
def verify_memory(arg1, arg2, arg3):
    return {'start_address': 0x0, 'end_address': 0x0,
            'channels': [{'differences': {0x0: (0x0, 0x0)}, 'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},
                         {'differences': {0x0: (0x0, 0x0)}, 'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},
                         {'differences': {0x0: (0x0, 0x0)}, 'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)},
                         {'differences': {0x0: (0x0, 0x0)}, 'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}]}


# cpdef inline wait_for_transition():
def wait_for_transition():
    pass


# cpdef unsigned long get_frame_number():
def get_frame_number():
    return 12345678


# cpdef set_mask(unsigned char mask):
def set_mask(arg):
    pass


# cpdef read_spil():
def read_spil():
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# cpdef write_spil():
def write_spil():
    return {'unit': 'xxx', 'bypass': False, 'frame': 12345678, 'value': (0, 0, 0, 0),
            'status': (0x0 | 0, 0x0 | 0, 0x0 | 0, 0x0 | 0)}


# def prefetch_spil(list args):
def prefetch_spil(arg):
    pass


# def message_msgtype(msgid, bus):
def message_msgtype(arg1, arg2):
    return 0


# def message_rtaddr1(msgid, bus):
def message_rtaddr1(arg1, arg2):
    return 0


# def message_rtsubaddr1(msgid, bus):
def message_rtsubaddr1(arg1, arg2):
    return 0


# def message_rtaddr2(msgid, bus):
def message_rtaddr2(arg1, arg2):
    return 0


# def message_rtsubaddr2(msgid, bus):
def message_rtsubaddr2(arg1, arg2):
    return 0


# def message_wcntmcode(msgid, bus):
def message_wcntmcode(arg1, arg2):
    return 0


# def message_info(msgid, bus):
def message_info(arg1, arg2):
    return 0


# def message_msggap(msgid, bus):
def message_msggap(arg1, arg2):
    return 0


# def message_defined(msgid, bus):
def message_defined(arg1, arg2):
    return 0


# def init1553b(filename):
def init1553b(arg):
    return {'bus1': {'processed': False, 'messages': 0, 'frames': 0},
            'bus2': {'processed': False, 'messages': 0, 'frames': 0}}
