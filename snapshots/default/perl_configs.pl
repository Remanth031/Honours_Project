#  Copyright 2019-2026 Western Digital Corporation or its affiliates.
#  Copyright 2022-2026 Antmicro <www.antmicro.com>
# 
#  SPDX-License-Identifier: Apache-2.0
#  Licensed under the Apache License, Version 2.0, see LICENSE for details.
# 
#  This is an automatically generated file by student on Sat Nov  7 10:27:02 IST 2026
# 
#  cmd:    veer -target=default 
# 
# To use this in a perf script, use 'require $RV_ROOT/configs/config.pl'
# Reference the hash via $config{name}..


%config = (
            'iccm' => {
                        'iccm_num_banks_4' => '',
                        'iccm_num_banks' => '4',
                        'iccm_enable' => 1,
                        'iccm_reserved' => '0x1000',
                        'iccm_offset' => '0xe000000',
                        'iccm_data_cell' => 'ram_4096x39',
                        'iccm_rows' => '4096',
                        'iccm_ecc_width' => '7',
                        'iccm_sadr' => '0xee000000',
                        'iccm_index_bits' => 12,
                        'iccm_size' => 64,
                        'iccm_region' => '0xe',
                        'iccm_bits' => 16,
                        'iccm_bank_index_lo' => 4,
                        'iccm_bank_hi' => 3,
                        'iccm_size_64' => '',
                        'iccm_bank_bits' => 2,
                        'iccm_eadr' => '0xee00ffff'
                      },
            'config_key' => '32\'hdeadbeef',
            'csr' => {
                       'cycle' => {
                                    'exists' => 'false'
                                  },
                       'mie' => {
                                  'reset' => '0x0',
                                  'exists' => 'true',
                                  'mask' => '0x70000888'
                                },
                       'instret' => {
                                      'exists' => 'false'
                                    },
                       'mhpmcounter5' => {
                                           'mask' => '0xffffffff',
                                           'exists' => 'true',
                                           'reset' => '0x0'
                                         },
                       'meicidpl' => {
                                       'comment' => 'External interrupt claim id priority level.',
                                       'mask' => '0xf',
                                       'reset' => '0x0',
                                       'exists' => 'true',
                                       'number' => '0xbcb'
                                     },
                       'mitcnt1' => {
                                      'mask' => '0xffffffff',
                                      'reset' => '0x0',
                                      'number' => '0x7d5',
                                      'exists' => 'true'
                                    },
                       'miccmect' => {
                                       'mask' => '0xffffffff',
                                       'reset' => '0x0',
                                       'number' => '0x7f1',
                                       'exists' => 'true'
                                     },
                       'mstatus' => {
                                      'mask' => '0x88',
                                      'reset' => '0x1800',
                                      'exists' => 'true'
                                    },
                       'meipt' => {
                                    'comment' => 'External interrupt priority threshold.',
                                    'mask' => '0xf',
                                    'number' => '0xbc9',
                                    'exists' => 'true',
                                    'reset' => '0x0'
                                  },
                       'marchid' => {
                                      'mask' => '0x0',
                                      'exists' => 'true',
                                      'reset' => '0x00000010'
                                    },
                       'mrac' => {
                                   'shared' => 'true',
                                   'mask' => '0xffffffff',
                                   'comment' => 'Memory region io and cache control.',
                                   'reset' => '0x0',
                                   'number' => '0x7c0',
                                   'exists' => 'true'
                                 },
                       'mpmc' => {
                                   'exists' => 'true',
                                   'number' => '0x7c6',
                                   'reset' => '0x2',
                                   'mask' => '0x2'
                                 },
                       'mcpc' => {
                                   'comment' => 'Core pause',
                                   'mask' => '0x0',
                                   'exists' => 'true',
                                   'number' => '0x7c2',
                                   'reset' => '0x0'
                                 },
                       'micect' => {
                                     'mask' => '0xffffffff',
                                     'reset' => '0x0',
                                     'exists' => 'true',
                                     'number' => '0x7f0'
                                   },
                       'mhpmevent4' => {
                                         'exists' => 'true',
                                         'reset' => '0x0',
                                         'mask' => '0xffffffff'
                                       },
                       'mhpmcounter4' => {
                                           'reset' => '0x0',
                                           'exists' => 'true',
                                           'mask' => '0xffffffff'
                                         },
                       'meicurpl' => {
                                       'mask' => '0xf',
                                       'comment' => 'External interrupt current priority level.',
                                       'reset' => '0x0',
                                       'exists' => 'true',
                                       'number' => '0xbcc'
                                     },
                       'mcounteren' => {
                                         'exists' => 'false'
                                       },
                       'dicad1' => {
                                     'comment' => 'Cache diagnostics.',
                                     'mask' => '0x3',
                                     'exists' => 'true',
                                     'number' => '0x7ca',
                                     'debug' => 'true',
                                     'reset' => '0x0'
                                   },
                       'mhpmcounter5h' => {
                                            'reset' => '0x0',
                                            'exists' => 'true',
                                            'mask' => '0xffffffff'
                                          },
                       'mhpmcounter3' => {
                                           'mask' => '0xffffffff',
                                           'reset' => '0x0',
                                           'exists' => 'true'
                                         },
                       'dmst' => {
                                   'mask' => '0x0',
                                   'comment' => 'Memory synch trigger: Flush caches in debug mode.',
                                   'exists' => 'true',
                                   'number' => '0x7c4',
                                   'debug' => 'true',
                                   'reset' => '0x0'
                                 },
                       'mfdhs' => {
                                    'reset' => '0x0',
                                    'exists' => 'true',
                                    'number' => '0x7cf',
                                    'comment' => 'Force Debug Halt Status',
                                    'mask' => '0x00000003'
                                  },
                       'dicawics' => {
                                       'comment' => 'Cache diagnostics.',
                                       'mask' => '0x0130fffc',
                                       'reset' => '0x0',
                                       'debug' => 'true',
                                       'exists' => 'true',
                                       'number' => '0x7c8'
                                     },
                       'mhpmevent6' => {
                                         'exists' => 'true',
                                         'reset' => '0x0',
                                         'mask' => '0xffffffff'
                                       },
                       'mscause' => {
                                      'mask' => '0x0000000f',
                                      'reset' => '0x0',
                                      'exists' => 'true',
                                      'number' => '0x7ff'
                                    },
                       'mvendorid' => {
                                        'reset' => '0x45',
                                        'exists' => 'true',
                                        'mask' => '0x0'
                                      },
                       'mitcnt0' => {
                                      'mask' => '0xffffffff',
                                      'reset' => '0x0',
                                      'number' => '0x7d2',
                                      'exists' => 'true'
                                    },
                       'misa' => {
                                   'mask' => '0x0',
                                   'reset' => '0x40001104',
                                   'exists' => 'true'
                                 },
                       'mitctl1' => {
                                      'number' => '0x7d7',
                                      'exists' => 'true',
                                      'reset' => '0x1',
                                      'mask' => '0x0000000f'
                                    },
                       'mhpmcounter4h' => {
                                            'reset' => '0x0',
                                            'exists' => 'true',
                                            'mask' => '0xffffffff'
                                          },
                       'time' => {
                                   'exists' => 'false'
                                 },
                       'mitbnd0' => {
                                      'reset' => '0xffffffff',
                                      'number' => '0x7d3',
                                      'exists' => 'true',
                                      'mask' => '0xffffffff'
                                    },
                       'mip' => {
                                  'mask' => '0x0',
                                  'reset' => '0x0',
                                  'poke_mask' => '0x70000888',
                                  'exists' => 'true'
                                },
                       'mfdc' => {
                                   'exists' => 'true',
                                   'number' => '0x7f9',
                                   'reset' => '0x00070040',
                                   'mask' => '0x00071fff'
                                 },
                       'mfdht' => {
                                    'shared' => 'true',
                                    'comment' => 'Force Debug Halt Threshold',
                                    'mask' => '0x0000003f',
                                    'number' => '0x7ce',
                                    'exists' => 'true',
                                    'reset' => '0x0'
                                  },
                       'mcgc' => {
                                   'mask' => '0x000003ff',
                                   'number' => '0x7f8',
                                   'exists' => 'true',
                                   'poke_mask' => '0x000003ff',
                                   'reset' => '0x200'
                                 },
                       'tselect' => {
                                      'mask' => '0x3',
                                      'reset' => '0x0',
                                      'exists' => 'true'
                                    },
                       'dcsr' => {
                                   'reset' => '0x40000003',
                                   'exists' => 'true',
                                   'poke_mask' => '0x00008dcc',
                                   'debug' => 'true',
                                   'mask' => '0x00008c04'
                                 },
                       'mhpmcounter3h' => {
                                            'reset' => '0x0',
                                            'exists' => 'true',
                                            'mask' => '0xffffffff'
                                          },
                       'mdccmect' => {
                                       'mask' => '0xffffffff',
                                       'reset' => '0x0',
                                       'exists' => 'true',
                                       'number' => '0x7f2'
                                     },
                       'mitctl0' => {
                                      'reset' => '0x1',
                                      'exists' => 'true',
                                      'number' => '0x7d4',
                                      'mask' => '0x00000007'
                                    },
                       'mhpmevent5' => {
                                         'mask' => '0xffffffff',
                                         'exists' => 'true',
                                         'reset' => '0x0'
                                       },
                       'mhpmcounter6h' => {
                                            'mask' => '0xffffffff',
                                            'reset' => '0x0',
                                            'exists' => 'true'
                                          },
                       'mhartid' => {
                                      'exists' => 'true',
                                      'poke_mask' => '0xfffffff0',
                                      'reset' => '0x0',
                                      'mask' => '0x0'
                                    },
                       'mcountinhibit' => {
                                            'reset' => '0x0',
                                            'exists' => 'true',
                                            'poke_mask' => '0x7d',
                                            'commnet' => 'Performance counter inhibit. One bit per counter.',
                                            'mask' => '0x7d'
                                          },
                       'dicad0' => {
                                     'comment' => 'Cache diagnostics.',
                                     'mask' => '0xffffffff',
                                     'reset' => '0x0',
                                     'debug' => 'true',
                                     'number' => '0x7c9',
                                     'exists' => 'true'
                                   },
                       'mhpmcounter6' => {
                                           'mask' => '0xffffffff',
                                           'reset' => '0x0',
                                           'exists' => 'true'
                                         },
                       'mhpmevent3' => {
                                         'reset' => '0x0',
                                         'exists' => 'true',
                                         'mask' => '0xffffffff'
                                       },
                       'dicago' => {
                                     'debug' => 'true',
                                     'exists' => 'true',
                                     'number' => '0x7cb',
                                     'reset' => '0x0',
                                     'mask' => '0x0',
                                     'comment' => 'Cache diagnostics.'
                                   },
                       'mitbnd1' => {
                                      'mask' => '0xffffffff',
                                      'number' => '0x7d6',
                                      'exists' => 'true',
                                      'reset' => '0xffffffff'
                                    },
                       'mimpid' => {
                                     'mask' => '0x0',
                                     'reset' => '0x4',
                                     'exists' => 'true'
                                   }
                     },
            'testbench' => {
                             'sterr_rollback' => '0',
                             'ext_addrwidth' => '32',
                             'CPU_TOP' => '`RV_TOP.veer',
                             'clock_period' => '100',
                             'RV_TOP' => '`TOP.rvtop_wrapper.rvtop',
                             'build_axi_native' => 1,
                             'TOP' => 'tb_top',
                             'SDVT_AHB' => 0,
                             'lderr_rollback' => '1',
                             'ext_datawidth' => '64',
                             'build_axi4' => 1
                           },
            'max_mmode_perf_event' => '516',
            'btb' => {
                       'btb_btag_fold' => 0,
                       'btb_array_depth' => 256,
                       'btb_addr_hi' => 9,
                       'btb_toffset_size' => '12',
                       'btb_enable' => '1',
                       'btb_addr_lo' => '2',
                       'btb_index2_lo' => 10,
                       'btb_index3_lo' => 18,
                       'btb_btag_size' => 5,
                       'btb_index1_hi' => 9,
                       'btb_index3_hi' => 25,
                       'btb_index1_lo' => '2',
                       'btb_fold2_index_hash' => 0,
                       'btb_size' => 512,
                       'btb_index2_hi' => 17
                     },
            'harts' => 1,
            'regwidth' => '32',
            'reset_vec' => '0x80000000',
            'pic' => {
                       'pic_bits' => 15,
                       'pic_meipl_offset' => '0x0000',
                       'pic_size' => 32,
                       'pic_meigwctrl_mask' => '0x3',
                       'pic_meigwctrl_count' => 31,
                       'pic_mpiccfg_mask' => '0x1',
                       'pic_meigwclr_count' => 31,
                       'pic_meipl_mask' => '0xf',
                       'pic_total_int_plus1' => 32,
                       'pic_meie_count' => 31,
                       'pic_meie_mask' => '0x1',
                       'pic_meip_offset' => '0x1000',
                       'pic_meipt_mask' => '0x0',
                       'pic_base_addr' => '0xf00c0000',
                       'pic_meip_mask' => '0x0',
                       'pic_total_int' => 31,
                       'pic_meigwclr_mask' => '0x0',
                       'pic_int_words' => 1,
                       'pic_region' => '0xf',
                       'pic_meipt_offset' => '0x3004',
                       'pic_meie_offset' => '0x2000',
                       'pic_mpiccfg_count' => 1,
                       'pic_meigwctrl_offset' => '0x4000',
                       'pic_meipt_count' => 31,
                       'pic_meip_count' => 1,
                       'pic_mpiccfg_offset' => '0x3000',
                       'pic_meigwclr_offset' => '0x5000',
                       'pic_offset' => '0xc0000',
                       'pic_meipl_count' => 31
                     },
            'physical' => '1',
            'tec_rv_icg' => 'clockhdr',
            'core' => {
                        'div_bit' => '4',
                        'lsu_stbuf_depth' => '4',
                        'fast_interrupt_redirect' => '1',
                        'timer_legal_en' => '1',
                        'lsu2dma' => 0,
                        'dma_buf_depth' => '5',
                        'bitmanip_zbf' => 0,
                        'bitmanip_zbp' => 0,
                        'bitmanip_zbs' => 1,
                        'fpga_optimize' => 1,
                        'icache_only' => 'derived',
                        'div_new' => 1,
                        'lsu_num_nbload_width' => '2',
                        'bitmanip_zba' => 1,
                        'bitmanip_zbe' => 0,
                        'lsu_num_nbload' => '4',
                        'bitmanip_zbc' => 1,
                        'iccm_icache' => 1,
                        'bitmanip_zbr' => 0,
                        'iccm_only' => 'derived',
                        'bitmanip_zbb' => 1,
                        'no_iccm_no_icache' => 'derived'
                      },
            'bus' => {
                       'dma_bus_id' => '1',
                       'ifu_bus_id' => '1',
                       'lsu_bus_tag' => 3,
                       'dma_bus_tag' => '1',
                       'ifu_bus_tag' => '3',
                       'ifu_bus_prty' => '2',
                       'sb_bus_prty' => '2',
                       'sb_bus_tag' => '1',
                       'lsu_bus_id' => '1',
                       'sb_bus_id' => '1',
                       'lsu_bus_prty' => '2',
                       'dma_bus_prty' => '2',
                       'bus_prty_default' => '3'
                     },
            'retstack' => {
                            'ret_stack_size' => '8'
                          },
            'memmap' => {
                          'external_data' => '0xc0580000',
                          'unused_region0' => '0x90000000',
                          'debug_sb_mem' => '0xa0580000',
                          'unused_region3' => '0x50000000',
                          'serialio' => '0xd0580000',
                          'unused_region6' => '0x20000000',
                          'unused_region5' => '0x30000000',
                          'unused_region1' => '0x70000000',
                          'external_data_1' => '0xb0000000',
                          'consoleio' => '0xd0580000',
                          'unused_region2' => '0x60000000',
                          'unused_region8' => '0x00000000',
                          'unused_region4' => '0x40000000',
                          'unused_region7' => '0x10000000'
                        },
            'triggers' => [
                            {
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ],
                              'poke_mask' => [
                                               '0x081818c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ],
                              'mask' => [
                                          '0x081818c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ]
                            },
                            {
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ],
                              'poke_mask' => [
                                               '0x081810c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ],
                              'mask' => [
                                          '0x081810c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ]
                            },
                            {
                              'mask' => [
                                          '0x081818c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ],
                              'poke_mask' => [
                                               '0x081818c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ],
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ]
                            },
                            {
                              'reset' => [
                                           '0x23e00000',
                                           '0x00000000',
                                           '0x00000000'
                                         ],
                              'poke_mask' => [
                                               '0x081810c7',
                                               '0xffffffff',
                                               '0x00000000'
                                             ],
                              'mask' => [
                                          '0x081810c7',
                                          '0xffffffff',
                                          '0x00000000'
                                        ]
                            }
                          ],
            'protection' => {
                              'inst_access_enable4' => '0x0',
                              'data_access_mask7' => '0xffffffff',
                              'data_access_mask4' => '0xffffffff',
                              'data_access_enable6' => '0x0',
                              'data_access_enable3' => '0x0',
                              'inst_access_mask7' => '0xffffffff',
                              'inst_access_addr4' => '0x00000000',
                              'inst_access_addr1' => '0x00000000',
                              'inst_access_enable3' => '0x0',
                              'data_access_enable2' => '0x0',
                              'data_access_addr7' => '0x00000000',
                              'data_access_enable4' => '0x0',
                              'inst_access_addr3' => '0x00000000',
                              'data_access_addr2' => '0x00000000',
                              'data_access_addr6' => '0x00000000',
                              'inst_access_enable7' => '0x0',
                              'data_access_addr5' => '0x00000000',
                              'data_access_addr0' => '0x00000000',
                              'inst_access_mask0' => '0xffffffff',
                              'inst_access_enable6' => '0x0',
                              'inst_access_addr2' => '0x00000000',
                              'inst_access_enable0' => '0x0',
                              'inst_access_enable5' => '0x0',
                              'inst_access_mask6' => '0xffffffff',
                              'pmp_entries' => '16',
                              'data_access_mask0' => '0xffffffff',
                              'inst_access_mask4' => '0xffffffff',
                              'inst_access_mask5' => '0xffffffff',
                              'data_access_enable0' => '0x0',
                              'inst_access_addr5' => '0x00000000',
                              'inst_access_enable1' => '0x0',
                              'data_access_mask3' => '0xffffffff',
                              'inst_access_mask2' => '0xffffffff',
                              'data_access_addr4' => '0x00000000',
                              'data_access_mask6' => '0xffffffff',
                              'data_access_mask5' => '0xffffffff',
                              'inst_access_addr0' => '0x00000000',
                              'data_access_addr3' => '0x00000000',
                              'data_access_mask2' => '0xffffffff',
                              'inst_access_mask3' => '0xffffffff',
                              'data_access_addr1' => '0x00000000',
                              'inst_access_enable2' => '0x0',
                              'data_access_mask1' => '0xffffffff',
                              'inst_access_addr7' => '0x00000000',
                              'data_access_enable1' => '0x0',
                              'inst_access_addr6' => '0x00000000',
                              'data_access_enable7' => '0x0',
                              'data_access_enable5' => '0x0',
                              'inst_access_mask1' => '0xffffffff'
                            },
            'bht' => {
                       'bht_ghr_hash_1' => '',
                       'bht_size' => 512,
                       'bht_addr_lo' => '2',
                       'bht_array_depth' => 256,
                       'bht_addr_hi' => 9,
                       'bht_ghr_range' => '7:0',
                       'bht_ghr_size' => 8,
                       'bht_hash_string' => '{hashin[8+1:2]^ghr[8-1:0]}// cf2'
                     },
            'xlen' => 32,
            'user_ec_rv_icg' => 'user_clock_gate',
            'even_odd_trigger_chains' => 'true',
            'target' => 'default',
            'num_mmode_perf_regs' => '4',
            'numiregs' => '32',
            'perf_events' => [
                               1,
                               2,
                               3,
                               4,
                               5,
                               6,
                               7,
                               8,
                               9,
                               10,
                               11,
                               12,
                               13,
                               14,
                               15,
                               16,
                               17,
                               18,
                               19,
                               20,
                               21,
                               22,
                               23,
                               24,
                               25,
                               26,
                               27,
                               28,
                               30,
                               31,
                               32,
                               34,
                               35,
                               36,
                               37,
                               38,
                               39,
                               40,
                               41,
                               42,
                               43,
                               44,
                               45,
                               46,
                               47,
                               48,
                               49,
                               50,
                               54,
                               55,
                               56,
                               512,
                               513,
                               514,
                               515,
                               516
                             ],
            'nmi_vec' => '0x11110000',
            'icache' => {
                          'icache_status_bits' => 1,
                          'icache_num_beats' => 8,
                          'icache_tag_cell' => 'ram_128x25',
                          'icache_num_lines_way' => '128',
                          'icache_num_bypass_width' => 2,
                          'icache_tag_lo' => 13,
                          'icache_data_depth' => '512',
                          'icache_index_hi' => 12,
                          'icache_tag_depth' => 128,
                          'icache_num_lines' => 256,
                          'icache_size' => 16,
                          'icache_ecc' => '1',
                          'icache_beat_bits' => 3,
                          'icache_bank_lo' => 3,
                          'icache_bypass_enable' => '1',
                          'icache_tag_index_lo' => '6',
                          'icache_enable' => 1,
                          'icache_tag_num_bypass' => '2',
                          'icache_scnd_last' => 6,
                          'icache_fdata_width' => 71,
                          'icache_num_lines_bank' => '64',
                          'icache_waypack' => '1',
                          'icache_num_bypass' => '2',
                          'icache_data_index_lo' => 4,
                          'icache_tag_num_bypass_width' => 2,
                          'icache_beat_addr_hi' => 5,
                          'icache_data_width' => 64,
                          'icache_2banks' => '1',
                          'icache_tag_bypass_enable' => '1',
                          'icache_banks_way' => 2,
                          'icache_ln_sz' => 64,
                          'icache_data_cell' => 'ram_512x71',
                          'icache_bank_bits' => 1,
                          'icache_num_ways' => 2,
                          'icache_bank_width' => 8,
                          'icache_bank_hi' => 3
                        },
            'dccm' => {
                        'dccm_region' => '0xf',
                        'dccm_enable' => '1',
                        'dccm_sadr' => '0xf0040000',
                        'dccm_rows' => '4096',
                        'lsu_sb_bits' => 16,
                        'dccm_fdata_width' => 39,
                        'dccm_num_banks_4' => '',
                        'dccm_data_width' => 32,
                        'dccm_offset' => '0x40000',
                        'dccm_eadr' => '0xf004ffff',
                        'dccm_ecc_width' => 7,
                        'dccm_bits' => 16,
                        'dccm_width_bits' => 2,
                        'dccm_bank_bits' => 2,
                        'dccm_index_bits' => 12,
                        'dccm_size_64' => '',
                        'dccm_num_banks' => '4',
                        'dccm_byte_width' => '4',
                        'dccm_reserved' => '0x1400',
                        'dccm_size' => 64,
                        'dccm_data_cell' => 'ram_4096x39'
                      }
          );
1;
