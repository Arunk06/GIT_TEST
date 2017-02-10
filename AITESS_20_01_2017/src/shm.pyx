# -*- coding: utf-8 -*-
#
# Package name		    : AITESS
# Module name		    : shm
# File name		        : shm_airdatse.pyx
# Usage			        : Handles interfacing to AIRDATS-E shared memory.
# Authors		        : Hari Kiran K (Sc), Venugopal R (Sc)
# Date of creation	    : N/A
#
# Modification history  :
#
# Mod1: hari on 30/03/2015
#       Shifted data masking code to a function and added SILC register
#       locations in DFCC as 16 bits
# Mod2: hari on 08/04/2015
#       RS422 negative value reading fix
#       TPR No. 20005 dated 11 Mar 2015 for AIRDATS-E
# Mod3: hari on 08/04/2015
#       SPIL bug fix and optimisation
# Mod4: hari on 08/04/2015
#       Added data masking function
# Mod5: hari on 08/04/2015
#       PBIT symbol update
# Mod6: hari on 06/01/2016
#       SPIL discrete data type mask bug fix
# Mod7: hari on 09/02/2016
#       Incorporation of download and upload for Motorola
#       S-Record file
# Mod8: hari on 04/01/2017
#       Platform independent data types for SPIL structure
# Mod9: hari on 18/01/2017
#       Added DFCC Mk1A and DFCC Mk2 masking and modified
#       and renamed the 'address_mask' function to
#       'apply_address_mask' which will return the masked
#       data instead of the mask

from cpython cimport bool
from libc.stdio cimport *

import os
import re
import tempfile
from ctypes import *
from time import sleep

import cfg
from cython.operator cimport dereference as deref
from time import time

include "settings.pyi"

# Dynamic configuration for ADC/LADC 21/11/2013
boot_message_addr = 0x1adc0000
model_map = {}
dev_map = {}
cards_per_cage = 0
g_exception = None  # Global exception for handling pure C function exceptions

IF XENOMAI_API:
    cimport posix.unistd as posix_unistd
    cimport posix.fcntl as posix_fcntl

    cdef extern from "sys/mman.h":
        enum: PROT_READ, PROT_WRITE, MAP_SHARED
        int shm_open(char *name, int oflag, posix_fcntl.mode_t mode)
        void *mmap(void *start, size_t length, int prot, int flags, int fd, posix_unistd.off_t offset)
        int munmap(void *start, size_t length)
ELSE:
    cdef extern from "mbuff.h":
        inline void *mbuff_alloc(char *name, int size)
        inline void mbuff_free(char *name, void *mbuf)

cdef extern from "string.h" nogil:
    void *memset(void *BLOCK, int C, size_t SIZE)

# Mod8: begin
cdef extern from "stdint.h":
    ctypedef int uint32_t
# Mod8: end

cdef extern from "module/include/common.h":
    pass

cdef extern from "module/include/mil1553_shmMod.h":
    ctypedef struct tagFRAMEDET:
        unsigned short FrameNo
        unsigned short NoOfMsgInFrame
        unsigned short RepeatCount
    ctypedef struct tagBCFRAMEDET:
        unsigned short FrameNo
        unsigned short NoOfMsgInFrame
        unsigned short RepeatCount
        unsigned short usFrameTime
    ctypedef struct tagRTSTRUCT:
        unsigned int RTAddress
        unsigned int SubAddr_ModeCode
        unsigned char Tx_Rx
        unsigned char WrdCnt_ModeCode
    ctypedef struct tagRTList:
        unsigned char ucNoOfRTs
        tagRTSTRUCT rtStruct[100]
        unsigned char simulated[100]
    ctypedef struct tagCTRLWRD:
        unsigned short RTtoRTFormat #     :1
        unsigned short BroadCastFormat #  :1
        unsigned short ModeCodeFormat #   :1
        unsigned short MIL_1553_A_B_Sel # :1
        unsigned short EOMIntEnable #     :1
        unsigned short MaskBroadCastBit # :1
        unsigned short OffLineSelfTest #  :1
        unsigned short BusChannelA_B #    :1
        unsigned short RetryEnabled #     :1
        unsigned short ReservedBitsMask # :1
        unsigned short TerminalFlagMask # :1
        unsigned short SubSysFlagMask #   :1
        unsigned short SubSysBusyMask #   :1
        unsigned short ServiceRqstMask #  :1
        unsigned short MsgErrorMask #     :1
        unsigned short Dummy #            :1
    ctypedef struct tagCMDWRD:
        unsigned short WrdCnt_ModeCode #  :5
        unsigned short SubAddr_ModeCode # :5
        unsigned short Tx_Rx #            :1
        unsigned short RTAddress #        :5

cdef extern from "module/include/spil_shmMod.h":
    enum: DATA_DWORD_COUNT, CMD_DWORD_COUNT, SPIL_MAX_BOARDS
    ctypedef struct STRUCT_SPIL_LTM:
        unsigned char ucFlag
    ctypedef struct STRUCT_DPRAM:
        # Mod8: begin
        uint32_t ulCmdSts
        uint32_t ulResSts
        uint32_t ulTransID
        uint32_t ulTransCnt
        uint32_t ulStartAddr
        uint32_t ulEndAddr
        uint32_t ulDType
        uint32_t ulData[DATA_DWORD_COUNT]
        uint32_t ulCommand[CMD_DWORD_COUNT]
        # Mod8: end
    ctypedef struct SPIL_SHMEM_OUT:
        STRUCT_DPRAM strDPRAM[SPIL_MAX_BOARDS]
    ctypedef struct SPIL_SHMEM_TASK:
        unsigned char ucFlag

IF AETS_ALL:
    cdef extern from "module/include/simproc_shmMod.h":
        enum: MAX_SIMPROC_BOARDS, MAX_APGIO_PER_SIMPROC_BOARD, MAX_AO_CHANNELS, MAX_DO_GROUPS, MAX_AI_CHANNELS, MAX_DI_GROUPS
        ctypedef struct SIMPROC_SHMEM_IN:
            unsigned short AI_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_AI_CHANNELS]
            unsigned char DI_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_DI_GROUPS]
        ctypedef struct SIMPROC_SHMEM_OUT:
            unsigned short AO_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_AO_CHANNELS]
            unsigned char DO_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_DO_GROUPS]
            unsigned short ModelCtrl
            unsigned short ConfigCtrl
ELSE:
    cdef extern from "module/include/simproc_shmMod.h":
        enum: MAX_SIMPROC_BOARDS, MAX_APGIO_PER_SIMPROC_BOARD, MAX_AO_CHANNELS, MAX_DO_GROUPS, MAX_AI_CHANNELS, MAX_DI_GROUPS
        ctypedef struct SIMPROC_SHMEM_IN:
            unsigned short AI_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_AI_CHANNELS]
            unsigned char DI_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_DI_GROUPS]
        ctypedef struct SIMPROC_SHMEM_OUT:
            unsigned short AO_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_AO_CHANNELS]
            unsigned char DO_Hex[MAX_SIMPROC_BOARDS][MAX_APGIO_PER_SIMPROC_BOARD][MAX_DO_GROUPS]
            unsigned short ModelCtrl

cdef extern from "module/include/ccdl_shmMod.h":
    enum: MAX_DFCC_CHANNELS, MAX_CCDL_WORDS
    ctypedef struct CCDL_SHMEM_IN:
        unsigned int CCDL_Hex[MAX_DFCC_CHANNELS][MAX_CCDL_WORDS]
    ctypedef struct CCDL_SHMEM_TASK:
        unsigned char CCDL_RX_ON

IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
    cdef extern from "module/include/dpfs_shmMod.h":
        enum: MEL_DPFS_CARDS, MEL_DPFS_CHANNELS
        ctypedef struct DPFS_SHMEM_OUT:
            float dDpfsValue[MEL_DPFS_CARDS * MEL_DPFS_CHANNELS]

IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
    cdef extern from "module/include/rs422_shmMod.h":
        enum: MAX_RS422_CHANNELS, MAX_RS422_IDS, MAX_RS422_BYTES, DOUBLE_BUFFER
        ctypedef struct RS422_SHMEM_IN:
            unsigned char RS422_Msg[MAX_RS422_CHANNELS][MAX_RS422_IDS][DOUBLE_BUFFER][MAX_RS422_BYTES]
        ctypedef struct RS422_SHMEM_OUT:
            unsigned char RS422_Msg[MAX_RS422_CHANNELS][MAX_RS422_IDS][DOUBLE_BUFFER][MAX_RS422_BYTES]
        ctypedef struct RS422_SHMEM_TASK:
            unsigned char TxON[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char TxChecksumBypass[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char TxMaxChannelIDs[MAX_RS422_CHANNELS]
            unsigned char RxMaxChannelIDs[MAX_RS422_CHANNELS]
            unsigned int BaudRate[MAX_RS422_CHANNELS]
            unsigned char DataBits[MAX_RS422_CHANNELS]
            unsigned char Parity[MAX_RS422_CHANNELS]
            unsigned char NumStopBits[MAX_RS422_CHANNELS]
            unsigned char TxFrameRate[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char TxFrameOffset[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char TxChksumAlgorithm[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char RxChksumAlgorithm[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char TxActiveBuffer[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char RxActiveBuffer[MAX_RS422_CHANNELS][MAX_RS422_IDS]
        ctypedef struct RS422_SHMEM_ERROR:
            unsigned long TxError[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned long RxCHECKSUM_Error[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned long RxDROPPED_PktsCount[MAX_RS422_CHANNELS][MAX_RS422_IDS]
ELIF AETS_EXC_MK1 or AETS_ALL:
    cdef extern from "module/include/rs422_shmMod.h":
        enum: MAX_RS422_CHANNELS, MAX_RS422_IDS, MAX_RS422_BYTES, DOUBLE_BUFFER
        ctypedef struct RS422_SHMEM_IN:
            unsigned char RS422_Msg[MAX_RS422_CHANNELS][MAX_RS422_IDS][DOUBLE_BUFFER][MAX_RS422_BYTES]
        ctypedef struct RS422_SHMEM_OUT:
            unsigned char RS422_Msg[MAX_RS422_CHANNELS][MAX_RS422_IDS][DOUBLE_BUFFER][MAX_RS422_BYTES]
        ctypedef struct RS422_SHMEM_TASK:
            unsigned char TxON[MAX_RS422_CHANNELS]
            unsigned char TxChecksumBypass[MAX_RS422_CHANNELS]
            unsigned int BaudRate[MAX_RS422_CHANNELS]
            unsigned char DataBits[MAX_RS422_CHANNELS]
            unsigned char Parity[MAX_RS422_CHANNELS]
            unsigned char NumStopBits[MAX_RS422_CHANNELS]
            unsigned char TxFrameRate[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char TxFrameOffset[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char ChksumAlgorithm[MAX_RS422_CHANNELS]
            unsigned char TxActiveBuffer[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned char RxActiveBuffer[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            char TxSingleFrame[MAX_RS422_CHANNELS]
            unsigned char RxCRCDisable[MAX_RS422_CHANNELS]
            unsigned char ChannelReset[MAX_RS422_CHANNELS]
        ctypedef struct RS422_SHMEM_ERROR:
            unsigned long TxError[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned long RxCHECKSUM_Error[MAX_RS422_CHANNELS][MAX_RS422_IDS]
            unsigned long RxDROPPED_PktsCount[MAX_RS422_CHANNELS][MAX_RS422_IDS]

IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
    cdef extern from "module/include/mil1553_shmMod.h":
        ctypedef struct MIL_1553_CONFIG_STRUCT:
            unsigned char message_type[2][512]
            unsigned char rt_tx_simulated[2][512]
            unsigned char rt_rx_simulated[2][512]
            tagCTRLWRD MessageControlWord[2][512]
            tagCMDWRD  BCMessageCommandWord1[2][512]
            tagCMDWRD  BCMessageCommandWord2[2][512]
            tagCMDWRD  RTMessageCommandWord1[2][512]
            tagCMDWRD  RTMessageCommandWord2[2][512]
            tagFRAMEDET RTMinorFrameStruct[2][512]
            tagBCFRAMEDET BCMinorFrameStruct[2][512]
            tagRTList RT_List[2]
            unsigned short MessageGapTime[2][512]
            unsigned char uc1553BConfigure[2]
            unsigned char uc1553BConfigured[2]
        ctypedef struct MIL_1553_SHMEM_TASK:
            MIL_1553_CONFIG_STRUCT config_struct
            int total_messages[2]
            int no_of_minor_frames[2]
            unsigned char primary_secondary_bus[2]
            unsigned char retry_enabled[2]
            unsigned char start[2]
            unsigned char stop[2]
        ctypedef struct MIL_1553_SHMEM_OUT:
            unsigned short bc_out[2][512][32]
            unsigned short rt_out[2][512][32]
        ctypedef struct MIL_1553_SHMEM_IN:
            unsigned short bc_in[2][512][32]
            unsigned short rt_in[2][512][32]
            unsigned short bc_status2_in[2][512]
ELIF AETS_EXC_MK1:
    cdef extern from "module/include/mil1553_shmMod.h":
        ctypedef struct MIL_1553_CONFIG_STRUCT:
            unsigned char message_type[2][512]
            unsigned char rt_tx_simulated[2][512]
            unsigned char rt_rx_simulated[2][512]
            tagCTRLWRD MessageControlWord[2][512]
            tagCMDWRD  BCMessageCommandWord1[2][512]
            tagCMDWRD  BCMessageCommandWord2[2][512]
            tagCMDWRD  RTMessageCommandWord1[2][512]
            tagCMDWRD  RTMessageCommandWord2[2][512]
            tagFRAMEDET RTMinorFrameStruct[2][512]
            tagBCFRAMEDET BCMinorFrameStruct[2][512]
            tagRTList RT_List[2]
            unsigned short MessageGapTime[2][512]
            unsigned char uc1553BConfigure[2]
            unsigned char uc1553BConfigured[2]
        ctypedef struct MIL_1553_SHMEM_TASK:
            MIL_1553_CONFIG_STRUCT config_struct
            int total_messages[2]
            int no_of_minor_frames[2]
            unsigned char primary_secondary_bus[2]
            unsigned char number_of_retries[2]
            unsigned char alternate_first_retry_bus[2]
            unsigned char alternate_second_retry_bus[2]
            unsigned char retry_enabled[2]
            unsigned short start[2]
            unsigned short stop[2]
            unsigned short read1553b[2]
            unsigned short bus_switched[2]
            # Mod5: begin
            unsigned char no_update[2]
            unsigned char no_errors[2]
            unsigned char mc_dfcc[2]
            unsigned char mc_mpru[2]
        # Mod5: end
        ctypedef struct MIL_1553_SHMEM_OUT:
            unsigned short bc_out[2][512][32]
            unsigned short rt_out[2][512][32]
        ctypedef struct MIL_1553_SHMEM_IN:
            unsigned short bc_in[2][512][32]
            unsigned short rt_in[2][512][32]
            unsigned short bc_status1_in[2][512]
            unsigned short bc_status2_in[2][512]
ELIF AETS_ALL:
    cdef extern from "module/include/mil1553_shmMod.h":
        enum: MIL_MSG_NO
        ctypedef struct MIL_1553_CONFIG_STRUCT:
            unsigned char message_type[2][MIL_MSG_NO]
            unsigned char rt_tx_simulated[2][MIL_MSG_NO]
            unsigned char rt_rx_simulated[2][MIL_MSG_NO]
            tagCTRLWRD MessageControlWord[2][MIL_MSG_NO]
            tagCMDWRD  BCMessageCommandWord1[2][MIL_MSG_NO]
            tagCMDWRD  BCMessageCommandWord2[2][MIL_MSG_NO]
            tagCMDWRD  RTMessageCommandWord1[2][MIL_MSG_NO]
            tagCMDWRD  RTMessageCommandWord2[2][MIL_MSG_NO]
            tagFRAMEDET RTMinorFrameStruct[2][MIL_MSG_NO]
            tagBCFRAMEDET BCMinorFrameStruct[2][MIL_MSG_NO]
            tagRTList RT_List[2]
            unsigned short MessageGapTime[2][MIL_MSG_NO]
            unsigned char uc1553BConfigure[2]
            unsigned char uc1553BConfigured[2]
        ctypedef struct MIL_1553_SHMEM_TASK:
            MIL_1553_CONFIG_STRUCT config_struct
            int total_messages[2]
            int no_of_minor_frames[2]
            unsigned char primary_secondary_bus[2]
            unsigned char number_of_retries[2]
            unsigned char alternate_first_retry_bus[2]
            unsigned char alternate_second_retry_bus[2]
            unsigned char retry_enabled[2]
            unsigned short start[2]
            unsigned short stop[2]
            unsigned short read1553b[2]
            unsigned short bus_switched[2]
            # Mod5: begin
            unsigned char no_update[2]
            unsigned char no_errors[2]
            unsigned char mc_dfcc[2]
            unsigned char mc_mpru[2]
        # Mod5: end
        ctypedef struct MIL_1553_SHMEM_OUT:
            unsigned short bc_out[2][MIL_MSG_NO][32]
            unsigned short rt_out[2][MIL_MSG_NO][32]
        ctypedef struct MIL_1553_SHMEM_IN:
            unsigned short bc_in[2][MIL_MSG_NO][32]
            unsigned short rt_in[2][MIL_MSG_NO][32]
            unsigned short bc_status1_in[2][MIL_MSG_NO]
            unsigned short bc_status2_in[2][MIL_MSG_NO]

IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
    cdef extern from "module/include/shmMod.h":
        ctypedef struct COMMON_SHMEM_TASK:
            unsigned char UUT_code
            unsigned long ulTaskIter
            unsigned char ucTaskFlag
        ctypedef struct SHMEM_IN:
            SIMPROC_SHMEM_IN simproc_in
            CCDL_SHMEM_IN ccdl_in
            RS422_SHMEM_IN rs422_in
            MIL_1553_SHMEM_IN mil1553_in
        ctypedef struct SHMEM_OUT:
            SPIL_SHMEM_OUT spil_out
            SIMPROC_SHMEM_OUT simproc_out
            DPFS_SHMEM_OUT dpfs_out
            RS422_SHMEM_OUT rs422_out
            MIL_1553_SHMEM_OUT mil1553_out
        ctypedef struct SHMEM_TASK:
            COMMON_SHMEM_TASK common_task
            SPIL_SHMEM_TASK spil_task
            CCDL_SHMEM_TASK ccdl_task
            RS422_SHMEM_TASK rs422_task
            MIL_1553_SHMEM_TASK mil1553_task
        ctypedef struct SHMEM_ERROR:
            RS422_SHMEM_ERROR rs422_error
ELSE:
    cdef extern from "module/include/shmMod.h":
        ctypedef struct COMMON_SHMEM_TASK:
            unsigned char UUT_code
            unsigned long ulTaskIter
            unsigned char ucTaskFlag
        ctypedef struct SHMEM_IN:
            SIMPROC_SHMEM_IN simproc_in
            CCDL_SHMEM_IN ccdl_in
            RS422_SHMEM_IN rs422_in
            MIL_1553_SHMEM_IN mil1553_in
        ctypedef struct SHMEM_OUT:
            SPIL_SHMEM_OUT spil_out
            SIMPROC_SHMEM_OUT simproc_out
            RS422_SHMEM_OUT rs422_out
            MIL_1553_SHMEM_OUT mil1553_out
        ctypedef struct SHMEM_TASK:
            COMMON_SHMEM_TASK common_task
            SPIL_SHMEM_TASK spil_task
            CCDL_SHMEM_TASK ccdl_task
            RS422_SHMEM_TASK rs422_task
            MIL_1553_SHMEM_TASK mil1553_task
        ctypedef struct SHMEM_ERROR:
            RS422_SHMEM_ERROR rs422_error

cdef public SHMEM_IN *GlobalSHM_in
cdef public SHMEM_OUT *GlobalSHM_out
cdef public SHMEM_TASK *GlobalSHM_task
cdef public SHMEM_ERROR *GlobalSHM_error
IF XENOMAI_API:
    cdef int GlobalSHM_in_fd
    cdef int GlobalSHM_out_fd
    cdef int GlobalSHM_task_fd
    cdef int GlobalSHM_error_fd

cdef unsigned char effective_mask[4]

msgid_map_bus1 = {}  # msgid : true_msgid
msgid_map_bus2 = {}  # msgid : true_msgid
message_map_bus1 = {}  # true_msgid
message_map_bus2 = {}  # true_msgid

bc_msgid_map_bus1 = {}  # msgid : true_msgid
bc_msgid_map_bus2 = {}  # msgid : true_msgid
bc_message_map_bus1 = {}  # true_msgid
bc_message_map_bus2 = {}  # true_msgid

cpdef init_apgio_dicts():
    global dev_map, cards_per_cage, boot_message_addr, model_map
    IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
        if cfg.config_file.is_configured_for_ADC():
            boot_message_addr = 0xadc00000
            dev_map = {'ae_aoa': 0, 'ae_dcm': 1, 'ae_disc1': 2}
            cards_per_cage = 3
        else:  # defaults to LADC
            boot_message_addr = 0x1adc0000
            dev_map = {'ae_aoa': 0, 'ae_dcm': 1, 'ae_disc1': 2, 'ae_disc2': 3, 'tqa': 4, 'rtlevcon': 5, 'ltlevcon': 6,
                       'unknown': 7}
            model_map = {'m_hyd': 0, 'm_lev': 1}
            cards_per_cage = 8
    ELIF AETS_EXC_MK1:
        boot_message_addr = 0xdfcc0000
        dev_map = {'rud': 0, 'lie': 1, 'loe': 2, 'rie': 3, 'roe': 4, 'lts': 5, 'rts': 6, 'aoa': 7, 'pcs': 8, 'adh': 9,
                   'asa': 10, 'gse': 11, 'amd': 12, 'guh': 13, 'rsa1': 14, 'rsa2': 15}
        model_map = {'m_hyd1': 0, 'm_hyd2': 1, 'm_rud': 0, 'm_lie': 1, 'm_loe': 2, 'm_rie': 3, 'm_roe': 4, 'm_lis': 5,
                     'm_lms': 6, 'm_los': 7, 'm_ris': 8, 'm_rms': 9, 'm_ros': 10, 'm_abr': 11, 'm_abl': 12}
        cards_per_cage = 8
    ELIF AETS_ALL:
        boot_message_addr = 0xdfcc0000
        dev_map = {'rud': 0, 'lie': 1, 'loe': 2, 'rie': 3, 'roe': 4, 'lts': 5, 'rts': 6, 'pcs': 7, 'aoa': 8, 'adh': 9,
                   'asa': 10, 'gse': 11, 'amd': 12, 'guh': 13, 'rsa1': 14, 'rsa2': 15, 'type12': 16, 'type13': 17,
                   'type14': 18, 'type15': 19}
        model_map = {'m_hyd1': 0, 'm_hyd2': 1, 'm_rud': 0, 'm_lie': 1, 'm_loe': 2, 'm_rie': 3, 'm_roe': 4, 'm_lis': 5,
                     'm_lms': 6, 'm_los': 7, 'm_ris': 8, 'm_rms': 9, 'm_ros': 10, 'm_abr': 11, 'm_abl': 12}
        cards_per_cage = 10

cdef inline read_transition_variable():
    return GlobalSHM_task[0].common_task.ucTaskFlag

cpdef clear_shm():
    memset(GlobalSHM_in, 0, sizeof(SHMEM_IN))
    memset(GlobalSHM_out, 0, sizeof(SHMEM_OUT))
    memset(GlobalSHM_task, 0, sizeof(SHMEM_TASK))
    memset(GlobalSHM_error, 0, sizeof(SHMEM_ERROR))

cpdef info_shm():
    return {"in": sizeof(SHMEM_IN), "out": sizeof(SHMEM_OUT), "task": sizeof(SHMEM_TASK), "error": sizeof(SHMEM_ERROR)}

IF XENOMAI_API:
    cpdef open_shm():
        global GlobalSHM_in_fd, GlobalSHM_out_fd, GlobalSHM_task_fd, GlobalSHM_error_fd
        global GlobalSHM_in, GlobalSHM_out, GlobalSHM_task, GlobalSHM_error
        status = {"in": True, "out": True, "task": True, "error": True}

        GlobalSHM_in_fd = shm_open("/SHM_IN", posix_fcntl.O_CREAT | posix_fcntl.O_RDWR, 0777)
        if GlobalSHM_in_fd == -1:
            status["in"] = False

        if posix_unistd.ftruncate(GlobalSHM_in_fd, sizeof(SHMEM_IN)):
            status["in"] = False

        GlobalSHM_in = <SHMEM_IN *> mmap(<void *> 0, sizeof(SHMEM_IN), PROT_READ | PROT_WRITE, MAP_SHARED,
                                         GlobalSHM_in_fd, 0)
        if GlobalSHM_in == <void *> -1:
            status["in"] = False

        GlobalSHM_out_fd = shm_open("/SHM_OUT", posix_fcntl.O_CREAT | posix_fcntl.O_RDWR, 0777)
        if GlobalSHM_out_fd == -1:
            status["out"] = False

        if posix_unistd.ftruncate(GlobalSHM_out_fd, sizeof(SHMEM_OUT)):
            status["out"] = False

        GlobalSHM_out = <SHMEM_OUT *> mmap(<void *> 0, sizeof(SHMEM_OUT), PROT_READ | PROT_WRITE, MAP_SHARED,
                                           GlobalSHM_out_fd, 0)
        if GlobalSHM_out == <void *> -1:
            status["out"] = False

        GlobalSHM_task_fd = shm_open("/SHM_TASK", posix_fcntl.O_CREAT | posix_fcntl.O_RDWR, 0777)
        if GlobalSHM_task_fd == -1:
            status["task"] = False

        if posix_unistd.ftruncate(GlobalSHM_task_fd, sizeof(SHMEM_TASK)):
            status["task"] = False

        GlobalSHM_task = <SHMEM_TASK *> mmap(<void *> 0, sizeof(SHMEM_TASK), PROT_READ | PROT_WRITE, MAP_SHARED,
                                             GlobalSHM_task_fd, 0)
        if GlobalSHM_task == <void *> -1:
            status["task"] = False

        GlobalSHM_error_fd = shm_open("/SHM_ERROR", posix_fcntl.O_CREAT | posix_fcntl.O_RDWR, 0777)
        if GlobalSHM_error_fd == -1:
            status["error"] = False

        if posix_unistd.ftruncate(GlobalSHM_error_fd, sizeof(SHMEM_ERROR)):
            status["error"] = False

        GlobalSHM_error = <SHMEM_ERROR *> mmap(<void *> 0, sizeof(SHMEM_ERROR), PROT_READ | PROT_WRITE, MAP_SHARED,
                                               GlobalSHM_error_fd, 0)
        if GlobalSHM_error == <void *> -1:
            status["error"] = False

        return status

    cpdef close_shm():
        global GlobalSHM_in_fd, GlobalSHM_out_fd, GlobalSHM_task_fd, GlobalSHM_error_fd
        global GlobalSHM_in, GlobalSHM_out, GlobalSHM_task, GlobalSHM_error

        munmap(GlobalSHM_in, sizeof(SHMEM_IN))
        posix_unistd.close(GlobalSHM_in_fd)

        munmap(GlobalSHM_out, sizeof(SHMEM_OUT))
        posix_unistd.close(GlobalSHM_out_fd)

        munmap(GlobalSHM_task, sizeof(SHMEM_TASK))
        posix_unistd.close(GlobalSHM_task_fd)

        munmap(GlobalSHM_error, sizeof(SHMEM_ERROR))
        posix_unistd.close(GlobalSHM_error_fd)
ELSE:
    cpdef open_shm():
        global GlobalSHM_in, GlobalSHM_out, GlobalSHM_task, GlobalSHM_error
        status = {"in": True, "out": True, "task": True, "error": True}

        GlobalSHM_in = <SHMEM_IN *> mbuff_alloc("GlobalSHM_in", sizeof(SHMEM_IN))
        GlobalSHM_out = <SHMEM_OUT *> mbuff_alloc("GlobalSHM_out", sizeof(SHMEM_OUT))
        GlobalSHM_task = <SHMEM_TASK *> mbuff_alloc("GlobalSHM_task", sizeof(SHMEM_TASK))
        GlobalSHM_error = <SHMEM_ERROR *> mbuff_alloc("GlobalSHM_error", sizeof(SHMEM_ERROR))

        if not GlobalSHM_in:
            status["in"] = False
        if not GlobalSHM_out:
            status["out"] = False
        if not GlobalSHM_task:
            status["task"] = False
        if not GlobalSHM_error:
            status["error"] = False

        return status

    cpdef close_shm():
        global GlobalSHM_in, GlobalSHM_out, GlobalSHM_task, GlobalSHM_error

        mbuff_free("GlobalSHM_in", <void *> GlobalSHM_in)
        mbuff_free("GlobalSHM_out", <void *> GlobalSHM_out)
        mbuff_free("GlobalSHM_task", <void *> GlobalSHM_task)
        mbuff_free("GlobalSHM_error", <void *> GlobalSHM_error)

cpdef set_UUT(unsigned char UUT_code):
    GlobalSHM_task[0].common_task.UUT_code = UUT_code

cdef inline float u32toffp(unsigned long value):
    return deref(<float *> &value)

cdef inline ffptou32(float value):
    return deref(<unsigned long *> &value)

cdef inline unsigned long rs422_extract_disc(unsigned long value, unsigned long mask):
    bit_select = 0b10000000000000000000000000000000
    pos = 31
    result = 0

    for count in xrange(1, 33):
        if bit_select & mask:
            result <<= 1
            result |= (value & bit_select) >> pos
        bit_select >>= 1
        pos -= 1

    return result

cdef inline d8tou8(unsigned long value, unsigned long mask, unsigned long data):
    return rs422_set_disc(value, mask, data) & 0xFF

cdef inline d16tou16(unsigned long value, unsigned long mask, unsigned long data):
    return rs422_set_disc(value, mask, data) & 0xFFFF

cdef inline d32tou32(unsigned long value, unsigned long mask, unsigned long data):
    return rs422_set_disc(value, mask, data) & 0xFFFFFFFF

cdef inline unsigned long rs422_set_disc(unsigned long value, unsigned long mask, unsigned long data):
    bit_select = 0b000000000000000000000001
    data_select = 0b000000000000000000000001
    pos = 0
    result = 0

    for count in xrange(1, 33):
        if bit_select & mask:
            if data & data_select:
                result |= 1 << pos
            data_select <<= 1
        else:
            result |= (value & bit_select)

        bit_select <<= 1
        pos += 1

    return result

# Mod2: begin
cpdef RS422_LHS_type_cast(type_code, mask, value):
    # assigning to 'v' caused problem when value is 'unused' in SPIL symbols
    if (type(value) is str) and (value == 'unused'):
        return value

    cdef unsigned int v = value

    if (type(value) in (int, long)) and ((type_code == 'u32') or (type_code == 'dword')):
        return deref(<unsigned int *> &v)
    elif (type(value) in (int, long)) and (type_code == 'u24'):
        return deref(<unsigned int *> &v)
    elif (type(value) in (int, long)) and ((type_code == 'u16') or (type_code == 'word')):
        return deref(<unsigned short *> &v)
    elif (type(value) in (int, long)) and ((type_code == 'u8') or (type_code == 'byte')):
        return deref(<unsigned char *> &v)
    elif (type(value) in (int, long, float)) and ((type_code == 's32') or (type_code == 'dpi')):
        return deref(<signed int *> &v)
    elif (type(value) in (int, long, float)) and (type_code == 's24'):
        return deref(<signed int *> &v)
    elif (type(value) in (int, long, float)) and ((type_code == 's16') or (type_code == 'spi')):
        return deref(<signed short *> &v)
    elif (type(value) in (int, long, float)) and (type_code == 's8'):
        return deref(<signed char *> &v)
    elif (type(value) in (int, long)) and (type_code == 'd32'):
        return rs422_extract_disc(value, mask) & 0xFFFFFFF
    elif (type(value) in (int, long)) and (type_code == 'd16'):
        return rs422_extract_disc(value, mask) & 0xFFFF
    elif (type(value) in (int, long)) and (type_code == 'd8'):
        return rs422_extract_disc(value, mask) & 0xFF
    elif (type(value) is str) and (value == 'unused'):
        return value
    else:
        raise AttributeError("%s is an invalid LHS type for RS422" % (str(type(value)).split("'")[1]))
# Mod2: end

cpdef RS422_RHS_type_cast(type_code, mask, value):
    if (type(value) in (int, long, float)) and ((type_code == 'u32') or (type_code == 'dword')):
        return c_uint(<unsigned int> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and (type_code == 'u24'):
        return c_uint(<unsigned int> value).value & 0xFFFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 'u16') or (type_code == 'word')):
        return c_ushort(<unsigned short> value).value & 0xFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 'u8') or (type_code == 'byte')):
        return c_ubyte(<unsigned char> value).value & 0xFF
    elif (type(value) in (int, long, float)) and ((type_code == 's32') or (type_code == 'dpi')):
        return c_int(<signed int> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and (type_code == 's24'):
        return c_int(<signed int> value).value & 0xFFFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 's16') or (type_code == 'spi')):
        return c_short(<signed short> value).value & 0xFFFF
    elif (type(value) in (int, long, float)) and (type_code == 's8'):
        return c_byte(<signed char> value).value & 0xFF
    elif (type(value) in (int, long, float)) and (type_code == 'd32'):
        return c_uint(<unsigned int> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and (type_code == 'd16'):
        return c_ushort(<unsigned short> value).value & 0xFFFF
    elif (type(value) in (int, long, float)) and (type_code == 'd8'):
        return c_ubyte(<unsigned char> value).value & 0xFF
    else:
        raise AttributeError("%s is an invalid RHS type for RS422" % (str(type(value)).split("'")[1]))

cdef LHS_type_cast(str type_code, value):
    # assigning to 'v' caused problem when value is 'unused' in SPIL symbols
    if (type(value) is str) and (value == 'unused'):
        return value

    cdef unsigned int v = value

    if (type(value) in (int, long)) and ((type_code == 'u32') or (type_code == 'dword')):
        return deref(<unsigned int *> &v)
    elif (type(value) in (int, long)) and ((type_code == 'u16') or (type_code == 'word')):
        return deref(<unsigned short *> &v)
    elif (type(value) in (int, long)) and ((type_code == 'u8') or (type_code == 'byte')):
        return deref(<unsigned char *> &v)
    elif (type(value) in (int, long)) and ((type_code == 's32') or (type_code == 'dpi')):
        return deref(<signed int *> &v)  #short *>&v) #bug fix 08/05/2013 dpi value problem
    elif (type(value) in (int, long)) and ((type_code == 's16') or (type_code == 'spi')):
        return deref(<signed short *> &v)
    elif (type(value) in (int, long)) and ((type_code == 's8') or (type_code == 'ssi')):
        return deref(<signed char *> &v)
    elif (type(value) in (int, long)) and (type_code == 'd32'):
        return c_uint(value & 0xFFFFFFFF).value
    elif (type(value) in (int, long)) and (type_code == 'd16'):
        return c_ushort(value & 0xFFFF).value
    elif (type(value) in (int, long)) and (type_code == 'd8'):
        return c_ubyte(value & 0xFF).value
    elif (type(value) in (int, long)) and (type_code == 'ffp'):
        return u32toffp(value)
    else:
        raise AttributeError("%s is an invalid LHS type" % (str(type(value)).split("'")[1]))

cdef RHS_type_cast(str type_code, value):
    if (type(value) in (int, long, float)) and ((type_code == 'u32') or (type_code == 'dword')):
        return c_uint(<unsigned int> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 'u16') or (type_code == 'word')):
        return c_uint(<unsigned short> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 'u8') or (type_code == 'byte')):
        return c_uint(<unsigned char> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 's32') or (type_code == 'dpi')):
        return c_uint(<signed int> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 's16') or (type_code == 'spi')):
        return c_uint(<signed short> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and ((type_code == 's8') or (type_code == 'ssi')):
        return c_uint(<signed char> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and (type_code == 'd32'):
        return c_uint(<unsigned int> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and (type_code == 'd16'):
        return c_uint(<unsigned short> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and (type_code == 'd8'):
        return c_uint(<unsigned char> value).value & 0xFFFFFFFF
    elif (type(value) in (int, long, float)) and (type_code == 'ffp'):
        return ffptou32(float(value))
    else:
        raise AttributeError("%s is an invalid RHS type" % (str(type(value)).split("'")[1]))

cpdef unsigned short ffptooffsetbinary(str stype, value) except *:
    try:
        if (stype == 'ai') or (stype == 'ao'):
            return value * 3276.7 + 32768
        else:
            return value
    except BaseException as e:
        global g_exception
        g_exception = e

cpdef offsetbinarytoffp(stype, value):
    if (type(value) is str) and (value == 'unused'):
        return value
    elif (stype == 'ai') or (stype == 'ao'):
        return value / 3276.8 - 10.0
    else:
        return value

cpdef applyslopeandbiasread(value, slope, bias, stype):
    if (type(value) is str) and (value == 'unused'):
        return value
    elif (stype == 'ai') or (stype == 'ao'):
        return (value - bias) / slope
    else:
        IF COMPLEMENTING:
            return (value + bias) & slope
        ELSE:
            return value

cpdef applyslopeandbiaswrite(value, slope, bias, stype):
    if (stype == 'ai') or (stype == 'ao'):
        return value * slope + bias
    else:
        IF COMPLEMENTING:
            return (value + bias) & slope
        ELSE:
            return value

cpdef inline check_range(bypass, min_, max_, value):
    range_status = 0x0000

    if value == 'unused':
        return range_status

    if not bypass:
        if value < min_:
            range_status = 0x0100

        if value > max_:
            range_status = 0x100

    return range_status

cdef inline bring_to_range(bypass, min_, max_, value):
    sanitized_value = value
    correction_status = 0x0000

    if not bypass:
        if value < min_:
            sanitized_value = min_
            correction_status = 0x0100

        if value > max_:
            sanitized_value = max_
            correction_status = 0x100

    return sanitized_value, correction_status

###############################################SIMPROC-BEGIN#############################################################
cdef inline void write_simproc_ai(unsigned int simproc_number, unsigned int apgio_number, unsigned int channel,
                                  unsigned short data):
    GlobalSHM_in[0].simproc_in.AI_Hex[simproc_number][apgio_number][channel - 1] = data

cdef inline void write_simproc_di(unsigned int simproc_number, unsigned int apgio_number, unsigned int channel,
                                  unsigned char data):
    GlobalSHM_in[0].simproc_in.DI_Hex[simproc_number][apgio_number][channel - 1] = data

cdef inline void write_simproc_ao(unsigned int simproc_number, unsigned int apgio_number, unsigned int channel,
                                  unsigned short data):
    GlobalSHM_out[0].simproc_out.AO_Hex[simproc_number][apgio_number][channel - 1] = data

cdef inline void write_simproc_do(unsigned int simproc_number, unsigned int apgio_number, unsigned int channel,
                                  unsigned char data):
    GlobalSHM_out[0].simproc_out.DO_Hex[simproc_number][apgio_number][channel - 1] = data

cdef inline unsigned short read_simproc_ai(unsigned int simproc_number, unsigned int apgio_number,
                                           unsigned int channel):
    return GlobalSHM_in[0].simproc_in.AI_Hex[simproc_number][apgio_number][channel - 1]

cdef inline unsigned char read_simproc_di(unsigned int simproc_number, unsigned int apgio_number, unsigned int channel):
    return GlobalSHM_in[0].simproc_in.DI_Hex[simproc_number][apgio_number][channel - 1]

cdef inline unsigned short read_simproc_ao(unsigned int simproc_number, unsigned int apgio_number,
                                           unsigned int channel):
    return GlobalSHM_out[0].simproc_out.AO_Hex[simproc_number][apgio_number][channel - 1]

cdef inline unsigned char read_simproc_do(unsigned int simproc_number, unsigned int apgio_number, unsigned int channel):
    return GlobalSHM_out[0].simproc_out.DO_Hex[simproc_number][apgio_number][channel - 1]

cdef inline void write_simproc_model_ctrl(unsigned int model_number, unsigned short data):
    GlobalSHM_out[0].simproc_out.ModelCtrl = data

cdef inline unsigned short read_simproc_model_ctrl(unsigned int model_number):
    return GlobalSHM_out[0].simproc_out.ModelCtrl

IF AETS_ALL:
    cdef inline void write_simproc_config_ctrl(unsigned int model_number, unsigned short data):
        GlobalSHM_out[0].simproc_out.ConfigCtrl = data

    cdef inline unsigned short read_simproc_config_ctrl(unsigned int model_number):
        return GlobalSHM_out[0].simproc_out.ConfigCtrl

cdef inline unsigned short extract_word(unsigned short value, unsigned short mask):
    bit_select = 0b1000000000000000
    pos = 15
    result = 0

    for count in xrange(1, 17):
        if bit_select & mask:
            result <<= 1
            result |= (value & bit_select) >> pos

        bit_select >>= 1
        pos -= 1

    return result

cdef inline unsigned short set_word(unsigned short value, unsigned short mask, unsigned short data):
    bit_select = 0b0000000000000001
    data_select = 0b0000000000000001
    pos = 0
    result = 0

    for count in xrange(1, 17):
        if bit_select & mask:
            if data & data_select:
                result |= 1 << pos

            data_select <<= 1
        else:
            result |= (value & bit_select)

        bit_select <<= 1
        pos += 1

    return result

cdef inline unsigned char extract_byte(unsigned char value, unsigned char mask):
    bit_select = 0b10000000
    pos = 7
    result = 0

    for count in xrange(1, 9):
        if bit_select & mask:
            result <<= 1
            result |= (value & bit_select) >> pos

        bit_select >>= 1
        pos -= 1

    return result

cdef inline unsigned char set_byte(unsigned char value, unsigned char mask, unsigned char data):
    bit_select = 0b00000001
    data_select = 0b00000001
    pos = 0
    result = 0

    for count in xrange(1, 9):
        if bit_select & mask:
            if data & data_select:
                result |= 1 << pos
            data_select <<= 1
        else:
            result |= (value & bit_select)

        bit_select <<= 1
        pos += 1

    return result

cpdef inline tuple boot():
    cdef unsigned long frame_number
    cdef list result, status

    offset = [1, 2, 4, 6]
    mask = [0x2, 0x80, 0x20, 0x8]

    frame_number = get_frame_number()

    result = ["unused", "unused", "unused", "unused"]
    status = [0x0, 0x0, 0x0, 0x0]

    wait_for_transition()
    for chan in xrange(0, 4):
        if channel_enabled(chan + 1):
            v = read_simproc_do(0, 2, offset[chan])
            v = set_byte(v, mask[chan], 0)
            write_simproc_do(0, 2, offset[chan], v)

    wait_for_transition()
    for chan in xrange(0, 4):
        if channel_enabled(chan + 1):
            v = read_simproc_do(0, 2, offset[chan])
            v = set_byte(v, mask[chan], 1)
            write_simproc_do(0, 2, offset[chan], v)

    wait_for_transition()
    for chan in xrange(0, 4):
        if channel_enabled(chan + 1):
            result[chan] = "booted"
            v = read_simproc_do(0, 2, offset[chan])
            v = set_byte(v, mask[chan], 0)
            write_simproc_do(0, 2, offset[chan], v)

    return {'frame': frame_number, 'start_address': boot_message_addr + 0xb, 'end_address': boot_message_addr + 0xe,
            'value': tuple(result), 'status': tuple(status)},

cpdef inline dict write_simproc(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    global g_exception
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    if not bypass:
        data = applyslopeandbiaswrite(data, symbol.get_slpe(), symbol.get_bias(), symbol.get_stype())
        data = ffptooffsetbinary(symbol.get_stype(), data)
        if g_exception:
            e = g_exception
            g_exception = None
            raise MemoryError(e)

    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    cdef subsystem = symbol.get_subsystem()
    cdef stype = symbol.get_stype()
    if (stype == 'do') or (stype == 'di') or (stype == 'mdlctrl'):
        mask = [symbol.get_mask1(), symbol.get_mask2(), symbol.get_mask3(), symbol.get_mask4()]

    frame_number = get_frame_number()

    if stype == 'mdlctrl':
        try:
            model_id = model_map[subsystem]
        except KeyError:
            raise MemoryError("Unknown model for active UUT")
    else:
        try:
            master_id = dev_map[subsystem] / cards_per_cage
            slave_id = dev_map[subsystem] % cards_per_cage
        except KeyError:
            raise MemoryError("Unknown device for active UUT")

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if stype == 'ai':
                write_simproc_ai(master_id, slave_id, offset[channel - 1], data)
            if stype == 'ao':
                write_simproc_ao(master_id, slave_id, offset[channel - 1], data)
            if stype == 'di':
                if not bypass:
                    value[channel - 1] = read_simproc_di(master_id, slave_id, offset[channel - 1])
                    value[channel - 1] = set_byte(value[channel - 1], mask[channel - 1], data)
                else:
                    value[channel - 1] = data
                write_simproc_di(master_id, slave_id, offset[channel - 1], value[channel - 1])
            if stype == 'do':
                # read
                # offset specifies the byte of which the discret belongs to and mask specifies the bit(s)
                # mask = 1 (first bit), 2 (second), 4 (third), 8(fourth), 10(fifth), 20(sixth), 40(seventh), 80(eighth)
                # mask = 3 (first & second), 7(first & second & third) and so on ...
                if not bypass:
                    value[channel - 1] = read_simproc_do(master_id, slave_id, offset[channel - 1])
                    value[channel - 1] = set_byte(value[channel - 1], mask[channel - 1], data)
                else:
                    value[channel - 1] = data
                write_simproc_do(master_id, slave_id, offset[channel - 1], value[channel - 1])
            if stype == 'mdlctrl':
                if not bypass:
                    value[channel - 1] = read_simproc_model_ctrl(model_id)
                    value[channel - 1] = set_word(value[channel - 1], mask[channel - 1], data)
                else:
                    value[channel - 1] = data
                write_simproc_model_ctrl(model_id, value[channel - 1])
            IF AETS_ALL:
                if stype == 'cfgctrl':
                    if not bypass:
                        value[channel - 1] = read_simproc_config_ctrl(model_id)
                        value[channel - 1] = set_word(value[channel - 1], mask[channel - 1], data)
                    else:
                        value[channel - 1] = data
                    write_simproc_config_ctrl(model_id, value[channel - 1])

            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict read_simproc(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    cdef subsystem = symbol.get_subsystem()
    cdef stype = symbol.get_stype()

    if (stype == 'do') or (stype == 'di') or (stype == 'mdlctrl'):
        mask = [symbol.get_mask1(), symbol.get_mask2(), symbol.get_mask3(), symbol.get_mask4()]

    frame_number = get_frame_number()

    if stype == 'mdlctrl':
        try:
            model_id = model_map[subsystem]
        except KeyError:
            raise MemoryError("Unknown model for active UUT")
    else:
        try:
            master_id = dev_map[subsystem] / cards_per_cage
            slave_id = dev_map[subsystem] % cards_per_cage
        except KeyError:
            raise MemoryError("Unknown device for active UUT")

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if stype == 'ai':
                value[channel - 1] = read_simproc_ai(master_id, slave_id, offset[channel - 1])
            if stype == 'ao':
                value[channel - 1] = read_simproc_ao(master_id, slave_id, offset[channel - 1])
            if stype == 'di':
                value[channel - 1] = read_simproc_di(master_id, slave_id, offset[channel - 1])
                if not bypass:
                    value[channel - 1] = extract_byte(value[channel - 1], mask[channel - 1])
            if stype == 'do':
                value[channel - 1] = read_simproc_do(master_id, slave_id, offset[channel - 1])
                if not bypass:
                    value[channel - 1] = extract_byte(value[channel - 1], mask[channel - 1])
            if stype == 'mdlctrl':
                value[channel - 1] = read_simproc_model_ctrl(model_id)
                if not bypass:
                    value[channel - 1] = extract_word(value[channel - 1], mask[channel - 1])
            IF AETS_ALL:
                if stype == 'cfgctrl':
                    value[channel - 1] = read_simproc_config_ctrl(model_id)
                    if not bypass:
                        value[channel - 1] = extract_word(value[channel - 1], mask[channel - 1])

    if not bypass:
        value = map(offsetbinarytoffp, [symbol.get_stype() for i in xrange(4)], value)
        value = map(applyslopeandbiasread, value, [symbol.get_slpe() for i in xrange(4)],
                    [symbol.get_bias() for i in xrange(4)], [symbol.get_stype() for i in xrange(4)])

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

###############################################SIMPROC-END#############################################################

cdef inline void spil_rt_begin():
    GlobalSHM_task[0].spil_task.ucFlag = 1

cdef inline void write_dpram_data(unsigned int uiBoardNo, unsigned long ulAddress, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulData[ulAddress] = ulData

cdef inline unsigned long read_dpram_data(unsigned int uiBoardNo, unsigned long ulAddress):
    return GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulData[ulAddress]

cdef inline void write_dpram_start_address(unsigned int uiBoardNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulStartAddr = ulData

cdef inline void write_dpram_end_address(unsigned int uiBoardNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulEndAddr = ulData

cdef inline void write_dpram_transaction_id(unsigned int uiBoardNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulTransID = ulData

cdef inline void write_dpram_transaction_count(unsigned int uiBoardNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulTransCnt = ulData

cdef inline void write_dpram_command_status(unsigned int uiBoardNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulCmdSts = ulData

cdef inline unsigned long read_dpram_command_status(unsigned int uiBoardNo):
    return GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulCmdSts

cdef inline unsigned long read_dpram_response_status(unsigned int uiBoardNo):
    return GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulResSts

cdef inline void write_dpram_data_type(unsigned int uiBoardNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulDType = ulData

cdef inline void write_dpram_command_area_address(unsigned int uiBoardNo, unsigned int uiTransNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulCommand[0x0 + (uiTransNo - 1) * 0x4] = ulData

cdef inline void write_dpram_command_area_data_type(unsigned int uiBoardNo, unsigned int uiTransNo,
                                                    unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulCommand[0x01 + (uiTransNo - 1) * 0x4] = ulData

cdef inline void write_dpram_command_area_data(unsigned int uiBoardNo, unsigned int uiTransNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulCommand[0x02 + (uiTransNo - 1) * 0x4] = ulData

cdef inline void write_dpram_command_area_mask(unsigned int uiBoardNo, unsigned int uiTransNo, unsigned long ulData):
    GlobalSHM_out[0].spil_out.strDPRAM[uiBoardNo - 1].ulCommand[0x03 + (uiTransNo - 1) * 0x4] = ulData

cdef inline void spil_nrt_begin():
    GlobalSHM_task[0].spil_task.ucFlag = 3

cpdef dict active_buffer_lookup = {}

cpdef inline reset_active_buffer_lookup():
    global active_buffer_lookup
    active_buffer_lookup = {}

cpdef inline unsigned char get_active_buffer_lookup(unsigned char channel, unsigned char id_):
    global active_buffer_lookup
    if active_buffer_lookup.has_key((channel, id_)):
        return active_buffer_lookup[(channel, id_)]
    else:
        # Active buffer for read/write from AITESS is the inactive buffer for kernel module
        buffer_ = GlobalSHM_task[0].rs422_task.RxActiveBuffer[channel][id_] ^ 1
        active_buffer_lookup[(channel, id_)] = buffer_
        return buffer_

cpdef inline set_active_buffer(unsigned char channel, unsigned char id_, unsigned char buffer_):
    GlobalSHM_task[0].rs422_task.TxActiveBuffer[channel][id_] = buffer_

cpdef inline unsigned char get_active_buffer(unsigned char channel, unsigned char id_):
    return GlobalSHM_task[0].rs422_task.TxActiveBuffer[channel][id_]

# 1553B writers
IF AETS_EXC_MK1 or AETS_ALL:
    # Mod5: begin
    cdef write_no_update(unsigned short bus, unsigned char value):
        GlobalSHM_task[0].mil1553_task.no_update[bus - 1] = value

    cdef write_no_errors(unsigned short bus, unsigned char value):
        GlobalSHM_task[0].mil1553_task.no_errors[bus - 1] = value

    cdef write_mc_dfcc(unsigned short bus, unsigned char value):
        GlobalSHM_task[0].mil1553_task.mc_dfcc[bus - 1] = value

    cdef write_mc_mpru(unsigned short bus, unsigned char value):
        GlobalSHM_task[0].mil1553_task.mc_mpru[bus - 1] = value
    # Mod5: end

    cdef switch_1553channels(unsigned short bus, unsigned short channel):
        GlobalSHM_task[0].mil1553_task.primary_secondary_bus[bus - 1] = int(channel)  # 0 = A, 1 = B
        for msgid in range(MIL_MSG_NO):  # switching maximum, where is the actual number of message IDs stored?
            GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid].BusChannelA_B = int(
                not channel)  # 1 = A, 0 = B
        GlobalSHM_task[0].mil1553_task.bus_switched[bus - 1] = 1

    cdef set_read1553b(unsigned short bus, unsigned short value):
        GlobalSHM_task[0].mil1553_task.read1553b[bus - 1] = value

    cdef inline unsigned short write_1553_task_start(unsigned short bus, unsigned short value):
        GlobalSHM_task[0].mil1553_task.start[bus - 1] = value

    cdef inline unsigned short write_1553_task_stop(unsigned short bus, unsigned short value):
        # Hari: Uma's requirement on 16/03/2015
        #GlobalSHM_task[0].mil1553_task.stop[bus - 1] = value
        if value == 0:
            GlobalSHM_task[0].mil1553_task.start[bus - 1] = 1
        else:
            GlobalSHM_task[0].mil1553_task.stop[bus - 1] = value
ELIF AIRDATS_E_MK1 or AIRDATS_E_MK2:
    cdef inline unsigned char write_1553_task_start(unsigned short bus, unsigned char value):
        GlobalSHM_task[0].mil1553_task.start[bus - 1] = value

    cdef inline unsigned char write_1553_task_stop(unsigned short bus, unsigned char value):
        GlobalSHM_task[0].mil1553_task.stop[bus - 1] = value

cdef inline write_bc_in(unsigned short bus, unsigned int message_index, unsigned int word_index, unsigned short value):
    GlobalSHM_in[0].mil1553_in.bc_in[bus - 1][message_index - 1][word_index - 1] = value

cdef inline write_bc_out(unsigned short bus, unsigned int message_index, unsigned int word_index, unsigned short value):
    GlobalSHM_out[0].mil1553_out.bc_out[bus - 1][message_index - 1][word_index - 1] = value

cdef inline write_rt_in(unsigned short bus, unsigned int message_index, unsigned int word_index, unsigned short value):
    GlobalSHM_in[0].mil1553_in.rt_in[bus - 1][message_index - 1][word_index - 1] = value

cdef inline write_rt_out(unsigned short bus, unsigned int message_index, unsigned int word_index, unsigned short value):
    GlobalSHM_out[0].mil1553_out.rt_out[bus - 1][message_index - 1][word_index - 1] = value

# 1553B readers
IF AETS_EXC_MK1 or AETS_ALL:
    # Mod6: begin
    cdef unsigned char read_no_update(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.no_update[bus - 1]

    cdef unsigned char read_no_errors(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.no_errors[bus - 1]

    cdef unsigned char read_mc_dfcc(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.mc_dfcc[bus - 1]

    cdef unsigned char read_mc_mpru(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.mc_mpru[bus - 1]
    # Mod6: end

    cdef unsigned char read_switch_1553channels(unsigned short bus):
        return int(GlobalSHM_task[0].mil1553_task.primary_secondary_bus[bus - 1])  # 0 = A, 1 = B

    cdef unsigned short read_read1553b(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.read1553b[bus - 1]

    cdef inline unsigned short read_1553_task_start(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.start[bus - 1]

    cdef inline unsigned short read_1553_task_stop(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.stop[bus - 1]
ELIF AIRDATS_E_MK1 or AIRDATS_E_MK2:
    cdef inline unsigned char read_1553_task_start(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.start[bus - 1]

    cdef inline unsigned char read_1553_task_stop(unsigned short bus):
        return GlobalSHM_task[0].mil1553_task.stop[bus - 1]

cdef inline unsigned short read_bc_in(unsigned short bus, unsigned int message_index, unsigned int word_index):
    return GlobalSHM_in[0].mil1553_in.bc_in[bus - 1][message_index - 1][word_index - 1]

cdef inline unsigned short read_bc_out(unsigned short bus, unsigned int message_index, unsigned int word_index):
    return GlobalSHM_out[0].mil1553_out.bc_out[bus - 1][message_index - 1][word_index - 1]

cdef inline unsigned short read_rt_in(unsigned short bus, unsigned int message_index, unsigned int word_index):
    return GlobalSHM_in[0].mil1553_in.rt_in[bus - 1][message_index - 1][word_index - 1]

cdef inline unsigned short read_rt_out(unsigned short bus, unsigned int message_index, unsigned int word_index):
    return GlobalSHM_out[0].mil1553_out.rt_out[bus - 1][message_index - 1][word_index - 1]

##################################################DPFS-BEGIN###################################################
cpdef inline dict write_dpfs(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    if not bypass:
        data = RHS_type_cast(symbol.get_dtype_code(), data)

    cdef unsigned char channel
    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]
    cdef unsigned long typed_data = data
    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
                GlobalSHM_out[0].dpfs_out.dDpfsValue[offset[channel - 1] - 1] = deref(<float *> &typed_data)
            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict read_dpfs(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef str type_code
    cdef unsigned char channel
    cdef unsigned long frame_number
    cdef list status = [0x0, 0x0, 0x0, 0x0]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
                value[channel - 1] = deref(
                    <unsigned long *> &GlobalSHM_out[0].dpfs_out.dDpfsValue[offset[channel - 1] - 1])
            ELIF AETS_EXC_MK1 or AETS_ALL:
                pass

    if not bypass:
        type_code = symbol.get_dtype_code()
        for channel from 0 <= channel < 4:
            value[channel] = LHS_type_cast(type_code, value[channel])

    min_value = symbol.get_min()
    max_value = symbol.get_max()
    for channel from 0 <= channel < 4:
        status[channel] = check_range(bypass, min_value, max_value, value[channel])

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

##################################################DPFS-END###################################################

##################################################SPIL-BEGIN###################################################
cpdef inline dict prefetch_write_spil_begin(object symbol, unsigned int user_mask, unsigned int user_offset,
                                            bool bypass, data):
    cdef dict result

    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    if not bypass:
        data = data * symbol.get_slpe() + symbol.get_bias()
        data = RHS_type_cast(symbol.get_dtype_code(), data)

    return {'data': data, 'status': status}

cpdef inline dict prefetch_read_spil_end(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass,
                                         dict result):
    cdef str type_code
    cdef unsigned char channel
    cdef list status = [0x0, 0x0, 0x0, 0x0]
    cdef list value = ["unused", "unused", "unused", "unused"]

    if not bypass:
        type_code = symbol.get_dtype_code()
        for channel from 0 <= channel < 4:
            if result['value'][channel] != "unused":
                value[channel] = (LHS_type_cast(type_code, result['value'][channel]) - symbol.get_bias()) / \
                                 symbol.get_slpe()
    else:
        for channel from 0 <= channel < 4:
            value[channel] = result['value'][channel]

    min_value = symbol.get_min()
    max_value = symbol.get_max()
    for channel from 0 <= channel < 4:
        status[channel] = check_range(bypass, min_value, max_value, value[channel]) | result['status'][channel]

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': result['frame'],
            'value': tuple(value), 'status': tuple(status)}

##################################################SPIL-END###################################################

##################################################RS422-BEGIN###################################################

cpdef switch_buffers(list nodes):
    cdef list offset
    cdef dict switched_offset_id = {}

    if len(nodes) == 0:
        return

    for node in nodes:
        offset = list(node.get_ofst())

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                if not switched_offset_id.has_key((offset[channel - 1], node.get_id_())):
                    GlobalSHM_task[0].rs422_task.TxActiveBuffer[offset[channel - 1]][node.get_id_()] ^= 1
                    switched_offset_id[(offset[channel - 1], node.get_id_())] = True

cdef inline get_rs422in_byte(offset, id_, shift):
    return GlobalSHM_in[0].rs422_in.RS422_Msg[offset][id_][get_active_buffer_lookup(offset, id_)][shift]

cdef inline get_rs422out_byte(offset, id_, shift):
    return GlobalSHM_out[0].rs422_out.RS422_Msg[offset][id_][get_active_buffer_lookup(offset, id_)][shift]

cdef inline rs422in_read_value(dtype, offset, id_, ofstx, user_offset):
    if (dtype == 'byte') or (dtype == 'u8') or (dtype == 's8') or (dtype == 'd8'):
        return get_rs422in_byte(offset, id_, ofstx + user_offset)
    if (dtype == 'word') or (dtype == 'u16') or (dtype == 's16') or (dtype == 'd16'):
        return get_rs422in_byte(offset, id_, ofstx + 2 * user_offset) | get_rs422in_byte(offset, id_,
                                                                                         ofstx + 2 * user_offset + 1) << 8
    if (dtype == 'u24') or (dtype == 's24'):
        return get_rs422in_byte(offset, id_, ofstx + 3 * user_offset) | get_rs422in_byte(offset, id_,
                                                                                         ofstx + 3 * user_offset + 1) << 8 | get_rs422in_byte(
            offset, id_, ofstx + 3 * user_offset + 2) << 16
    if (dtype == 'dword') or (dtype == 'u32') or (dtype == 's32') or (dtype == 'd32'):
        return (get_rs422in_byte(offset, id_, ofstx + 4 * user_offset) | get_rs422in_byte(offset, id_,
                                                                                          ofstx + 4 * user_offset + 1) << 8 |
                get_rs422in_byte(offset, id_, ofstx + 4 * user_offset + 2) << 16 | get_rs422in_byte(offset, id_,
                                                                                                    ofstx + 4 * user_offset + 3) << 24)

cdef inline rs422out_read_value(dtype, offset, id_, ofstx, user_offset):
    if (dtype == 'byte') or (dtype == 'u8') or (dtype == 's8') or (dtype == 'd8'):
        return get_rs422out_byte(offset, id_, ofstx + user_offset)
    if (dtype == 'word') or (dtype == 'u16') or (dtype == 's16') or (dtype == 'd16'):
        return get_rs422out_byte(offset, id_, ofstx + 2 * user_offset) | get_rs422out_byte(offset, id_,
                                                                                           ofstx + 2 * user_offset + 1) << 8
    if (dtype == 'u24') or (dtype == 's24'):
        return get_rs422out_byte(offset, id_, ofstx + 3 * user_offset) | get_rs422out_byte(offset, id_,
                                                                                           ofstx + 3 * user_offset + 1) << 8 | get_rs422out_byte(
            offset, id_, ofstx + 3 * user_offset + 2) << 16
    if (dtype == 'dword') or (dtype == 'u32') or (dtype == 's32') or (dtype == 'd32'):
        return (get_rs422out_byte(offset, id_, ofstx + 4 * user_offset) | get_rs422out_byte(offset, id_,
                                                                                            ofstx + 4 * user_offset + 1) << 8 |
                get_rs422out_byte(offset, id_, ofstx + 4 * user_offset + 2) << 16 | get_rs422out_byte(offset, id_,
                                                                                                      ofstx + 4 * user_offset + 3) << 24)

cpdef inline dict read_rs422in(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            value[channel - 1] = rs422in_read_value(symbol.get_dtype_code(), offset[channel - 1], symbol.get_id_(),
                                                    symbol.get_ofstx(), user_offset)

    if not bypass:
        if symbol.get_dtype_code() == 's24':  # for signed 24 bit
            value = [(0xFF000000 | v) if (type(value) is not str) and (0x800000 & v) else v for v in
                     value]  # if the value is negative, sign extend to 32bit
        value = map(RS422_LHS_type_cast, [symbol.get_dtype_code() for i in xrange(4)],
                    [symbol.get_mask() for i in xrange(4)], value)
        value = [('unused' if v == 'unused' else ((v - symbol.get_bias()) / symbol.get_slpe())) for v in value]

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cdef inline set_rs422in_byte(offset, id_, buffer_, shift, unsigned char data):
    GlobalSHM_in[0].rs422_in.RS422_Msg[offset][id_][buffer_][shift] = data

cdef inline set_rs422out_byte(offset, id_, buffer_, shift, unsigned char data):
    GlobalSHM_out[0].rs422_out.RS422_Msg[offset][id_][buffer_][shift] = data

cdef inline rs422in_write_value(bypass, dtype, offset, id_, ofstx, user_offset, data, mask):
    buffer_ = GlobalSHM_task[0].rs422_task.TxActiveBuffer[offset][id_] ^ 1
    if (dtype == 'byte') or (dtype == 'u8') or (dtype == 's8'):
        set_rs422in_byte(offset, id_, buffer_, ofstx + user_offset, data)
    if (dtype == 'word') or (dtype == 'u16') or (dtype == 's16'):
        set_rs422in_byte(offset, id_, buffer_, ofstx + 2 * user_offset, data & 0xFF)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 2 * user_offset + 1, (data & 0xFF00) >> 8)
    if (dtype == 'u24') or (dtype == 's24'):
        set_rs422in_byte(offset, id_, buffer_, ofstx + 3 * user_offset, data & 0xFF)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 3 * user_offset + 1, (data & 0xFF00) >> 8)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 3 * user_offset + 2, (data & 0xFF0000) >> 16)
    if (dtype == 'dword') or (dtype == 'u32') or (dtype == 's32'):
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset, data & 0xFF)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 1, (data & 0xFF00) >> 8)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 2, (data & 0xFF0000) >> 16)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 3, (data & 0xFF000000) >> 24)
    if dtype == 'd8':
        modified_data = data if bypass else d8tou8(rs422in_read_value(dtype, offset, id_, ofstx, user_offset), mask,
                                                   data)
        set_rs422in_byte(offset, id_, buffer_, ofstx + user_offset, modified_data)
    if dtype == 'd16':
        modified_data = data if bypass else d16tou16(rs422in_read_value(dtype, offset, id_, ofstx, user_offset), mask,
                                                     data)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 2 * user_offset, modified_data & 0xFF)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 2 * user_offset + 1, (modified_data & 0xFF00) >> 8)
    if dtype == 'd32':
        modified_data = data if bypass else d32tou32(rs422in_read_value(dtype, offset, id_, ofstx, user_offset), mask,
                                                     data)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset, modified_data & 0xFF)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 1, (modified_data & 0xFF00) >> 8)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 2, (modified_data & 0xFF0000) >> 16)
        set_rs422in_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 3, (modified_data & 0xFF000000) >> 24)

cdef inline rs422out_write_value(bypass, dtype, offset, id_, ofstx, user_offset, data, mask):
    buffer_ = GlobalSHM_task[0].rs422_task.TxActiveBuffer[offset][id_] ^ 1
    if (dtype == 'byte') or (dtype == 'u8') or (dtype == 's8'):
        set_rs422out_byte(offset, id_, buffer_, ofstx + user_offset, data)
    if (dtype == 'word') or (dtype == 'u16') or (dtype == 's16'):
        set_rs422out_byte(offset, id_, buffer_, ofstx + 2 * user_offset, data & 0xFF)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 2 * user_offset + 1, (data & 0xFF00) >> 8)
    if (dtype == 'u24') or (dtype == 's24'):
        set_rs422out_byte(offset, id_, buffer_, ofstx + 3 * user_offset, data & 0xFF)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 3 * user_offset + 1, (data & 0xFF00) >> 8)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 3 * user_offset + 2, (data & 0xFF0000) >> 16)
    if (dtype == 'dword') or (dtype == 'u32') or (dtype == 's32'):
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset, data & 0xFF)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 1, (data & 0xFF00) >> 8)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 2, (data & 0xFF0000) >> 16)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 3, (data & 0xFF000000) >> 24)
    if dtype == 'd8':
        modified_data = data if bypass else d8tou8(rs422out_read_value(dtype, offset, id_, ofstx, user_offset), mask,
                                                   data)
        set_rs422out_byte(offset, id_, buffer_, ofstx + user_offset, modified_data)
    if dtype == 'd16':
        modified_data = data if bypass else d16tou16(rs422out_read_value(dtype, offset, id_, ofstx, user_offset), mask,
                                                     data)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 2 * user_offset, modified_data & 0xFF)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 2 * user_offset + 1, (modified_data & 0xFF00) >> 8)
    if dtype == 'd32':
        modified_data = data if bypass else d32tou32(rs422out_read_value(dtype, offset, id_, ofstx, user_offset), mask,
                                                     data)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset, modified_data & 0xFF)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 1, (modified_data & 0xFF00) >> 8)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 2, (modified_data & 0xFF0000) >> 16)
        set_rs422out_byte(offset, id_, buffer_, ofstx + 4 * user_offset + 3, (modified_data & 0xFF000000) >> 24)

cpdef inline dict write_rs422in(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    if not bypass:
        data = data * symbol.get_slpe() + symbol.get_bias()
        data = RS422_RHS_type_cast(symbol.get_dtype_code(), symbol.get_mask(), data)

    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            rs422in_write_value(bypass, symbol.get_dtype_code(), offset[channel - 1], symbol.get_id_(),
                                symbol.get_ofstx(), user_offset, data, symbol.get_mask())
            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict read_rs422out(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            value[channel - 1] = rs422out_read_value(symbol.get_dtype_code(), offset[channel - 1], symbol.get_id_(),
                                                     symbol.get_ofstx(), user_offset)

    if not bypass:
        if symbol.get_dtype_code() == 's24':  # for signed 24 bit
            value = [(0xFF000000 | v) if (type(value) is not str) and (0x800000 & v) else v for v in
                     value]  # if the value is negative, sign extend to 32bit
        value = map(RS422_LHS_type_cast, [symbol.get_dtype_code() for i in xrange(4)],
                    [symbol.get_mask() for i in xrange(4)], value)
        value = [('unused' if v == 'unused' else ((v - symbol.get_bias()) / symbol.get_slpe())) for v in value]

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict write_rs422out(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    if not bypass:
        data = data * symbol.get_slpe() + symbol.get_bias()
        data = RS422_RHS_type_cast(symbol.get_dtype_code(), symbol.get_mask(), data)

    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            rs422out_write_value(bypass, symbol.get_dtype_code(), offset[channel - 1], symbol.get_id_(),
                                 symbol.get_ofstx(), user_offset, data, symbol.get_mask())
            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict write_rs422task(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)
    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())
    cdef stype = symbol.get_stype()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
                if symbol.get_stype() == 'txon':
                    GlobalSHM_task[0].rs422_task.TxON[offset[channel - 1]][symbol.get_id_()] = converted_data[
                        channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'ckbp':
                    GlobalSHM_task[0].rs422_task.TxChecksumBypass[offset[channel - 1]][symbol.get_id_()] = \
                        converted_data[
                            channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'txmxid':
                    GlobalSHM_task[0].rs422_task.TxMaxChannelIDs[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'rxmxid':
                    GlobalSHM_task[0].rs422_task.RxMaxChannelIDs[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
            ELIF AETS_EXC_MK1 or AETS_ALL:
                if symbol.get_stype() == 'txon':
                    GlobalSHM_task[0].rs422_task.TxON[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'ckbp':
                    GlobalSHM_task[0].rs422_task.TxChecksumBypass[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'singlefrm':
                    GlobalSHM_task[0].rs422_task.TxSingleFrame[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'crcdis':
                    GlobalSHM_task[0].rs422_task.RxCRCDisable[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'chreset':
                    GlobalSHM_task[0].rs422_task.ChannelReset[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
            if symbol.get_stype() == 'txab':
                GlobalSHM_task[0].rs422_task.TxActiveBuffer[offset[channel - 1]][symbol.get_id_()] = converted_data[
                    channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'rxab':
                GlobalSHM_task[0].rs422_task.RxActiveBuffer[offset[channel - 1]][symbol.get_id_()] = converted_data[
                    channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'hz':
                GlobalSHM_task[0].rs422_task.TxFrameRate[offset[channel - 1]][symbol.get_id_()] = converted_data[
                    channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'baud':
                GlobalSHM_task[0].rs422_task.BaudRate[offset[channel - 1]] = converted_data[channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'databits':
                GlobalSHM_task[0].rs422_task.DataBits[offset[channel - 1]] = converted_data[channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'parity':
                GlobalSHM_task[0].rs422_task.Parity[offset[channel - 1]] = converted_data[channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'stopbits':
                GlobalSHM_task[0].rs422_task.NumStopBits[offset[channel - 1]] = converted_data[channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'frmofst':
                GlobalSHM_task[0].rs422_task.TxFrameOffset[offset[channel - 1]][symbol.get_id_()] = converted_data[
                    channel - 1]
                value[channel - 1] = "written"
            IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
                if symbol.get_stype() == 'txcsalgo':
                    GlobalSHM_task[0].rs422_task.TxChksumAlgorithm[offset[channel - 1]][symbol.get_id_()] = \
                        converted_data[
                            channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'rxcsalgo':
                    GlobalSHM_task[0].rs422_task.RxChksumAlgorithm[offset[channel - 1]][symbol.get_id_()] = \
                        converted_data[
                            channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'txmaxids':
                    GlobalSHM_task[0].rs422_task.TxMaxChannelIDs[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
                if symbol.get_stype() == 'rxmaxids':
                    GlobalSHM_task[0].rs422_task.RxMaxChannelIDs[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"
            ELIF AETS_EXC_MK1 or AETS_ALL:
                if symbol.get_stype() == 'csalgo':
                    GlobalSHM_task[0].rs422_task.ChksumAlgorithm[offset[channel - 1]] = converted_data[channel - 1]
                    value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict read_rs422task(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
                if symbol.get_stype() == 'txon':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxON[offset[channel - 1]][symbol.get_id_()]
                if symbol.get_stype() == 'ckbp':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxChecksumBypass[offset[channel - 1]][
                        symbol.get_id_()]
                if symbol.get_stype() == 'txmxid':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxMaxChannelIDs[offset[channel - 1]]
                if symbol.get_stype() == 'rxmxid':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.RxMaxChannelIDs[offset[channel - 1]]
            ELIF AETS_EXC_MK1 or AETS_ALL:
                if symbol.get_stype() == 'txon':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxON[offset[channel - 1]]
                if symbol.get_stype() == 'ckbp':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxChecksumBypass[offset[channel - 1]]
                if symbol.get_stype() == 'singlefrm':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxSingleFrame[offset[channel - 1]]
                if symbol.get_stype() == 'crcdis':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.RxCRCDisable[offset[channel - 1]]
                if symbol.get_stype() == 'chreset':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.ChannelReset[offset[channel - 1]]
            if symbol.get_stype() == 'txab':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.TxActiveBuffer[offset[channel - 1]][symbol.get_id_()]
            if symbol.get_stype() == 'rxab':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.RxActiveBuffer[offset[channel - 1]][symbol.get_id_()]
            if symbol.get_stype() == 'hz':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.TxFrameRate[offset[channel - 1]][symbol.get_id_()]
            if symbol.get_stype() == 'baud':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.BaudRate[offset[channel - 1]]
            if symbol.get_stype() == 'databits':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.DataBits[offset[channel - 1]]
            if symbol.get_stype() == 'parity':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.Parity[offset[channel - 1]]
            if symbol.get_stype() == 'stopbits':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.NumStopBits[offset[channel - 1]]
            if symbol.get_stype() == 'frmofst':
                value[channel - 1] = GlobalSHM_task[0].rs422_task.TxFrameOffset[offset[channel - 1]][symbol.get_id_()]
            IF AIRDATS_E_MK1 or AIRDATS_E_MK2:
                if symbol.get_stype() == 'txcsalgo':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxChksumAlgorithm[offset[channel - 1]][
                        symbol.get_id_()]
                if symbol.get_stype() == 'rxcsalgo':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.RxChksumAlgorithm[offset[channel - 1]][
                        symbol.get_id_()]
                if symbol.get_stype() == 'txmaxids':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.TxMaxChannelIDs[offset[channel - 1]]
                if symbol.get_stype() == 'rxmaxids':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.RxMaxChannelIDs[offset[channel - 1]]
            ELIF AETS_EXC_MK1 or AETS_ALL:
                if symbol.get_stype() == 'csalgo':
                    value[channel - 1] = GlobalSHM_task[0].rs422_task.ChksumAlgorithm[offset[channel - 1]]

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict write_rs422error(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)
    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())
    cdef stype = symbol.get_stype()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if symbol.get_stype() == 'txerr':
                GlobalSHM_error[0].rs422_error.TxError[offset[channel - 1]][symbol.get_id_()] = converted_data[
                    channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'rxdp':
                GlobalSHM_error[0].rs422_error.RxDROPPED_PktsCount[offset[channel - 1]][symbol.get_id_()] = \
                    converted_data[channel - 1]
                value[channel - 1] = "written"
            if symbol.get_stype() == 'rxcserr':
                GlobalSHM_error[0].rs422_error.RxCHECKSUM_Error[offset[channel - 1]][symbol.get_id_()] = converted_data[
                    channel - 1]
                value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict read_rs422error(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = list(symbol.get_ofst())

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if symbol.get_stype() == 'txerr':
                value[channel - 1] = GlobalSHM_error[0].rs422_error.TxError[offset[channel - 1]][symbol.get_id_()]
            if symbol.get_stype() == 'rxdp':
                value[channel - 1] = GlobalSHM_error[0].rs422_error.RxDROPPED_PktsCount[offset[channel - 1]][
                    symbol.get_id_()]
            if symbol.get_stype() == 'rxcserr':
                value[channel - 1] = GlobalSHM_error[0].rs422_error.RxCHECKSUM_Error[offset[channel - 1]][
                    symbol.get_id_()]

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

##################################################RS422-END###################################################

####################################1553-BEG
cdef inline unsigned char get_mil_bus(unsigned char channel):
    if channel in (1, 2):
        return 1
    else:  # if  channel in (3, 4)
        return 2

cpdef inline dict read_mil1553btask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef str type_code
    cdef unsigned char channel
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]
    cdef unsigned int message_index = symbol.get_ofstx()
    cdef subsystem = symbol.get_subsystem()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if subsystem == 'start':
                value[channel - 1] = read_1553_task_start(get_mil_bus(channel))
            if subsystem == 'stop':
                value[channel - 1] = read_1553_task_stop(get_mil_bus(channel))
            IF AETS_EXC_MK1 or AETS_ALL:
                if subsystem == 'read':
                    value[channel - 1] = read_read1553b(get_mil_bus(channel))
                if subsystem == 'switch':
                    value[channel - 1] = read_switch_1553channels(get_mil_bus(channel))
                # Mod5: begin
                if subsystem == 'no_update':
                    value[channel - 1] = read_no_update(get_mil_bus(channel))
                if subsystem == 'no_errors':
                    value[channel - 1] = read_no_errors(get_mil_bus(channel))
                if subsystem == 'mc_dfcc':
                    value[channel - 1] = read_mc_dfcc(get_mil_bus(channel))
                if subsystem == 'mc_mpru':
                    value[channel - 1] = read_mc_mpru(get_mil_bus(channel))
                    # Mod5: end

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict write_mil1553btask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass,
                                     data):
    converted_data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]
    cdef unsigned int message_index = symbol.get_ofstx()
    cdef subsystem = symbol.get_subsystem()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if subsystem == 'start':
                write_1553_task_start(get_mil_bus(channel), converted_data)
            if subsystem == 'stop':
                write_1553_task_stop(get_mil_bus(channel), converted_data)
            IF AETS_EXC_MK1 or AETS_ALL:
                if subsystem == 'read':
                    set_read1553b(get_mil_bus(channel), converted_data)
                if subsystem == 'switch':
                    switch_1553channels(get_mil_bus(channel), converted_data)
                # Mod5: begin
                if subsystem == 'no_update':
                    write_no_update(get_mil_bus(channel), converted_data)
                if subsystem == 'no_errors':
                    write_no_errors(get_mil_bus(channel), converted_data)
                if subsystem == 'mc_dfcc':
                    write_mc_dfcc(get_mil_bus(channel), converted_data)
                if subsystem == 'mc_mpru':
                    write_mc_mpru(get_mil_bus(channel), converted_data)
                    # Mod5: end
            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

###
cpdef inline dict read_mil1553bin(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef str type_code
    cdef unsigned char channel
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]
    cdef unsigned int message_index = symbol.get_ofstx()
    cdef subsystem = symbol.get_subsystem()
    cdef mask = symbol.get_mask()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if subsystem == 'bc':
                if channel in (1, 2):
                    mapped_index = bc_msgid_map_bus1.get((message_index, True), message_index)
                else:
                    mapped_index = bc_msgid_map_bus2.get((message_index, True), message_index)
                value[channel - 1] = read_bc_in(get_mil_bus(channel), mapped_index, offset[channel - 1])
                if not bypass:
                    value[channel - 1] = extract_word(value[channel - 1], mask)
            elif subsystem == 'rt':
                if channel in (1, 2):
                    mapped_index = msgid_map_bus1.get((message_index, False), message_index)
                else:
                    mapped_index = msgid_map_bus2.get((message_index, False), message_index)
                value[channel - 1] = read_rt_in(get_mil_bus(channel), mapped_index, offset[channel - 1])
                if not bypass:
                    value[channel - 1] = extract_word(value[channel - 1], mask)

    if not bypass:
        type_code = symbol.get_dtype_code()
        for channel from 0 <= channel < 4:
            if value[channel] != "unused":
                value[channel] = (LHS_type_cast(type_code, value[channel]) / symbol.get_slpe()) - symbol.get_bias()

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict read_mil1553bout(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef str type_code
    cdef unsigned char channel
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]
    cdef unsigned int message_index = symbol.get_ofstx()
    cdef subsystem = symbol.get_subsystem()
    cdef mask = symbol.get_mask()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if subsystem == 'bc':
                if channel in (1, 2):
                    mapped_index = bc_msgid_map_bus1.get((message_index, False), message_index)
                else:
                    mapped_index = bc_msgid_map_bus2.get((message_index, False), message_index)
                value[channel - 1] = read_bc_out(get_mil_bus(channel), mapped_index, offset[channel - 1])
                if not bypass:
                    value[channel - 1] = extract_word(value[channel - 1], mask)
            elif subsystem == 'rt':
                if channel in (1, 2):
                    mapped_index = msgid_map_bus1.get((message_index, True), message_index)
                else:
                    mapped_index = msgid_map_bus2.get((message_index, True), message_index)
                value[channel - 1] = read_rt_out(get_mil_bus(channel), mapped_index, offset[channel - 1])
                if not bypass:
                    value[channel - 1] = extract_word(value[channel - 1], mask)

    if not bypass:
        type_code = symbol.get_dtype_code()
        for channel from 0 <= channel < 4:
            if value[channel] != "unused":
                value[channel] = (LHS_type_cast(type_code, value[channel]) / symbol.get_slpe()) - symbol.get_bias()

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict write_mil1553bin(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    converted_data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    if not bypass:
        converted_data = symbol.get_slpe() * (converted_data + symbol.get_bias())
        converted_data = RHS_type_cast(symbol.get_dtype_code(), converted_data)

    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]
    cdef unsigned int message_index = symbol.get_ofstx()
    cdef subsystem = symbol.get_subsystem()
    cdef mask = symbol.get_mask()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if subsystem == 'bc':
                if channel in (1, 2):
                    mapped_index = bc_msgid_map_bus1.get((message_index, True), message_index)
                else:
                    mapped_index = bc_msgid_map_bus2.get((message_index, True), message_index)
                if not bypass:
                    value[channel - 1] = read_bc_in(get_mil_bus(channel), mapped_index, offset[channel - 1])
                    value[channel - 1] = set_word(value[channel - 1], mask, converted_data)
                else:
                    value[channel - 1] = converted_data
                write_bc_in(get_mil_bus(channel), mapped_index, offset[channel - 1], value[channel - 1])
            elif subsystem == 'rt':
                if channel in (1, 2):
                    mapped_index = msgid_map_bus1.get((message_index, False), message_index)
                else:
                    mapped_index = msgid_map_bus2.get((message_index, False), message_index)
                if not bypass:
                    value[channel - 1] = read_rt_in(get_mil_bus(channel), mapped_index, offset[channel - 1])
                    value[channel - 1] = set_word(value[channel - 1], mask, converted_data)
                else:
                    value[channel - 1] = converted_data
                write_rt_in(get_mil_bus(channel), mapped_index, offset[channel - 1], value[channel - 1])

            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict write_mil1553bout(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    converted_data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)

    if not bypass:
        converted_data = symbol.get_slpe() * (converted_data + symbol.get_bias())
        converted_data = RHS_type_cast(symbol.get_dtype_code(), converted_data)

    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]
    cdef unsigned int message_index = symbol.get_ofstx()
    cdef subsystem = symbol.get_subsystem()
    cdef mask = symbol.get_mask()

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            if subsystem == 'bc':
                if channel in (1, 2):
                    mapped_index = bc_msgid_map_bus1.get((message_index, False), message_index)
                else:
                    mapped_index = bc_msgid_map_bus2.get((message_index, False), message_index)
                if not bypass:
                    value[channel - 1] = read_bc_out(get_mil_bus(channel), mapped_index, offset[channel - 1])
                    value[channel - 1] = set_word(value[channel - 1], mask, converted_data)
                else:
                    value[channel - 1] = converted_data
                write_bc_out(get_mil_bus(channel), mapped_index, offset[channel - 1], value[channel - 1])
            elif subsystem == 'rt':
                if channel in (1, 2):
                    mapped_index = msgid_map_bus1.get((message_index, True), message_index)
                else:
                    mapped_index = msgid_map_bus2.get((message_index, True), message_index)
                if not bypass:
                    value[channel - 1] = read_rt_out(get_mil_bus(channel), mapped_index, offset[channel - 1])
                    value[channel - 1] = set_word(value[channel - 1], mask, converted_data)
                else:
                    value[channel - 1] = converted_data
                write_rt_out(get_mil_bus(channel), mapped_index, offset[channel - 1], value[channel - 1])

            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

####################################1553-END
cpdef bit_march_test(unsigned long start_address, unsigned long end_address, unsigned char data_type,
                     unsigned char march_bit):
    cdef unsigned long transaction_count, transaction_number, address, frame_number, march_info
    cdef list result, status, return_value = []
    cdef unsigned char channel

    frame_number = get_frame_number()

    if data_type == 0x4:
        # make addresses to DWORD boundary
        start_address &= 0xFFFFFFFC
        end_address &= 0xFFFFFFFFC
    elif data_type == 0x2:
        # make addresses to WORD boundary
        start_address &= 0xFFFFFFFE
        end_address &= 0xFFFFFFFFE
    else:
        pass  # nothing to do for byte

    transaction_count = ((end_address - start_address) / data_type) + 1

    for channel from 1 <= channel < 5:  # for channel in xrange(1, 5):
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0xD)
            write_dpram_transaction_count(channel, transaction_count)
            write_dpram_start_address(channel, start_address)
            write_dpram_end_address(channel, end_address)
            # min modify rt module hack: first bit of data type location indicates march type
            if march_bit:
                march_info = 0x80000000 | <unsigned long> data_type
            else:
                march_info = 0x00000000 | <unsigned long> data_type
            write_dpram_data_type(channel, march_info)

    for channel from 1 <= channel < 5:  # for channel in xrange(1, 5):
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_nrt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.01)  #pass

    result = ["unused", "unused", "unused", "unused"]
    status = [0x0, 0x0, 0x0, 0x0]

    for channel from 1 <= channel < 5:  # for channel in xrange(1, 5):
        if channel_enabled(channel):
            result[channel - 1] = read_dpram_data(channel, 0)
            status[channel - 1] = read_dpram_response_status(channel)

    spil_nrt_end()

    return {'start_address': start_address, 'end_address': end_address, 'value': tuple(result),
            'status': tuple(status)},

cpdef tuple reg_poke_nc(tuple address_datatype_data, hide_write=False):
    cdef unsigned long transaction_count, transaction_number, frame_number
    cdef list result, status, return_value = []
    cdef unsigned char channel

    frame_number = get_frame_number()

    transaction_count = len(address_datatype_data) / 4

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0xC)
            write_dpram_transaction_count(channel, transaction_count)

            for transaction_number from 0 <= transaction_number < transaction_count:
                write_dpram_command_area_address(channel, (transaction_number + 1),
                                                 address_datatype_data[4 * transaction_number])
                write_dpram_command_area_data(channel, (transaction_number + 1),
                                              address_datatype_data[(4 * transaction_number) + 1])
                write_dpram_command_area_data_type(channel, (transaction_number + 1),
                                                   address_datatype_data[(4 * transaction_number) + 2])
                write_dpram_command_area_mask(channel, (transaction_number + 1),
                                              address_datatype_data[(4 * transaction_number) + 3])

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_rt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.01)  #pass

    for transaction_number from 0 <= transaction_number < transaction_count:
        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                if hide_write:
                    result[channel - 1] = "written"
                else:
                    result[channel - 1] = address_datatype_data[(4 * transaction_number) + 1]
                status[channel - 1] = read_dpram_response_status(channel)

        return_value.append(
            {'frame': frame_number, 'address': address_datatype_data[4 * transaction_number], 'value': tuple(result),
             'status': tuple(status)})

    return tuple(return_value)

cpdef tuple poke_nc(tuple address_datatype_data):
    cdef unsigned long transaction_count, transaction_number, frame_number
    cdef list result, status, return_value = []
    cdef unsigned char channel

    frame_number = get_frame_number()

    transaction_count = len(address_datatype_data) / 4

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0x5)
            write_dpram_transaction_count(channel, transaction_count)

            for transaction_number from 0 <= transaction_number < transaction_count:
                write_dpram_command_area_address(channel, (transaction_number + 1),
                                                 address_datatype_data[4 * transaction_number])
                write_dpram_command_area_data(channel, (transaction_number + 1),
                                              address_datatype_data[(4 * transaction_number) + 1])
                write_dpram_command_area_data_type(channel, (transaction_number + 1),
                                                   address_datatype_data[(4 * transaction_number) + 2])
                write_dpram_command_area_mask(channel, (transaction_number + 1),
                                              address_datatype_data[(4 * transaction_number) + 3])

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_rt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.01)  #pass

    for transaction_number from 0 <= transaction_number < transaction_count:
        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                result[channel - 1] = address_datatype_data[(4 * transaction_number) + 1]
                status[channel - 1] = read_dpram_response_status(channel)

        return_value.append(
            {'frame': frame_number, 'address': address_datatype_data[4 * transaction_number], 'value': tuple(result),
             'status': tuple(status)})

    return tuple(return_value)

# Mod1: begin
# Mod4: begin
# Mod9: begin
cpdef inline unsigned long apply_address_mask(unsigned long address, unsigned long data):
    if cfg.config_file.is_configured_for_DFCC():
        is_ccdl = (0x003C0000 <= address < 0x003C8000)  # 16 bits
        is_1553 = (0x003C8000 <= address < 0x003D0000)  # 16 bits
        is_nvm = (0x00300000 <= address < 0x00302000)  # 16 bits
        is_analog_io = (0x003D0000 <= address <= 0x003D1FFC)  # 16 bits
        is_silc = (0x003D6000 <= address < 0x003D8000) and (address != 0x003D6028)  # 16 bits
        is_rs422_tx1_fifo = (address == 0x003D80D0)  # 9 bits
        is_rs422_tx2_fifo = (address == 0x003D80E0)  # 8 bits
        is_rs422_rx_fifo = (address == 0x003D80C0)  # 15 bits
        is_rs422_wrap_fifo = (0x003D8000 <= address <= 0x003D8090)  # 8 bits

        if is_ccdl or is_nvm or is_1553 or is_analog_io or is_silc:
            return 0x0000FFFF & data
        elif is_rs422_rx_fifo:
            return 0x00007FFF & data
        elif is_rs422_tx1_fifo:
            return 0x000001FF & data
        elif is_rs422_tx2_fifo or is_rs422_wrap_fifo:
            return 0x000000FF & data
        else:
            return 0xFFFFFFFF & data
    elif cfg.config_file.is_configured_for_DFCC_MK1A() or cfg.config_file.is_configured_for_DFCC_MK2():
        is_ccdl = (0x206C0000 <= address < 0x206C8000)  # 16 bits
        is_1553 = (0x206C8000 <= address < 0x206D0000)  # 16 bits
        is_nvm = (0x20500000 <= address < 0x20600000)  # 16 bits
        is_analog_io = (0x206D0000 <= address <= 0x206D2000)  # 16 bits
        is_silc = (0x206D6000 <= address < 0x206D6060) and (address != 0x206D6028)  # 16 bits
        is_rs422_tx_fifo = (0x20620200 <= address <= 0x2062027C)  # 8 bits
        is_rs422_rx_fifo = (0x20620280 <= address <= 0x206202FC)  # 8 bits
        is_rs422_wrap_fifo = (0x20620200 <= address <= 0x206202FC)  # 8 bits

        if is_ccdl or is_1553 or is_analog_io or is_silc:
            return 0x0000FFFF & data
        elif is_nvm:
            return (0xFFFF0000 & data) >> 16
        elif is_rs422_rx_fifo or is_rs422_tx_fifo or is_rs422_wrap_fifo:
            return 0x000000FF & data
        else:
            return 0xFFFFFFFF & data
    else:  # ADC/LADC
        return 0xFFFFFFFF & data
# Mod9: end
# Mod4: end
# Mod1: end

cpdef tuple peek_nc(tuple address_datatype):
    cdef unsigned long transaction_count, transaction_number, frame_number
    cdef list result, status, return_value = []
    cdef unsigned char channel

    frame_number = get_frame_number()

    transaction_count = len(address_datatype) / 3

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0x6)
            write_dpram_transaction_count(channel, transaction_count)

            for transaction_number from 0 <= transaction_number < transaction_count:
                write_dpram_command_area_address(channel, (transaction_number + 1),
                                                 address_datatype[3 * transaction_number])
                write_dpram_command_area_data_type(channel, (transaction_number + 1),
                                                   address_datatype[(3 * transaction_number) + 1])
                write_dpram_command_area_mask(channel, (transaction_number + 1),
                                              address_datatype[(3 * transaction_number) + 2])

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_rt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.01)  #pass

    for transaction_number from 0 <= transaction_number < transaction_count:
        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                # Mod1: begin
                address = address_datatype[3 * transaction_number]
                # Mod9: begin
                result[channel - 1] = apply_address_mask(address, read_dpram_data(channel, transaction_number))
                # Mod9: end
                # Mod1: end
                status[channel - 1] = read_dpram_response_status(channel)

        return_value.append(
            {'frame': frame_number, 'address': address_datatype[3 * transaction_number], 'value': tuple(result),
             'status': tuple(status)})

    return tuple(return_value)

cpdef tuple peek_c(unsigned long start_address, unsigned long end_address, unsigned char data_type):
    cdef unsigned long transaction_count, transaction_number, address, frame_number
    cdef list result, status, return_value = []
    cdef unsigned char channel

    frame_number = get_frame_number()

    transaction_count = ((end_address - start_address) / data_type) + 1

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0x4)
            write_dpram_transaction_count(channel, transaction_count)
            write_dpram_start_address(channel, start_address)
            write_dpram_end_address(channel, end_address)
            write_dpram_data_type(channel, data_type)

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_rt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.01)  #pass

    address = start_address

    for transaction_number from 0 <= transaction_number < transaction_count:
        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                # Mod1: begin
                # Mod9: begin
                result[channel - 1] = apply_address_mask(address, read_dpram_data(channel, transaction_number))
                # Mod9: end
                # Mod1: end
                status[channel - 1] = read_dpram_response_status(channel)

        return_value.append(
            {'frame': frame_number, 'address': address, 'value': tuple(result), 'status': tuple(status)})
        address += data_type

    return tuple(return_value)

cpdef tuple poke_c(unsigned long start_address, unsigned long end_address, unsigned long data, unsigned char data_type):
    cdef unsigned long transaction_count, transaction_number, frame_number
    cdef list result = ["unused", "unused", "unused", "unused"]
    cdef list status = [0x0, 0x0, 0x0, 0x0]
    cdef unsigned char channel

    frame_number = get_frame_number()

    transaction_count = ((end_address - start_address) / data_type) + 1

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0x3)
            write_dpram_start_address(channel, start_address)
            write_dpram_end_address(channel, end_address)

            for transaction_number from 0 <= transaction_number < transaction_count:
                write_dpram_data(channel, transaction_number, data)

            write_dpram_data_type(channel, data_type)

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_rt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.01)  #pass

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            result[channel - 1] = "written"
            status[channel - 1] = read_dpram_response_status(channel)

    return {'frame': frame_number, 'start_address': start_address, 'end_address': end_address, 'value': tuple(result),
            'status': tuple(status)},

cpdef inline set_symbolmask(unsigned char global_mask, unsigned char user_mask, unsigned char system_mask):
    """Computes the effective mask for symbols.

    This method computes the effective mask for a symbol based on user mask
    (provided through the user input), system mask (provided in the symbol
    file) and global mask (provided using the DCHAN command).
    """
    if user_mask == 0b1111:
        set_mask(global_mask & system_mask)
    else:
        set_mask(user_mask & system_mask)

##################################################CCDL-BEGIN###################################################

cpdef inline dict read_ccdltask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            value[channel - 1] = GlobalSHM_task[0].ccdl_task.CCDL_RX_ON

    if not bypass:
        value = [('unused' if v == 'unused' else ((v - symbol.get_bias()) / symbol.get_slpe())) for v in value]

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict write_ccdltask(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)
    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    if not bypass:
        converted_data = [((symbol.get_slpe() * d) + symbol.get_bias()) for d in converted_data]

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            GlobalSHM_task[0].ccdl_task.CCDL_RX_ON = converted_data[channel - 1]
            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict read_ccdlin(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            value[channel - 1] = GlobalSHM_in[0].ccdl_in.CCDL_Hex[channel - 1][offset[channel - 1] - 1]

    if not bypass:
        value = [('unused' if v == 'unused' else ((v - symbol.get_bias()) / symbol.get_slpe())) for v in value]

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict write_ccdlin(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)
    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    if not bypass:
        converted_data = [((symbol.get_slpe() * d) + symbol.get_bias()) for d in converted_data]

    frame_number = get_frame_number()

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            GlobalSHM_in[0].ccdl_in.CCDL_Hex[channel - 1][offset[channel - 1] - 1] = converted_data[channel - 1]
            value[channel - 1] = "written"

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

cpdef inline dict read_ccdlout(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass):
    cdef unsigned long frame_number
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    frame_number = get_frame_number()

    if not bypass:
        value = [('unused' if v == 'unused' else ((v - symbol.get_bias()) / symbol.get_slpe())) for v in value]

    status = map(check_range, [bypass for i in xrange(4)], [symbol.get_min() for i in xrange(4)],
                 [symbol.get_max() for i in xrange(4)], value)

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status[0], 0x0 | status[1], 0x0 | status[2], 0x0 | status[3])}

cpdef inline dict write_ccdlout(object symbol, unsigned int user_mask, unsigned int user_offset, bool bypass, data):
    data, status = bring_to_range(bypass, symbol.get_min(), symbol.get_max(), data)
    cdef unsigned long frame_number
    cdef list converted_data = [data, data, data, data]
    cdef list value = ["unused", "unused", "unused", "unused"]
    cdef list offset = [(system_offset + user_offset) for system_offset in symbol.get_ofst()]

    if not bypass:
        converted_data = [((symbol.get_slpe() * d) + symbol.get_bias()) for d in converted_data]

    frame_number = get_frame_number()

    return {'unit': '' if bypass else symbol.get_unit(), 'bypass': bypass, 'frame': frame_number, 'value': tuple(value),
            'status': (0x0 | status, 0x0 | status, 0x0 | status, 0x0 | status)}

##################################################CCDL-END###################################################

cpdef dict download_block(unsigned long start_address, unsigned long end_address, list data_block):
    cdef list result = ["unused", "unused", "unused", "unused"]
    cdef list status = [0x0, 0x0, 0x0, 0x0]

    if len(data_block) > 0x4000:
        raise MemoryError("Download block size too large (> 0x4000)")

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0x1)

            for data_block_index in xrange(len(data_block)):
                write_dpram_data(channel, data_block_index, data_block[data_block_index])

            write_dpram_start_address(channel, start_address)
            write_dpram_end_address(channel, end_address)

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)
            spil_nrt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.1)
                pass

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            result[channel - 1] = "written"
            status[channel - 1] = read_dpram_response_status(channel)

    # convert end address to the real end address of the block rather than the last dwords address
    return {'start_address': start_address, 'end_address': (end_address + 0x3), 'value': tuple(result),
            'status': tuple(status)}

# Mod7: begin
cdef inline dict build_motorola_memory(str file_name):
    cpdef unsigned long line_number = 0
    cpdef long base_address = -1
    cpdef dict memory = {}
    parse_memory = {}
    cdef bool s0_record_found = False
    cdef bool s7_record_found = False
    fill_byte_str = 'FF'
    exec_start_addr = 0x0
    s3_record_count = 0

    try:
        f = open(file_name, "rt")
    except BaseException as e:
        raise MemoryError(e)

    # Basic S-record format
    reg_exp1 = re.compile(r"(S[01235789])([0-9A-F]{2})([0-9A-F]{6,74})")

    for line in f:
        line_number += 1
        record_search = reg_exp1.search(line)
        if not record_search:
            raise MemoryError(
                "(srecfile '%s', line %d) Invalid record line in S-record file" % (file_name, line_number))

        record_groups = record_search.groups()

        record_type = record_groups[0]
        byte_count = int(record_groups[1], 16)
        addr_data_csum = record_groups[2]

        if record_type == 'S0':
            s0_record_found = True
        elif record_type == 'S1':
            if not s0_record_found:
                raise MemoryError(
                    "(srecfile '%s', line %d) Record type 'S1' found before header record 'S0' in S-record file" % (
                        file_name, line_number))
            raise MemoryError("(srecfile '%s', line %d) Unimplemented record type 'S1' found in S-record file" % (
                file_name, line_number))
        elif record_type == 'S2':
            if not s0_record_found:
                raise MemoryError(
                    "(srecfile '%s', line %d) Record type 'S2' found before header record 'S0' in S-record file" % (
                        file_name, line_number))
            raise MemoryError("(srecfile '%s', line %d) Unimplemented record type 'S2' found in S-record file" % (
                file_name, line_number))
        elif record_type == 'S3':
            s3_record_count += 1
            if not s0_record_found:
                raise MemoryError(
                    "(srecfile '%s', line %d) Record type 'S3' found before header record 'S0' in S-record file" % (
                        file_name, line_number))
            if len(addr_data_csum) / 2 != byte_count:
                raise MemoryError(
                    "(srecfile '%s', line %d) Byte count mismatch for record type 'S3' in S-record file" % (
                        file_name, line_number))

            reg_exp2 = re.compile(r"([0-9A-F]{8})([0-9A-F]{%d})([0-9A-F]{2})" % (
                len(addr_data_csum) - (8 + 2)))  # subtract address and checksum length
            s3_search = reg_exp2.search(addr_data_csum)

            if not s3_search:
                raise MemoryError(
                    "(srecfile '%s', line %d) Invalid 'S3' record line in S-record file" % (file_name, line_number))

            s3_groups = s3_search.groups()

            address = int(s3_groups[0], 16)
            data_str = s3_groups[1]
            checksum = int(s3_groups[2], 16)

            base_address = address & 0xFFFF0000
            offset_address = (address & 0x0000FFFF)

            if not parse_memory.has_key((base_address, 0)):
                parse_memory[(base_address, 0)] = {}

            data_length = len(addr_data_csum) - (8 + 2)
            for i in range(0, data_length, 2):
                # 16K dwords (64KB) is the maximum size of a block
                if len(parse_memory[(base_address, 0)]) == (16 * 1024 * 4):
                    raise MemoryError(
                        "(srecfile '%s', line %d) Block size exceeds maximum allowed size of 16K dwords in S-record file" % (
                            file_name, line_number))
                parse_memory[(base_address, 0)][offset_address] = data_str[i:(i + 2)]
                offset_address += 1
                # if offset advances to next base and still data is
                # present in the current record then ... (this is to
                # prevent creation of empty entries in the parse_memory
                # dictionary, see $1 below)
                if (offset_address == 0x10000) and (i < (data_length - 2)):
                    base_address += 0x10000
                    offset_address = 0
                    if not parse_memory.has_key((base_address, 0)):
                        parse_memory[(base_address, 0)] = {}  # $1
        elif record_type == 'S5':
            if not s0_record_found:
                raise MemoryError(
                    "(srecfile '%s', line %d) Record type 'S5' found before header record 'S0' in S-record file" % (
                        file_name, line_number))

            if len(addr_data_csum) / 2 != byte_count:
                raise MemoryError(
                    "(srecfile '%s', line %d) Byte count mismatch for record type 'S5' in S-record file" % (
                        file_name, line_number))

            reg_exp3 = re.compile(r"([0-9A-F]{8})([0-9A-F]{2})")
            s5_search = reg_exp3.search(addr_data_csum)

            if not s3_search:
                raise MemoryError(
                    "(srecfile '%s', line %d) Invalid 'S5' record line in S-record file" % (file_name, line_number))

            s5_groups = s5_search.groups()

            if s3_record_count != int(s5_groups[0], 16):
                raise MemoryError(
                    "(srecfile '%s', line %d) Number of 'S3' records encountered does not match with that specified in 'S5' record in S-record file" % (
                        file_name, line_number))
        elif record_type == 'S7':
            if not s0_record_found:
                raise MemoryError(
                    "(srecfile '%s', line %d) Record type 'S7' found before header record 'S0' in S-record file" % (
                        file_name, line_number))

            if len(addr_data_csum) / 2 != byte_count:
                raise MemoryError(
                    "(srecfile '%s', line %d) Byte count mismatch for record type 'S5' in S-record file" % (
                        file_name, line_number))

            reg_exp4 = re.compile(r"([0-9A-F]{8})([0-9A-F]{2})")
            s7_search = reg_exp4.search(addr_data_csum)

            if not s3_search:
                raise MemoryError(
                    "(srecfile '%s', line %d) Invalid 'S7' record line in S-record file" % (file_name, line_number))

            s7_record_found = True
            s7_groups = s7_search.groups()

            exec_start_addr = int(s7_groups[0], 16)
        elif record_type == 'S8':
            if not s0_record_found:
                raise MemoryError(
                    "(srecfile '%s', line %d) Record type 'S8' found before header record 'S0' in S-record file" % (
                        file_name, line_number))

            raise MemoryError("(srecfile '%s', line %d) Unimplemented record type 'S8' found in S-record file" % (
                file_name, line_number))
        elif record_type == 'S9':
            if not s0_record_found:
                raise MemoryError(
                    "(srecfile '%s', line %d) Record type 'S9' found before header record 'S0' in S-record file" % (
                        file_name, line_number))

            raise MemoryError("(srecfile '%s', line %d) Unimplemented record type 'S9' found in S-record file" % (
                file_name, line_number))
        else:
            raise MemoryError("(srecfile '%s', line %d) Unknown record type '%s' in S-record file" % (
                file_name, line_number, record_type))

    if not s7_record_found:
        raise MemoryError("(srecfile '%s', line %d) Record type 'S7' not found but EOF encountered in S-record file" % (
            file_name, line_number))

    f.close()

    for base in parse_memory.keys():
        memory[base] = []
        for dword_offset in range(0, 0x10000, 4):
            dword = parse_memory[base].get(dword_offset, fill_byte_str) + \
                    parse_memory[base].get((dword_offset + 1), fill_byte_str) + \
                    parse_memory[base].get((dword_offset + 2), fill_byte_str) + \
                    parse_memory[base].get((dword_offset + 3), fill_byte_str)
            memory[base].append(int(dword, 16))

    return memory
# Mod7: end

# Mod7: begin
cdef inline dict build_intel_memory(str file_name):
    # Mod7: end
    #"""
    #d = build_memory('c.chk')
    #
    #for b in d.keys():
    #    for o in d[b].keys():
    #        print "%08X:%04X-%04X (%d) %08X-%08X" % (b, o, o + len(d[b][o]) * 4 - 1, len(d[b][o]), d[b][o][0], d[b][o][-1])
    #"""
    cpdef unsigned long line_number = 0
    cpdef long base_address = -1
    cpdef dict memory = {}

    try:
        f = open(file_name, "rt")
    except BaseException as e:
        raise MemoryError(e)

    reg_exp1 = re.compile(r":([0-9A-F]{2})([0-9A-F]{4})([0-9A-F]{2})((?:[0-9A-F]{0,32}))([0-9A-F]{2})")
    reg_exp2 = re.compile(r"([0-9A-F]{8})([0-9A-F]{8})([0-9A-F]{8})([0-9A-F]{8})")

    for line in f:
        line_number += 1
        record_search = reg_exp1.search(line)
        if not record_search:
            raise MemoryError("(hexfile '%s', line %d) Invalid i960 hex file format" % (file_name, line_number))

        record_groups = record_search.groups()

        byte_count = int(record_groups[0], 16)
        offset = int(record_groups[1], 16)
        record_type = int(record_groups[2], 16)
        record = record_groups[3]
        checksum = int(record_groups[4], 16)

        # Record that indicates the end of Intel hex file.
        # bug fix for bug in their hex file (stupid world) 02/08/2013 (begin stupidity)
        if (line.strip() == ":000000001FF") or (record_type == 1):  #if record_type == 1: # before stupidity
            # bug fix for bug in their hex file (stupid world) 02/08/2013 (end stupidity)
            break
        # Record that indicates the start of a block.
        elif record_type == 4:
            # base address is 4 nibbles so maximum value is 0xFFFF 64 KB
            base_address = int(record, 16) << 16
            code_record_offset_address = offset_address = offset
            memory[(base_address, offset_address)] = []
        # Record that contains executable code.
        elif record_type == 0:
            if base_address == -1:
                raise MemoryError(
                    "(hexfile '%s', line %d) Block encountered before start of block record in i960 hex file" % (
                        file_name, line_number))

            if offset <> code_record_offset_address:
                raise MemoryError(
                    "(hexfile '%s', line %d) Offset address jump encountered in code record in i960 hex file" % (
                        file_name, line_number))

            code_record_offset_address += 0x10

            code_search = reg_exp2.search(record)

            if not code_search:
                raise MemoryError(
                    "(hexfile '%s', line %d) Corrupted code record in i960 hex file" % (file_name, line_number))

            code_groups = code_search.groups()

            for dword in code_groups:
                # 16K dwords (64KB) is the maximum size of a block
                if len(memory[(base_address, offset_address)]) == (16 * 1024):
                    raise MemoryError(
                        "(hexfile '%s', line %d) Block size exceeds maximum allowed size of 16K dwords in i960 hex file" % (
                            file_name, line_number))

                memory[(base_address, offset_address)].append(
                    int(dword[6:8] + dword[4:6] + dword[2:4] + dword[0:2], 16))
        else:
            raise MemoryError("(hexfile '%s', line %d) Unknown record type in i960 hex file" % (file_name, line_number))

    f.close()

    # 10/02/2015: hari
    # for DFCC ATP some .chk files have a strange start of block record with out an actual block
    # just before the end record. These can be detected here by checking for memory[(base_address, offset_address)] == []
    # and deleting such entries
    for key in memory.keys():
        if len(memory[key]) == 0:
            del memory[key]

    return memory

# Mod7: begin
cdef inline dict build_memory(str file_name):
    if cfg.config_file.is_configured_for_ADC() or cfg.config_file.is_configured_for_LADC() or cfg.config_file.is_configured_for_DFCC():
        return build_intel_memory(file_name)
    elif cfg.config_file.is_configured_for_DFCC_MK1A() or cfg.config_file.is_configured_for_DFCC_MK2():
        return build_motorola_memory(file_name)
    else:
        raise MemoryError("Unknown UUT name specified in 'config.dat' file")
# Mod7: end

cpdef tuple download_from_file(str file_name):
    cdef list download_result = []
    cpdef dict memory = {}

    memory = build_memory(file_name)

    # Information
    # Theoretically a chunk can have a maximum of 0xFFFF bytes
    # (4 nibbles in offset portion) that is 64KB.
    # There can be a maximum of 0xFFFF (4 nibbles in base address position)
    # that is 64K chunks in a hex file.
    # Thus a hex file can contain a maximum of 4GB of data to be
    # written.
    # Code running on SPIL processor card can transfer only 64 KB of
    # data in contiguous locations to/from system.
    sorted_memory_addresses = memory.keys()
    sorted_memory_addresses.sort()
    block_number = 0
    for base_address, offset_address in sorted_memory_addresses:
        block_number += 1
        block_of_16k_dwords = memory[(base_address, offset_address)]
        cfg.progress_bar.update_progress_message('Block number %d / %d' % (block_number, len(sorted_memory_addresses)))
        download_result.append(download_block((base_address + offset_address),
                                              (base_address + (offset_address + (len(block_of_16k_dwords) * 4) - 4)),
                                              block_of_16k_dwords))

    spil_nrt_end()

    return tuple(download_result)

cpdef spil_nrt_end():
    GlobalSHM_task[0].spil_task.ucFlag = 4

cpdef tuple find_checksum(unsigned long start_address, unsigned long end_address):
    cdef list result = ["unused", "unused", "unused", "unused"]
    cdef list status = [0x0, 0x0, 0x0, 0x0]

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_transaction_id(channel, 0x9)
            write_dpram_start_address(channel, start_address)
            write_dpram_end_address(channel, end_address)
            write_dpram_data_type(channel, 4)

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_nrt_begin()

    for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
        if channel_enabled(channel):
            while read_dpram_command_status(channel):
                sleep(0.01)  #pass

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            result[channel - 1] = "0x%x" % read_dpram_data(channel, 0x0)
            status[channel - 1] = read_dpram_response_status(channel)

    spil_nrt_end()

    return {'start_address': start_address, 'end_address': end_address, 'value': tuple(result),
            'status': tuple(status)},

cdef inline unsigned long transform(unsigned long data):
    #
    # 78563412 to 12345678
    #

    cdef unsigned long b1, b2, b3, b4

    b1 = (data & 0x000000FF) << 24  # 12000000
    b2 = (data & 0x0000FF00) << 8  # 00340000
    b3 = (data & 0x00FF0000) >> 8  # 00005600
    b4 = (data & 0xFF000000) >> 24  # 00000078

    return b1 + b2 + b3 + b4

# Mod7: begin
cdef inline unsigned char motorola_checksum(char *record):
    cdef unsigned long byte_count = 0, address_b1 = 0, address_b2 = 0, address_b3 = 0, address_b4 = 0, data_b1 = 0, \
        data_b2 = 0, data_b3 = 0, data_b4 = 0, data_b5 = 0, data_b6 = 0, data_b7 = 0, data_b8 = 0, \
        data_b9 = 0, data_b10 = 0, data_b11 = 0, data_b12 = 0, data_b13 = 0, data_b14 = 0, \
        data_b15 = 0, data_b16 = 0
    cdef unsigned char sum_

    sscanf(record, "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x", &byte_count,
           &address_b1, &address_b2, &address_b3, &address_b4, &data_b1, &data_b2, &data_b3, &data_b4, &data_b5,
           &data_b6, &data_b7, &data_b8, &data_b9, &data_b10, &data_b11, &data_b12, &data_b13, &data_b14, &data_b15,
           &data_b16)

    sum_ = (
        byte_count + address_b1 + address_b2 + address_b3 + address_b4 + data_b1 + data_b2 + data_b3 + data_b4 + data_b5 + data_b6 + data_b7 + data_b8 + data_b9 + data_b10 + data_b11 + data_b12 + data_b13 + data_b14 + data_b15 + data_b16)

    return ~sum_
# Mod7: end

cdef inline unsigned char checksum(char *record):
    cdef unsigned long record_length = 0, load_offset1 = 0, load_offset2 = 0, record_type = 0, data_b1 = 0, \
        data_b2 = 0, data_b3 = 0, data_b4 = 0, data_b5 = 0, data_b6 = 0, data_b7 = 0, data_b8 = 0, \
        data_b9 = 0, data_b10 = 0, data_b11 = 0, data_b12 = 0, data_b13 = 0, data_b14 = 0, \
        data_b15 = 0, data_b16 = 0
    cdef unsigned char sum_

    sscanf(record, ":%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x", &record_length,
           &load_offset1, &load_offset2, &record_type, &data_b1, &data_b2, &data_b3, &data_b4, &data_b5, &data_b6,
           &data_b7, &data_b8, &data_b9, &data_b10, &data_b11, &data_b12, &data_b13, &data_b14, &data_b15, &data_b16)

    sum_ = (
        record_length + load_offset1 + load_offset2 + record_type + data_b1 + data_b2 + data_b3 + data_b4 + data_b5 + data_b6 + data_b7 + data_b8 + data_b9 + data_b10 + data_b11 + data_b12 + data_b13 + data_b14 + data_b15 + data_b16)

    return ~sum_ + 1

# Mod7: begin
cpdef tuple upload_to_motorola_file(unsigned long start_address, unsigned long end_address, str file_name):
    cdef list result = ["unused", "unused", "unused", "unused"]
    cdef list status = [0x0, 0x0, 0x0, 0x0]
    cdef unsigned long block_count, from_address, block_start_address, block_end_address
    cdef str channel_file_name
    cdef list channel_file = [None, None, None, None]
    cdef list upload_result = []

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            channel_file_name = "%s.ch%d" % (file_name, channel)

            try:
                channel_file[channel - 1] = open(channel_file_name, "wt")
            except BaseException as e:
                raise MemoryError(e)

            try:
                os.chown(channel_file_name, int(os.getenv("SUDO_UID")), int(os.getenv("SUDO_GID")))
            except TypeError:  # If we are not running under "sudo", environment variables "SUDO_UID" and
                pass  # "SUDO_GID" will not be set and there is no point in changing the ownership

    block_start_address = (start_address / (64 * 1024)) * 0x10000
    block_end_address = ((end_address / (64 * 1024)) * 0x10000) + 0x10000

    block_count = (block_end_address - block_start_address) / ((64 * 1024) - 1)

    block_number = 0
    block_from_addresses = xrange(block_start_address, block_end_address, (64 * 1024))

    # write start record
    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            #
            # S0 0F 0000657874466C6173684D6B0000 F9
            #
            record = "1948617269204B6972616E204B"
            channel_file[channel - 1].write("S0%s%02X\n" % (record, motorola_checksum(record)))

    for from_address in block_from_addresses:
        block_number += 1
        cfg.progress_bar.update_progress_message('Uploading block %d / %d' % (block_number, len(block_from_addresses)))
        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                write_dpram_transaction_id(channel, 0x2)
                write_dpram_start_address(channel, from_address)
                write_dpram_end_address(channel, (from_address + ((64 * 1024) - 1)))

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                write_dpram_command_status(channel, 0xAAAAAAAA)
                spil_nrt_begin()

        for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
            if channel_enabled(channel):
                counter = 0
                while counter < 12:  #1000000:
                    counter = 0
                    while read_dpram_command_status(channel):
                        sleep(0.1)
                        counter += 1
                    if read_dpram_response_status(channel):
                        break
                    if counter < 12:  #1000000:
                        write_dpram_command_status(channel, 0xAAAAAAAA)
                        spil_nrt_begin()

        # read, convert and write to hex file
        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                for offset in xrange(0, (16 * 1024), 0x4):
                    #
                    # S3 21 20000000 005A0000 2000000C 912DF68A 7C6000A6 64630200 7C600124 3CA0C3F8 17 (but only 4 DWORDS)
                    #
                    dword1 = read_dpram_data(channel, offset)
                    dword2 = read_dpram_data(channel, offset + 0x1)
                    dword3 = read_dpram_data(channel, offset + 0x2)
                    dword4 = read_dpram_data(channel, offset + 0x3)
                    byte_count = 21  # 1 address * 4 + 4 data * 4 + 1 checksum
                    offset_address = offset * 4  # DWORD offset * bytes in DWORD
                    record = "%02X%04X%04X%08X%08X%08X%08X" % (
                        byte_count, (from_address >> 16), offset_address, dword1, dword2, dword3, dword4)
                    channel_file[channel - 1].write("S3%s%02X\n" % (record, motorola_checksum(record)))

        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                result[channel - 1] = "uploaded"
                status[channel - 1] = read_dpram_response_status(channel)

        upload_result.append(
            {'start_address': from_address, 'end_address': (from_address + ((64 * 1024) - 1)), 'value': tuple(result),
             'status': tuple(status)})

    # write end record and close hex file
    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            #
            # S5 05 00000CDC 12
            #
            record = "05%08X" % (block_number * 0x1000)  # S3 record count is multiple of 4096 (0x1000)
            channel_file[channel - 1].write("S5%s%02X\n" % (record, motorola_checksum(record)))
            #
            # S7 05 2000 BCA8 76
            #
            record = "0500000000"  # Start of execution address assumed 0 (0x0)
            channel_file[channel - 1].write("S7%s%02X\n" % (record, motorola_checksum(record)))

            channel_file[channel - 1].close()

    spil_nrt_end()

    return tuple(upload_result)
# Mod7: end

# Mod7: begin
cpdef tuple upload_to_intel_file(unsigned long start_address, unsigned long end_address, str file_name):
    # Mod7: end
    cdef list result = ["unused", "unused", "unused", "unused"]
    cdef list status = [0x0, 0x0, 0x0, 0x0]
    cdef unsigned long block_count, from_address, block_start_address, block_end_address
    cdef str channel_file_name
    cdef list channel_file = [None, None, None, None]
    cdef list upload_result = []

    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            channel_file_name = "%s.ch%d" % (file_name, channel)

            try:
                channel_file[channel - 1] = open(channel_file_name, "wt")
            except BaseException as e:
                raise MemoryError(e)

            try:
                os.chown(channel_file_name, int(os.getenv("SUDO_UID")), int(os.getenv("SUDO_GID")))
            except TypeError:  # If we are not running under "sudo", environment variables "SUDO_UID" and
                pass  # "SUDO_GID" will not be set and there is no point in changing the ownership

    block_start_address = (start_address / (64 * 1024)) * 0x10000
    block_end_address = ((end_address / (64 * 1024)) * 0x10000) + 0x10000

    block_count = (block_end_address - block_start_address) / ((64 * 1024) - 1)

    block_number = 0
    block_from_addresses = xrange(block_start_address, block_end_address, (64 * 1024))
    for from_address in block_from_addresses:
        block_number += 1
        cfg.progress_bar.update_progress_message('Uploading block %d / %d' % (block_number, len(block_from_addresses)))
        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                write_dpram_transaction_id(channel, 0x2)
                write_dpram_start_address(channel, from_address)
                write_dpram_end_address(channel, (from_address + ((64 * 1024) - 1)))

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                write_dpram_command_status(channel, 0xAAAAAAAA)
                spil_nrt_begin()

        for channel in xrange(1, 5):  #for channel from 1 <= channel < 5:#locking up :-(
            if channel_enabled(channel):
                counter = 0
                while counter < 12:  #1000000:
                    counter = 0
                    while read_dpram_command_status(channel):
                        sleep(0.1)
                        counter += 1
                    if read_dpram_response_status(channel):
                        break
                    if counter < 12:  #1000000:
                        write_dpram_command_status(channel, 0xAAAAAAAA)
                        spil_nrt_begin()

        # read, convert and write to hex file
        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                #
                # :02 0000 04 0000 FA
                # :02 0000 04 0001 F9
                #
                record = ":02000004%04X" % (from_address >> 16)
                channel_file[channel - 1].write("%s%02X\n" % (record, checksum(record)))
                for offset in xrange(0, (16 * 1024), 0x4):
                    #
                    # :10 0000 00 12345678 ABCDEF12 3456789A BCDEF123 E7
                    # :10 0010 00 07F6FFFF 00000000 00000000 F8FFFFFF F0
                    #
                    dword1 = transform(read_dpram_data(channel, offset))
                    dword2 = transform(read_dpram_data(channel, offset + 0x1))
                    dword3 = transform(read_dpram_data(channel, offset + 0x2))
                    dword4 = transform(read_dpram_data(channel, offset + 0x3))
                    record = ":10%04X00%08X%08X%08X%08X" % ((offset * 0x4), dword1, dword2, dword3, dword4)
                    channel_file[channel - 1].write("%s%02X\n" % (record, checksum(record)))

        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if channel_enabled(channel):
                result[channel - 1] = "uploaded"
                status[channel - 1] = read_dpram_response_status(channel)

        upload_result.append(
            {'start_address': from_address, 'end_address': (from_address + ((64 * 1024) - 1)), 'value': tuple(result),
             'status': tuple(status)})

    # write end record and close hex file
    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            #
            # :00 0000 01 FF
            #
            record = ":00000001"
            channel_file[channel - 1].write("%s%02X\n" % (record, checksum(record)))
            channel_file[channel - 1].close()

    spil_nrt_end()

    return tuple(upload_result)

# Mod7: begin
cpdef tuple upload_to_file(unsigned long start_address, unsigned long end_address, str file_name):
    if cfg.config_file.is_configured_for_ADC() or cfg.config_file.is_configured_for_LADC() or cfg.config_file.is_configured_for_DFCC():
        return upload_to_intel_file(start_address, end_address, file_name)
    elif cfg.config_file.is_configured_for_DFCC_MK1A() or cfg.config_file.is_configured_for_DFCC_MK2():
        return upload_to_motorola_file(start_address, end_address, file_name)
    else:
        raise MemoryError("Unknown UUT name specified in 'config.dat' file")
# Mod7: end

cdef dict compare_hex_files(unsigned long start_address, unsigned long end_address, str temp_file_name,
                            str hex_file_name):
    cdef dict differences = {}

    temp_memory = build_memory(temp_file_name)
    hex_memory = build_memory(hex_file_name)

    for temp_base_address, temp_offset_address in temp_memory.keys():
        block_address = temp_base_address + temp_offset_address
        try:
            hex_16K_block = hex_memory[(temp_base_address, temp_offset_address)]
        except KeyError:
            raise MemoryError("No block starting at 0x%X in %s file '%s'" % (block_address,
                                                                             "S-record" if cfg.config_file.is_configured_for_DFCC_MK2() else "i960 hex",
                                                                             hex_file_name))

        temp_16K_block = temp_memory[(temp_base_address, temp_offset_address)]

        for block_index in xrange(len(temp_16K_block)):
            temp_dword = temp_16K_block[block_index]

            absolute_address = temp_base_address + (temp_offset_address + (block_index * 0x4))

            try:
                hex_dword = hex_16K_block[block_index]
            except:
                raise MemoryError("No dword at 0x%X in %s file '%s'" % (absolute_address,
                                                                        "S-record" if cfg.config_file.is_configured_for_DFCC_MK2() else "i960 hex",
                                                                        hex_file_name))

            if (temp_dword != hex_dword) and (
                        (absolute_address >= start_address) and (absolute_address <= end_address)):
                differences[absolute_address] = (temp_dword, hex_dword)

    return differences

cpdef dict verify_memory(unsigned long start_address, unsigned long end_address, str file_name):
    cdef list channel_differences = ["unused", "unused", "unused", "unused"]

    try:
        f = open(file_name, "rt")
    except BaseException as e:
        raise MemoryError(e)

    f.close()
    #

    # Create a temporary file and upload the contiguous memory blocks of interest to that file
    temp_hex_file = tempfile.NamedTemporaryFile(suffix='.tmp', prefix='dump-', dir='/tmp/')
    temp_hex_file.close()
    result = upload_to_file(start_address, end_address,
                            "%s%s" % (cfg.config_file.get_uploadpath(""), temp_hex_file.name.split('/')[-1]))[-1]

    # Now, call comare_hex_files on all the uploaded hex files for each channel with the specified hex file
    for channel from 1 <= channel < 5:
        if channel_enabled(channel):
            channel_differences[channel - 1] = {'differences': compare_hex_files(start_address, end_address,
                                                                                 '%s%s.ch%d' % (
                                                                                     cfg.config_file.get_uploadpath(""),
                                                                                     temp_hex_file.name.split('/')[-1],
                                                                                     channel), file_name)}
            channel_differences[channel - 1]['status'] = result['status'][channel - 1]
            os.remove('%s%s.ch%d' % (cfg.config_file.get_uploadpath(""), temp_hex_file.name.split('/')[-1], channel))

    return {'start_address': start_address, 'end_address': end_address, 'channels': tuple(channel_differences)}

cpdef inline wait_for_transition():
    cdef unsigned char state = 0, transition_variable = 0

    while 1:
        transition_variable = read_transition_variable()
        if not transition_variable and (state == 0):
            state = 1

        if transition_variable and (state == 1):
            break

cpdef unsigned long get_frame_number():
    return GlobalSHM_task[0].common_task.ulTaskIter

cdef inline unsigned char channel_enabled(unsigned char channel):
    return effective_mask[channel - 1]

cpdef set_mask(unsigned char mask):
    effective_mask[0] = (mask >> 3) & 0x1
    effective_mask[1] = (mask >> 2) & 0x1
    effective_mask[2] = (mask >> 1) & 0x1
    effective_mask[3] = mask & 0x1

cpdef list spil_cache = []
cpdef spil_cache_iter

cpdef read_spil():
    global spil_cache_iter
    return spil_cache_iter.next()

cpdef write_spil():
    global spil_cache_iter
    return spil_cache_iter.next()

# Mod3: begin
# modified reg_poke_nc
# parameters = (address1, data1, dtype1, mask1, effective_mask1, ...)
cpdef tuple spil_symbol_write(tuple parameters):
    cdef unsigned long transaction_count, transaction_number, frame_number
    cdef list result, status, return_value = []
    cdef unsigned char channel
    cdef unsigned int chan_transaction_count[4]

    frame_number = get_frame_number()

    chan_transaction_count[0] = 0
    chan_transaction_count[1] = 0
    chan_transaction_count[2] = 0
    chan_transaction_count[3] = 0

    transaction_count = len(parameters) / 5

    for transaction_number from 0 <= transaction_number < transaction_count:
        for channel from 1 <= channel < 5:
            if parameters[(5 * transaction_number) + 4][channel - 1]:  # if channel enabled
                chan_transaction_count[channel - 1] += 1
                write_dpram_command_area_address(channel, chan_transaction_count[channel - 1],
                                                 parameters[5 * transaction_number])
                write_dpram_command_area_data(channel, chan_transaction_count[channel - 1],
                                              parameters[(5 * transaction_number) + 1])
                write_dpram_command_area_data_type(channel, chan_transaction_count[channel - 1],
                                                   parameters[(5 * transaction_number) + 2])
                write_dpram_command_area_mask(channel, chan_transaction_count[channel - 1],
                                              parameters[(5 * transaction_number) + 3])

    for channel from 1 <= channel < 5:
        if chan_transaction_count[channel - 1]:
            write_dpram_transaction_id(channel, 0xC)
            write_dpram_transaction_count(channel, chan_transaction_count[channel - 1])

    for channel from 1 <= channel < 5:
        if chan_transaction_count[channel - 1]:
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_rt_begin()

    for channel in xrange(1, 5):
        if chan_transaction_count[channel - 1]:
            while read_dpram_command_status(channel):
                sleep(0.0001)

    for transaction_number from 0 <= transaction_number < transaction_count:
        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if parameters[(5 * transaction_number) + 4][channel - 1]:
                result[channel - 1] = "written"
                status[channel - 1] = read_dpram_response_status(channel)

        return_value.append(
            {'frame': frame_number, 'address': parameters[5 * transaction_number], 'value': tuple(result),
             'status': tuple(status)})

    return tuple(return_value)
# Mod3: end

# Mod3: begin
# modified peek_nc
# parameters = (address1, dtype1, mask1, effective_mask1, ...)
cpdef tuple spil_symbol_read(tuple parameters):
    cdef unsigned long transaction_count, transaction_number, frame_number
    cdef list result, status, return_value = []
    cdef unsigned char channel
    cdef unsigned int chan_transaction_count[4]
    cdef unsigned int temp_transactions[4]

    frame_number = get_frame_number()

    chan_transaction_count[0] = 0
    chan_transaction_count[1] = 0
    chan_transaction_count[2] = 0
    chan_transaction_count[3] = 0

    transaction_count = len(parameters) / 4
    t = time()
    for transaction_number from 0 <= transaction_number < transaction_count:
        for channel from 1 <= channel < 5:
            if parameters[(4 * transaction_number) + 3][channel - 1]:  # if channel enabled
                chan_transaction_count[channel - 1] += 1
                write_dpram_command_area_address(channel, chan_transaction_count[channel - 1],
                                                 parameters[4 * transaction_number])
                write_dpram_command_area_data_type(channel, chan_transaction_count[channel - 1],
                                                   parameters[(4 * transaction_number) + 1])
                write_dpram_command_area_mask(channel, chan_transaction_count[channel - 1],
                                              parameters[(4 * transaction_number) + 2])

    t = time()
    for channel from 1 <= channel < 5:
        if chan_transaction_count[channel - 1]:
            write_dpram_transaction_id(channel, 0x6)
            write_dpram_transaction_count(channel, chan_transaction_count[channel - 1])

    for channel from 1 <= channel < 5:
        if chan_transaction_count[channel - 1]:
            write_dpram_command_status(channel, 0xAAAAAAAA)

    spil_rt_begin()

    for channel from 1 <= channel < 5:
        if chan_transaction_count[channel - 1]:
            while read_dpram_command_status(channel):
                sleep(0.0001)

    temp_transactions[0] = 0
    temp_transactions[1] = 0
    temp_transactions[2] = 0
    temp_transactions[3] = 0

    for transaction_number from 0 <= transaction_number < transaction_count:
        result = ["unused", "unused", "unused", "unused"]
        status = [0x0, 0x0, 0x0, 0x0]

        for channel from 1 <= channel < 5:
            if parameters[(4 * transaction_number) + 3][channel - 1]:
                # Mod2: begin
                address = parameters[4 * transaction_number]
                # Mod9: begin
                result[channel - 1] = apply_address_mask(address,
                                                         read_dpram_data(channel, temp_transactions[channel - 1]))
                # Mod9: end
                # Mod2: end
                status[channel - 1] = read_dpram_response_status(channel)
                temp_transactions[channel - 1] += 1

        return_value.append(
            {'frame': frame_number, 'address': parameters[4 * transaction_number], 'value': tuple(result),
             'status': tuple(status)})

    return tuple(return_value)
# Mod3: end

def prefetch_spil(list args):
    global spil_cache, spil_cache_iter
    cdef str typecode
    cdef unsigned char channel
    #cdef tuple results
    cdef list data_status = []
    cdef unsigned long i

    spil_cache = []
    parameter = []

    if all(map(lambda arg: arg['write'], args)):  # write
        for arg in args:
            # Mod3: begin
            set_symbolmask(cfg.global_mask, arg['user_mask'], arg['symbol'].get_chan())
            # Mod3: end
            data_status.append(
                prefetch_write_spil_begin(arg['symbol'], arg['user_mask'], arg['user_offset'], arg['bypass'],
                                          arg['data']))
            # Mod3: begin
            # Mod6: begin
            parameter += [(arg['symbol'].get_addr() + arg['user_offset']), data_status[-1]['data'],
                          arg['symbol'].get_dtype(arg['bypass']), arg['symbol'].get_mask(arg['bypass']),
                          (effective_mask[0], effective_mask[1], effective_mask[2], effective_mask[3])]
            # Mod6: end
            # Mod3: end

        # Mod3: begin
        results = spil_symbol_write(tuple(parameter))
        # Mod3: end

        for i from 0 <= i < len(args):
            spil_cache.append(
                {'unit': '' if args[i]['bypass'] else args[i]['symbol'].get_unit(), 'bypass': args[i]['bypass'],
                 'frame': results[i]['frame'], 'value': results[i]['value'], 'status': (
                    data_status[i]['status'] | results[i]['status'][0],
                    data_status[i]['status'] | results[i]['status'][1],
                    data_status[i]['status'] | results[i]['status'][2],
                    data_status[i]['status'] | results[i]['status'][3])})
    elif all(map(lambda arg: not arg['write'], args)):
        for arg in args:
            # Mod3: begin
            set_symbolmask(cfg.global_mask, arg['user_mask'], arg['symbol'].get_chan())
            # Mod3: end
            # Mod3: begin
            # Mod6: begin
            parameter += [(arg['symbol'].get_addr() + arg['user_offset']), arg['symbol'].get_dtype(arg['bypass']),
                          arg['symbol'].get_mask(arg['bypass']),
                          (effective_mask[0], effective_mask[1], effective_mask[2], effective_mask[3])]
            # Mod6: end
            # Mod3: end

        # Mod3: begin
        results = spil_symbol_read(tuple(parameter))
        # Mod3: end

        for i from 0 <= i < len(args):
            spil_cache.append(prefetch_read_spil_end(args[i]['symbol'], args[i]['user_mask'], args[i]['user_offset'],
                                                     args[i]['bypass'], results[i]))
    else:
        raise MemoryError("Cannot combine SPIL reads and writes")

    spil_cache_iter = iter(spil_cache)

##################1553
msgid_temp = 0
bus_configuration_is_present = {1: False, 2: False}
bus_message_count = {1: 0, 2: 0}
bus_message_count_total = {1: 0, 2: 0}
bus_mframe_count_total = {1: 0, 2: 0}
bus_simulatedrt_count = {1: 0, 2: 0}
old_bus_simulatedrt_count = {1: 0, 2: 0}
simulated_rt = {}
bus_channel_map = {1: "A", 2: "A"}
cdef dict mil1553_messages_bus1 = {}
cdef dict mil1553_messages_bus2 = {}

def message_msgtype(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    try:
        if bus == 1:
            return mil1553_messages_bus1[msgid]['msgtype']
        if bus == 2:
            return mil1553_messages_bus2[msgid]['msgtype']
    except KeyError:
        raise MemoryError("message_msgtype(): Message ID, bus combination not defined")

def message_rtaddr1(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    try:
        if bus == 1:
            return mil1553_messages_bus1[msgid]['rtaddr1']
        if bus == 2:
            return mil1553_messages_bus2[msgid]['rtaddr1']
    except KeyError:
        raise MemoryError("message_rtaddr1(): Message ID, bus combination not defined")

def message_rtsubaddr1(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    try:
        if bus == 1:
            return mil1553_messages_bus1[msgid]['rtsubaddr1']
        if bus == 2:
            return mil1553_messages_bus2[msgid]['rtsubaddr1']
    except KeyError:
        raise MemoryError("message_rtsubaddr1(): Message ID, bus combination not defined")

def message_rtaddr2(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    try:
        if bus == 1:
            return mil1553_messages_bus1[msgid]['rtaddr2']
        if bus == 2:
            return mil1553_messages_bus2[msgid]['rtaddr2']
    except KeyError:
        raise MemoryError("message_rtaddr2(): Message ID, bus combination not defined")

def message_rtsubaddr2(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    try:
        if bus == 1:
            return mil1553_messages_bus1[msgid]['rtsubaddr2']
        if bus == 2:
            return mil1553_messages_bus2[msgid]['rtsubaddr2']
    except KeyError:
        raise MemoryError("message_rtsubaddr2(): Message ID, bus combination not defined")

def message_wcntmcode(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    try:
        if bus == 1:
            return mil1553_messages_bus1[msgid]['wcnt_mcode']
        if bus == 2:
            return mil1553_messages_bus2[msgid]['wcnt_mcode']
    except KeyError:
        raise MemoryError("message_wcntmcode(): Message ID, bus combination not defined")

def message_info(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    msgtype_map = {1: "BC to RT", 2: "RT to BC", 3: "RT to RT", 5: "Broadcast", 7: "Modecode Tx", 8: "Modecode Rx"}
    tx_rx_map = {1: "R", 2: "T", 5: "T", 7: "T", 8: "R"}
    msgtype = mil1553_messages_bus1[msgid]['msgtype']
    try:
        # messagetype, commandword1, commandword2,
        if bus == 1:
            if msgtype == 3:
                return 'Message Information: %s, %s-T-%s-%s, %s-R-%s-%s' % (
                    msgtype_map[msgtype], mil1553_messages_bus1[msgid]['rtaddr1'],
                    mil1553_messages_bus1[msgid]['rtsubaddr1'], mil1553_messages_bus1[msgid]['wcnt_mcode'],
                    mil1553_messages_bus1[msgid]['rtaddr2'], mil1553_messages_bus1[msgid]['rtsubaddr2'],
                    mil1553_messages_bus1[msgid]['wcnt_mcode'])
            else:
                return 'Message Information: %s, %s-%s-%s-%s' % (
                    msgtype_map[msgtype], mil1553_messages_bus1[msgid]['rtaddr1'],
                    mil1553_messages_bus1[msgid]['rtsubaddr1'], tx_rx_map[msgtype],
                    mil1553_messages_bus1[msgid]['wcnt_mcode'])

        if bus == 2:
            if msgtype == 3:
                return 'Message Information: %s, %s-T-%s-%s, %s-R-%s-%s' % (
                    msgtype_map[msgtype], mil1553_messages_bus2[msgid]['rtaddr1'],
                    mil1553_messages_bus2[msgid]['rtsubaddr1'], mil1553_messages_bus2[msgid]['wcnt_mcode'],
                    mil1553_messages_bus2[msgid]['rtaddr2'], mil1553_messages_bus2[msgid]['rtsubaddr2'],
                    mil1553_messages_bus2[msgid]['wcnt_mcode'])
            else:
                return 'Message Information: %s, %s-%s-%s-%s' % (
                    msgtype_map[msgtype], mil1553_messages_bus2[msgid]['rtaddr1'],
                    mil1553_messages_bus2[msgid]['rtsubaddr1'], tx_rx_map[msgtype],
                    mil1553_messages_bus2[msgid]['wcnt_mcode'])

    except KeyError:
        raise MemoryError("message_info(): Message ID, bus combination not defined")

def message_msggap(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    try:
        if bus == 1:
            return mil1553_messages_bus1[msgid]['msggap']
        if bus == 2:
            return mil1553_messages_bus2[msgid]['msggap']
    except KeyError:
        raise MemoryError("message_msgtype(): Message ID, bus combination not defined")

def message_defined(msgid, bus):
    global mil1553_messages_bus1, mil1553_messages_bus2
    if bus == 1:
        return mil1553_messages_bus1.has_key(msgid)
    if bus == 2:
        return mil1553_messages_bus2.has_key(msgid)

def store_message(msgid, bus, msgtype, rtaddr1, rtsubaddr1, rtaddr2, rtsubaddr2, wcnt_mcode, msggap):
    global mil1553_messages_bus1, mil1553_messages_bus2, msgid_map_bus1, msgid_map_bus2, message_map_bus1, message_map_bus2

    if (bus_message_count[bus] == 1) and (bus_message_count_total[bus] == 0):
        if bus == 1:
            mil1553_messages_bus1 = {}
            msgid_map_bus1 = {}
            message_map_bus1 = {}
        if bus == 2:
            mil1553_messages_bus2 = {}
            msgid_map_bus2 = {}
            message_map_bus2 = {}

    if bus == 1:
        mil1553_messages_bus1[msgid] = {'msgtype': msgtype, 'rtaddr1': rtaddr1, 'rtsubaddr1': rtsubaddr1,
                                        'rtaddr2': rtaddr2, 'rtsubaddr2': rtsubaddr2, 'wcnt_mcode': wcnt_mcode,
                                        'msggap': msggap}
    if bus == 2:
        mil1553_messages_bus2[msgid] = {'msgtype': msgtype, 'rtaddr1': rtaddr1, 'rtsubaddr1': rtsubaddr1,
                                        'rtaddr2': rtaddr2, 'rtsubaddr2': rtsubaddr2, 'wcnt_mcode': wcnt_mcode,
                                        'msggap': msggap}

def increment_total_mframe_count(bus):
    global bus_mframe_count_total
    bus_mframe_count_total[bus] += 1

def increment_total_message_count(bus):
    global bus_message_count, bus_message_count_total
    bus_message_count_total[bus] += bus_message_count[bus]

def increment_message_count(bus):
    global bus_message_count
    bus_message_count[bus] += 1

def reset_message_count(bus):
    global bus_message_count
    bus_message_count[bus] = 0

def reconfigure_busses():
    global bus_configuration_is_present, bus_message_count_total, bus_mframe_count_total

    status = {'bus1': {'processed': False, 'messages': 0, 'frames': 0},
              'bus2': {'processed': False, 'messages': 0, 'frames': 0}}

    if bus_configuration_is_present[1]:
        GlobalSHM_task[0].mil1553_task.config_struct.uc1553BConfigure[0] = 1
        GlobalSHM_task[0].mil1553_task.total_messages[0] = bus_message_count_total[1]
        GlobalSHM_task[0].mil1553_task.no_of_minor_frames[0] = bus_mframe_count_total[1]
        status['bus1']['processed'] = True
        status['bus1']['messages'] = bus_message_count_total[1]
        status['bus1']['frames'] = bus_mframe_count_total[1]

    if bus_configuration_is_present[2]:
        GlobalSHM_task[0].mil1553_task.config_struct.uc1553BConfigure[1] = 1
        GlobalSHM_task[0].mil1553_task.total_messages[1] = bus_message_count_total[2]
        GlobalSHM_task[0].mil1553_task.no_of_minor_frames[1] = bus_mframe_count_total[2]
        status['bus2']['processed'] = True
        status['bus2']['messages'] = bus_message_count_total[2]
        status['bus2']['frames'] = bus_mframe_count_total[2]

    return status

cpdef inline get_true_msgid(msgid, rtaddr, rtsubaddr, wcnt_mcode, tx_rx, bus):
    global message_map_bus1, message_map_bus2

    if bus == 1:
        if message_map_bus1.has_key((rtaddr, rtsubaddr, wcnt_mcode, tx_rx)):
            true_msgid = message_map_bus1[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)]
        else:
            true_msgid = msgid
            message_map_bus1[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)] = true_msgid

    if bus == 2:
        if message_map_bus2.has_key((rtaddr, rtsubaddr, wcnt_mcode, tx_rx)):
            true_msgid = message_map_bus2[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)]
        else:
            true_msgid = msgid
            message_map_bus2[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)] = true_msgid

    return true_msgid

cpdef inline get_true_bc_msgid(msgid, rtaddr, rtsubaddr, wcnt_mcode, tx_rx, bus):
    global bc_message_map_bus1, bc_message_map_bus2

    if bus == 1:
        if bc_message_map_bus1.has_key((rtaddr, rtsubaddr, wcnt_mcode, tx_rx)):
            true_msgid = bc_message_map_bus1[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)]
        else:
            true_msgid = msgid
            bc_message_map_bus1[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)] = true_msgid

    if bus == 2:
        if bc_message_map_bus2.has_key((rtaddr, rtsubaddr, wcnt_mcode, tx_rx)):
            true_msgid = bc_message_map_bus2[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)]
        else:
            true_msgid = msgid
            bc_message_map_bus2[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx)] = true_msgid

    return true_msgid

def generate_msgid_map(msgid, msgtype, rtaddr1, rtsubaddr1, rtaddr2, rtsubaddr2, wcnt_mcode, bus):
    global msgid_map_bus1, msgid_map_bus2, bc_msgid_map_bus1, bc_msgid_map_bus2

    if bus == 1:
        if (msgtype == 1) or (msgtype == 5):  # BC->RT, BROADCAST
            msgid_map_bus1[(msgid, False)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
            bc_msgid_map_bus1[(msgid, False)] = get_true_bc_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
        elif msgtype == 2:  # RT->BC
            msgid_map_bus1[(msgid, True)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
            bc_msgid_map_bus1[(msgid, True)] = get_true_bc_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
        elif msgtype == 3:  # RT<->RT
            # transmitter
            msgid_map_bus1[(msgid, True)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
            # receiver
            msgid_map_bus1[(msgid, False)] = get_true_msgid(msgid, rtaddr2, rtsubaddr2, wcnt_mcode, False, bus)
        elif msgtype == 7:  # MC TX
            msgid_map_bus1[(msgid, True)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
        elif msgtype == 8:  # MC RX
            msgid_map_bus1[(msgid, False)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)

    if bus == 2:
        if (msgtype == 1) or (msgtype == 5):  # BC->RT, BROADCAST
            msgid_map_bus2[(msgid, False)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
            bc_msgid_map_bus2[(msgid, False)] = get_true_bc_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
        elif msgtype == 2:  # RT->BC
            msgid_map_bus2[(msgid, True)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
            bc_msgid_map_bus2[(msgid, True)] = get_true_bc_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
        elif msgtype == 3:  # RT<->RT
            # transmitter
            msgid_map_bus2[(msgid, True)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
            # receiver
            msgid_map_bus2[(msgid, False)] = get_true_msgid(msgid, rtaddr2, rtsubaddr2, wcnt_mcode, False, bus)
        elif msgtype == 7:  # MC TX
            msgid_map_bus2[(msgid, True)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)
        elif msgtype == 8:  # MC RX
            msgid_map_bus2[(msgid, False)] = get_true_msgid(msgid, rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)

def configure_rtmessage(rtaddr, rtsubaddr, wcnt_mcode, tx_rx, simulated, bus):
    global simulated_rt, bus_simulatedrt_count

    simulated_rt[(rtaddr, rtsubaddr, wcnt_mcode, tx_rx, bus)] = simulated

def configure_bcmessage(msgid, msgtype, rtaddr1, rtsubaddr1, rtaddr2, rtsubaddr2, wcnt_mcode, msggap, bus):
    global bus_configuration_is_present, simulated_rt, bus_channel_map
    modecode_txrx = {0: 1, 1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 16: 1, 17: 0, 18: 1, 19: 1, 20: 0, 21: 0}

    if (msgtype == 1) or (msgtype == 5):  # BC->RT
        if not simulated_rt.has_key((rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)):
            raise MemoryError(rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
    elif msgtype == 2:  # RT->BC
        if not simulated_rt.has_key((rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)):
            raise MemoryError(rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
    elif msgtype == 3:  # RT<->RT
        if not simulated_rt.has_key((rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)):
            raise MemoryError(rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
        if not simulated_rt.has_key((rtaddr2, rtsubaddr2, wcnt_mcode, False, bus)):
            raise MemoryError(rtaddr2, rtsubaddr2, wcnt_mcode, False, bus)
    elif msgtype == 7:  # MC TX
        if not simulated_rt.has_key((rtaddr1, rtsubaddr1, wcnt_mcode, True, bus)):
            raise MemoryError(rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)
    elif msgtype == 8:  # MC RX
        if not simulated_rt.has_key((rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)):
            raise MemoryError(rtaddr1, rtsubaddr1, wcnt_mcode, False, bus)

    increment_message_count(bus)

    store_message(msgid, bus, msgtype, rtaddr1, rtsubaddr1, rtaddr2, rtsubaddr2, wcnt_mcode, msggap)

    bus_configuration_is_present[bus] = True

    # tagCTRLWRD MessageControlWord[2][512]
    # tagCMDWRD  BCMessageCommandWord1[2][512]
    # tagCMDWRD  BCMessageCommandWord2[2][512]

    GlobalSHM_task[0].mil1553_task.config_struct.message_type[bus - 1][msgid - 1] = msgtype

    # MessageControlWord
    if msgtype == 3:
        GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].RTtoRTFormat = 0b1
    if rtaddr1 == 31:
        GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].BroadCastFormat = 0b1
    if rtsubaddr1 == 31:
        GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].ModeCodeFormat = 0b1
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].MIL_1553_A_B_Sel = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].EOMIntEnable = 0b1
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].MaskBroadCastBit = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].OffLineSelfTest = 0b0
    if bus_channel_map[bus] == "A":
        GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].BusChannelA_B = 0b1
    elif bus_channel_map[bus] == "B":
        GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].BusChannelA_B = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].RetryEnabled = 0b1
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].ReservedBitsMask = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].TerminalFlagMask = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].SubSysFlagMask = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].SubSysBusyMask = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].ServiceRqstMask = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].MsgErrorMask = 0b0
    GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1][msgid - 1].Dummy = 0b0

    GlobalSHM_task[0].mil1553_task.config_struct.MessageGapTime[bus - 1][msgid - 1] = msggap

    # BCMessageCommandWord2
    if msgtype == 3:  # RT to RT
        # interchanged RTMessageCommandWord1 and RTMessageCommandWord2 values because kernel module
        # is making use of only RTMessageCommandWord1 ?????????????????????????????????????????????
        # receiver (second)
        # BCMessageCommandWord1
        flag = simulated_rt.get((rtaddr2, rtsubaddr2, wcnt_mcode, False, bus), False)
        if flag:
            GlobalSHM_task[0].mil1553_task.config_struct.rt_rx_simulated[bus - 1][msgid - 1] = 1
            bus_simulatedrt_count[bus] += 1
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].WrdCnt_ModeCode = wcnt_mcode
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].SubAddr_ModeCode = rtsubaddr2
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].Tx_Rx = 0
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].RTAddress = rtaddr2
        else:
            GlobalSHM_task[0].mil1553_task.config_struct.rt_rx_simulated[bus - 1][msgid - 1] = 0

        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][
            msgid - 1].WrdCnt_ModeCode = wcnt_mcode
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][
            msgid - 1].SubAddr_ModeCode = rtsubaddr2
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][msgid - 1].Tx_Rx = 0
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][msgid - 1].RTAddress = rtaddr2

        # for AIM card
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].RTAddress = rtaddr2
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].SubAddr_ModeCode = rtsubaddr2
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].Tx_Rx = 0
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].WrdCnt_ModeCode = wcnt_mcode
        if flag:
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].simulated[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[
                    bus - 1].ucNoOfRTs] = 1  #for handling RT to RT, by Venu
        else:
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].simulated[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[
                    bus - 1].ucNoOfRTs] = 0  #for handling RT to RT, by Venu
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs += 1

        # transmitter (first)
        # BCMessageCommandWord2
        flag = simulated_rt.get((rtaddr1, rtsubaddr1, wcnt_mcode, True, bus), False)
        if flag:
            GlobalSHM_task[0].mil1553_task.config_struct.rt_tx_simulated[bus - 1][msgid - 1] = 1
            bus_simulatedrt_count[bus] += 1
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].WrdCnt_ModeCode = wcnt_mcode
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].SubAddr_ModeCode = rtsubaddr1
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].Tx_Rx = 1
            GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                bus_simulatedrt_count[bus] - 1].RTAddress = rtaddr1
        else:
            GlobalSHM_task[0].mil1553_task.config_struct.rt_tx_simulated[bus - 1][msgid - 1] = 0

        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord2[bus - 1][
            msgid - 1].WrdCnt_ModeCode = wcnt_mcode
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord2[bus - 1][
            msgid - 1].SubAddr_ModeCode = rtsubaddr1
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord2[bus - 1][msgid - 1].Tx_Rx = 1
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord2[bus - 1][msgid - 1].RTAddress = rtaddr1

        # for AIM card
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].RTAddress = rtaddr1
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].SubAddr_ModeCode = rtsubaddr1
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].Tx_Rx = 1
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].WrdCnt_ModeCode = wcnt_mcode
        if flag:
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].simulated[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[
                    bus - 1].ucNoOfRTs] = 1  #for handling RT to RT, by Venu
        else:
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].simulated[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[
                    bus - 1].ucNoOfRTs] = 0  #for handling RT to RT, by Venu
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs += 1
    else:  # not RT to RT
        # BCMessageCommandWord1
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][
            msgid - 1].WrdCnt_ModeCode = wcnt_mcode
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][
            msgid - 1].SubAddr_ModeCode = rtsubaddr1
        GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][msgid - 1].RTAddress = rtaddr1

        # for AIM card
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].RTAddress = rtaddr1
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].SubAddr_ModeCode = rtsubaddr1
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].WrdCnt_ModeCode = wcnt_mcode

        if (msgtype == 1) or (msgtype == 5):  # BC to RT or Broadcast
            flag = simulated_rt.get((rtaddr1, rtsubaddr1, wcnt_mcode, False, bus), False)

            if flag:
                GlobalSHM_task[0].mil1553_task.config_struct.rt_rx_simulated[bus - 1][msgid - 1] = 1
                bus_simulatedrt_count[bus] += 1
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].Tx_Rx = 0
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].WrdCnt_ModeCode = wcnt_mcode
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].SubAddr_ModeCode = rtsubaddr1
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].RTAddress = rtaddr1

            else:
                GlobalSHM_task[0].mil1553_task.config_struct.rt_rx_simulated[bus - 1][msgid - 1] = 0

            GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][msgid - 1].Tx_Rx = 0

            # for AIM card
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].Tx_Rx = 0

        if msgtype == 2:  # RT to BC
            flag = simulated_rt.get((rtaddr1, rtsubaddr1, wcnt_mcode, True, bus), False)

            if flag:
                GlobalSHM_task[0].mil1553_task.config_struct.rt_tx_simulated[bus - 1][msgid - 1] = 1
                bus_simulatedrt_count[bus] += 1
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].Tx_Rx = 1
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].WrdCnt_ModeCode = wcnt_mcode
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].SubAddr_ModeCode = rtsubaddr1
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].RTAddress = rtaddr1

            else:
                GlobalSHM_task[0].mil1553_task.config_struct.rt_tx_simulated[bus - 1][msgid - 1] = 0

            GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][msgid - 1].Tx_Rx = 1

            # for AIM card
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].Tx_Rx = 1

        if (msgtype == 7) or (msgtype == 8):  # Modecode Tx or Modecode Rx
            flag = simulated_rt.get((rtaddr1, rtsubaddr1, wcnt_mcode, True, bus), False) or simulated_rt.get(
                (rtaddr1, rtsubaddr1, wcnt_mcode, False, bus), False)

            if flag:
                if msgtype == 7:
                    GlobalSHM_task[0].mil1553_task.config_struct.rt_tx_simulated[bus - 1][msgid - 1] = 1
                elif msgtype == 8:
                    GlobalSHM_task[0].mil1553_task.config_struct.rt_rx_simulated[bus - 1][msgid - 1] = 1
                bus_simulatedrt_count[bus] += 1
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].Tx_Rx = modecode_txrx[wcnt_mcode]
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].WrdCnt_ModeCode = wcnt_mcode
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].SubAddr_ModeCode = rtsubaddr1
                GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1][
                    bus_simulatedrt_count[bus] - 1].RTAddress = rtaddr1

            else:
                if msgtype == 7:
                    GlobalSHM_task[0].mil1553_task.config_struct.rt_tx_simulated[bus - 1][msgid - 1] = 0
                elif msgtype == 8:
                    GlobalSHM_task[0].mil1553_task.config_struct.rt_rx_simulated[bus - 1][msgid - 1] = 0

            GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1][msgid - 1].Tx_Rx = \
                modecode_txrx[wcnt_mcode]

            # for AIM card
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].rtStruct[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs].Tx_Rx = modecode_txrx[
                wcnt_mcode]

        # for AIM card

        if flag:
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].simulated[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[
                    bus - 1].ucNoOfRTs] = 1  #for handling RT to RT, by Venu
        else:
            GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].simulated[
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[
                    bus - 1].ucNoOfRTs] = 0  #for handling RT to RT, by Venu
        GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs += 1

def frame_bcmessage(minorframeno, minorframetime, bus):
    global bus_message_count, bus_simulatedrt_count, old_bus_simulatedrt_count

    increment_total_mframe_count(bus)
    increment_total_message_count(bus)

    GlobalSHM_task[0].mil1553_task.config_struct.BCMinorFrameStruct[bus - 1][minorframeno - 1].FrameNo = minorframeno
    GlobalSHM_task[0].mil1553_task.config_struct.BCMinorFrameStruct[bus - 1][minorframeno - 1].NoOfMsgInFrame = \
        bus_message_count[bus]
    GlobalSHM_task[0].mil1553_task.config_struct.BCMinorFrameStruct[bus - 1][minorframeno - 1].RepeatCount = 1
    GlobalSHM_task[0].mil1553_task.config_struct.BCMinorFrameStruct[bus - 1][
        minorframeno - 1].usFrameTime = minorframetime

    GlobalSHM_task[0].mil1553_task.config_struct.RTMinorFrameStruct[bus - 1][minorframeno - 1].FrameNo = minorframeno
    GlobalSHM_task[0].mil1553_task.config_struct.RTMinorFrameStruct[bus - 1][minorframeno - 1].NoOfMsgInFrame = \
        bus_simulatedrt_count[bus] - old_bus_simulatedrt_count[bus]
    GlobalSHM_task[0].mil1553_task.config_struct.RTMinorFrameStruct[bus - 1][minorframeno - 1].RepeatCount = 1

    old_bus_simulatedrt_count[bus] = bus_simulatedrt_count[bus]
    reset_message_count(bus)

def configure_buschannel(bus, channel, retry):
    global bus_channel_map

    memset(GlobalSHM_task[0].mil1553_task.config_struct.MessageControlWord[bus - 1], 0, (sizeof(tagCTRLWRD) * 512))
    memset(GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord1[bus - 1], 0, (sizeof(tagCMDWRD) * 512))
    memset(GlobalSHM_task[0].mil1553_task.config_struct.BCMessageCommandWord2[bus - 1], 0, (sizeof(tagCMDWRD) * 512))
    memset(GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord1[bus - 1], 0, (sizeof(tagCMDWRD) * 512))
    memset(GlobalSHM_task[0].mil1553_task.config_struct.RTMessageCommandWord2[bus - 1], 0, (sizeof(tagCMDWRD) * 512))
    memset(GlobalSHM_task[0].mil1553_task.config_struct.RTMinorFrameStruct[bus - 1], 0, (sizeof(tagFRAMEDET) * 512))
    memset(GlobalSHM_task[0].mil1553_task.config_struct.BCMinorFrameStruct[bus - 1], 0, (sizeof(tagBCFRAMEDET) * 512))

    # 03/07/2013 bug fix: initialization total RT numbers on a bus on every reconfiguration
    GlobalSHM_task[0].mil1553_task.config_struct.RT_List[bus - 1].ucNoOfRTs = 0
    bus_channel_map[bus] = channel

    GlobalSHM_task[0].mil1553_task.retry_enabled[bus - 1] = int(bool(retry))
    #Commented for new modue 11/09/2014#GlobalSHM_task[0].mil1553_task.number_of_retries[bus - 1] = retry
    #Commented for new modue 11/09/2014#GlobalSHM_task[0].mil1553_task.alternate_first_retry_bus[bus - 1] = 1 # retry on alternate bus

    if bus_channel_map[bus] == "A":
        GlobalSHM_task[0].mil1553_task.primary_secondary_bus[bus - 1] = 0
    if bus_channel_map[bus] == "B":
        GlobalSHM_task[0].mil1553_task.primary_secondary_bus[bus - 1] = 1

def parse_1553b_config(filename):
    global msgid_temp

    #GlobalSHM_task[0].mil1553_task.config_struct.RT_List[0].ucNoOfRTs = 0 # commented Venu toretain memory of the other bus
    #GlobalSHM_task[0].mil1553_task.config_struct.RT_List[1].ucNoOfRTs = 0
    line_number = 0
    transmit_receive = {"TX": True, "RX": False}
    simulation_status = {"TRUE": True, "FALSE": False}
    reg_exp1 = re.compile(r";")
    # CNFGRTMES 21,01,1,0000h,MCBSIM1
    # CNFGRTMES rtaddr=21,rtsubaddr=01,wcnt_mcode=16,tx/rx,simulated=true/false,bus=1/2
    reg_exp2 = re.compile(
        r"CNFGRTMES\s+RTADDR\s*=\s*(\d+)\s*,\s*RTSUBADDR\s*=\s*(\d+)\s*,\s*WCNT_MCODE\s*=\s*(\d+)\s*,\s*(TX|RX)\s*,\s*SIMULATED\s*=\s*(TRUE|FALSE)\s*,\s*BUS\s*=\s*(1|2)\s*")
    # CNFGBCMES  65,2,21,11,16,000Bh,MCBSIM1
    # CNFGBCMES  msgid=65,msgtype=2,rtaddr1=21,rtsubaddr1=11,{rtaddr2=20,rtsubaddr2=10,}wcnt_mcode=16,msggap=20.0(ms),bus=1/2
    reg_exp3 = re.compile(
        r"CNFGBCMES\s+MSGID\s*=\s*(\d+)\s*,\s*MSGTYPE\s*=\s*(\d+)\s*,\s*RTADDR1\s*=\s*(\d+)\s*,\s*RTSUBADDR1\s*=\s*(\d+)\s*,\s*(?:RTADDR2\s*=\s*(\d+)\s*,\s*RTSUBADDR2\s*=\s*(\d+)\s*,\s*)?WCNT_MCODE\s*=\s*(\d+)\s*,\s*MSGGAP\s*=\s*(\d+(?:.\d+)?)\s*,\s*BUS\s*=\s*(1|2)\s*")
    # FRAMEBCMES    1,MCBSIM1
    # FRAMEBCMES    minorframeno=1,minorframetime=20.0(ms),bus=1/2
    reg_exp4 = re.compile(
        r"FRAMEBCMES\s+MINORFRAMENO\s*=\s*(\d+)\s*,\s*MINORFRAMETIME\s*=\s*(\d+(?:.\d+)?)\s*,\s*BUS\s*=\s*(1|2)\s*")
    # CNFGBUSCHAN   BUS = 1, CHAN = A, RETRY = 0
    reg_exp5 = re.compile(r"CNFGBUSCHAN\s+BUS\s*=\s*(1|2)\s*,\s*CHAN\s*=\s*(A|B)\s*,\s*RETRY\s*=\s*(\d+)\s*")

    try:
        f = open(filename)
    except IOError as e:
        message = "Configuration file '%s' I/O error, %s" \
                  % (filename, e.strerror.lower())
        raise MemoryError(message)

    for line in f:
        line_number += 1
        line = line.upper()
        line_split = reg_exp1.split(line)

        if line_split[0] and not line_split[0].isspace():
            cfg_rtmessage = reg_exp2.search(line_split[0])
            cfg_bcmessage = reg_exp3.search(line_split[0])
            frm_bcmessage = reg_exp4.search(line_split[0])
            cfg_buschan = reg_exp5.search(line_split[0])

            if cfg_rtmessage:
                cfg_rtmessage_groups = cfg_rtmessage.groups()
                configure_rtmessage(rtaddr=int(cfg_rtmessage_groups[0]), rtsubaddr=int(cfg_rtmessage_groups[1]),
                                    wcnt_mcode=int(cfg_rtmessage_groups[2]),
                                    tx_rx=transmit_receive[cfg_rtmessage_groups[3]],
                                    simulated=simulation_status[cfg_rtmessage_groups[4]],
                                    bus=int(cfg_rtmessage_groups[5]))
            elif cfg_bcmessage:
                cfg_bcmessage_groups = cfg_bcmessage.groups()
                msgid_temp += 1

                if msgid_temp != int(cfg_bcmessage_groups[0]):
                    message = "(cfgfile '%s', line %d) Non-sequential message ID detected, found '%d' but expected '%d'" \
                              % (filename, line_number, int(cfg_bcmessage_groups[0]), msgid_temp)
                    raise MemoryError(message)

                try:
                    configure_bcmessage(msgid=msgid_temp,
                                        msgtype=int(cfg_bcmessage_groups[1]), rtaddr1=int(cfg_bcmessage_groups[2]),
                                        rtsubaddr1=int(cfg_bcmessage_groups[3]),
                                        rtaddr2=(
                                            0 if cfg_bcmessage_groups[4] is None else int(cfg_bcmessage_groups[4])),
                                        rtsubaddr2=(
                                            0 if cfg_bcmessage_groups[5] is None else int(cfg_bcmessage_groups[5])),
                                        wcnt_mcode=int(cfg_bcmessage_groups[6]), msggap=float(cfg_bcmessage_groups[7]),
                                        bus=int(cfg_bcmessage_groups[8]))
                except MemoryError as e:  #rtaddr1, rtsubaddr1, wcnt_mcode, tx_rx, bus
                    message = "(cfgfile '%s', line %d) RT message %d-%c-%d-%d not defined for bus %d" \
                              % (filename, line_number, e[0], {True: "T", False: "R"}[e[3]], e[1], e[2], e[4])
                    raise MemoryError(message)

                generate_msgid_map(msgid=msgid_temp,
                                   msgtype=int(cfg_bcmessage_groups[1]), rtaddr1=int(cfg_bcmessage_groups[2]),
                                   rtsubaddr1=int(cfg_bcmessage_groups[3]),
                                   rtaddr2=(0 if cfg_bcmessage_groups[4] is None else int(cfg_bcmessage_groups[4])),
                                   rtsubaddr2=(0 if cfg_bcmessage_groups[5] is None else int(cfg_bcmessage_groups[5])),
                                   wcnt_mcode=int(cfg_bcmessage_groups[6]), bus=int(cfg_bcmessage_groups[8]))
            elif frm_bcmessage:
                frm_bcmessage_groups = frm_bcmessage.groups()
                frame_bcmessage(minorframeno=int(frm_bcmessage_groups[0]),
                                minorframetime=float(frm_bcmessage_groups[1]) * 10.0, bus=int(frm_bcmessage_groups[2]))
            elif cfg_buschan:
                cfg_buschan_groups = cfg_buschan.groups()
                bus = int(cfg_buschan_groups[0])  #added by Venu
                GlobalSHM_task[0].mil1553_task.config_struct.RT_List[
                    bus - 1].ucNoOfRTs = 0  #added by Venu to clear the bus
                configure_buschannel(bus=int(cfg_buschan_groups[0]), channel=cfg_buschan_groups[1],
                                     retry=int(cfg_buschan_groups[2]))
            else:
                message = "(cfgfile '%s', line %d) Syntax error in configuration file" \
                          % (filename, line_number)
                raise MemoryError(message)

    f.close()

def init1553b(filename):
    global bus_configuration_is_present, bus_message_count, bus_message_count_total, bus_mframe_count_total, bus_simulatedrt_count, old_bus_simulatedrt_count, simulated_rt, msgid_temp, mil1553_messages_bus1, mil1553_messages_bus2

    msgid_temp = 0
    bus_configuration_is_present[1] = False
    bus_configuration_is_present[2] = False
    bus_message_count[1] = 0
    bus_message_count_total[1] = 0
    bus_message_count[2] = 0
    bus_message_count_total[2] = 0
    bus_mframe_count_total[1] = 0
    bus_mframe_count_total[2] = 0
    bus_simulatedrt_count[1] = 0
    bus_simulatedrt_count[2] = 0
    old_bus_simulatedrt_count[1] = 0
    old_bus_simulatedrt_count[2] = 0
    simulated_rt = {}
    bus_channel_map[1] = "A"
    bus_channel_map[2] = "A"
    #mil1553_messages = {} 04/07/2013 Venu's requirement to not reset one bus info when other bus's configuration is loaded

    parse_1553b_config(filename)
    return reconfigure_busses()
