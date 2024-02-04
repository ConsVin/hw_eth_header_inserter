import warnings
import itertools
import logging
import random
import numpy as np
from  scapy.all import Ether,Raw

import cocotb
import cocotbext
from cocotb.triggers import Timer
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotbext.axi import (AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamMonitor)
from cocotb.binary import BinaryValue
    
def hexify(arr):
    return ''.join( [ "%02X "%x  for x in arr])

class EthernetHeaderTB(object):

    def __init__(self, dut, debug=False):
        self.dut = dut
        # AxiStreamSource/Monitor doesn't support callbacks
        # And AxiStreamMonitor is incompatible with Scoreboard
        self.stream_in   =  AxiStreamSource(AxiStreamBus.from_prefix(dut, "data_in" ), dut.clk, dut.rst)
        self.stream_out  = AxiStreamMonitor(AxiStreamBus.from_prefix(dut, "data_out"), dut.clk, dut.rst)
        
        self.expected_output = []
        self.actual_output = []
        # Set verbosity on our various interfaces
        level = logging.DEBUG if debug else logging.WARNING
        self.stream_in.log.setLevel(level)
        self.stream_out.log.setLevel(level)
        self.dut._log.setLevel(level)
        ##
        self.err_cnt   = 0
        self.packet_rx = 0
        self.packet_tx = 0
        self.eth_cfg = {
            'dst'  : self.dut.dbg.c_dst_mac.value.buff,
            'src'  : self.dut.dbg.c_src_mac.value.buff,
            'type' : self.dut.dbg.c_eth_type.value.integer,
        }
        
    def model(self, transaction):
        eth_packet = Ether(**self.eth_cfg)/transaction
        self.expected_output.append(bytearray(eth_packet.build()))
    def show_err_log(self, exp, rx):
        self.dut._log.error("Exp: " + hexify(exp))
        self.dut._log.error("Rx : " + hexify(rx))
        s = []
        for i in range(min(len(exp),len(rx))):
            if ( exp[i]==rx[i]):
                s+=["  "]
            else:
                s+=["~~"]
        self.dut._log.error("Err: "+ " ".join(s))
   
    async def monitor(self):
        while(1):
            data = await self.stream_out.recv()# compact=True
            self.packet_rx+=1
            expected = self.expected_output[0]
            self.expected_output.pop(0)
            if (expected != data.tdata):
                self.show_err_log(expected, data.tdata)
                self.err_cnt += 1
            else:
                self.dut._log.debug(f"Correctly recieved {len(data)}B packet")

    async def send(self, payload):
        await self.stream_in.send(payload)
        self.model(payload)
        self.dut._log.debug("Payload         : " + hexify(payload))
        self.dut._log.debug("Expected Packet : " + hexify(self.expected_output[-1]))
        await self.stream_in.wait()
        self.packet_tx += 1
        for i in range(1): # corresponds to 2 clock gap
            await RisingEdge(self.dut.clk)

    async def reset(self, duration=20):
        self.dut.rst = 1
        await Timer(duration, units='ns')
        await RisingEdge(self.dut.clk)
        self.dut.rst = 0
        self.dut._log.debug("Out of reset")       

    def assert_state(self):
        assert self.err_cnt   == 0, "Bad packets, see error log"
        assert self.packet_rx != 0, "No packets were recieved"
        assert self.packet_tx == self.packet_rx, "Rx/Tx packet counters don't match"
        assert self.packet_rx == self.dut.dbg.rx_pkt_cnt,"RTL packet counter doesn't match"
    
    async def launch(self):
        cocotb.fork(Clock(self.dut.clk, 10, units='ns').start())
        cocotb.fork(self.monitor())
        await self.reset()

def random_ones(p_ones = 0.1):
    """Random ones and zeros"""
    while True:
        yield (np.random.uniform() > p_ones)

def cycle_pause():
    """Mostly ones"""
    return itertools.cycle([1, 1, 1, 0])

def payload_random(max_size=64):
    """Generate Random payload"""
    while(True):
        n_bytes = np.random.randint(1, max_size)
        arr = np.random.randint(0, high=255, size=n_bytes, dtype=np.uint8)
        yield arr.tobytes()
def payload_counter():
    """Generate payload, where each byte is incrementing counter value"""
    payload = bytearray()
    idx = 1
    while(True):
        payload.append(idx%256)
        yield payload
        idx+=1        


@cocotb.test()
async def test_basic(dut):
    tb = EthernetHeaderTB(dut,debug=True)
    await tb.launch()
    payload = bytearray([1, 2, 3, 4, 5, 6, 7])
    tb.dut._log.debug(f"Send 7B payload")
    await tb.send(payload)
    for i in range(3):
        await RisingEdge(dut.clk)  
    tb.dut._log.debug(f"Send 7B payload twice one by one")
    await tb.send(payload)
    await tb.send(payload)
    for i in range(3):
        await RisingEdge(dut.clk)  
    tb.dut._log.debug(f"Send 2B payload and 1B payload")
    await tb.send(payload[1:3])
    await tb.send(payload[1:2])
    for i in range(3):
        await RisingEdge(dut.clk)  
    tb.dut._log.debug(f"Send 64B payload")
    frame = (np.arange(64, dtype=np.uint8)+1).tobytes()
    await tb.send(frame)
    for i in range(3):
        await RisingEdge(dut.clk)  

@cocotb.test()
async def test_idles(dut):
    tb = EthernetHeaderTB(dut, debug=True)
    await tb.launch()
    tb.stream_in.set_pause_generator(cycle_pause())
    for n in [16,17,18,23]:
        frame = (np.arange(n, dtype=np.uint8)).tobytes()
        await tb.send(frame)
        for i in range(5):
            await RisingEdge(dut.clk)  
    # 2 periods for header + 1 period for latency
    tb.assert_state()

async def run_test(dut, payload_gen_func, idle_inserter = None):
    tb = EthernetHeaderTB(dut)
    await tb.launch()
    if (idle_inserter):
        tb.stream_in.set_pause_generator(idle_inserter())
    payload_gen = payload_gen_func()
    
    for i in range (64):
        payload = next(payload_gen)
        await tb.send(payload)
    
    # 2 periods for header + 1 period for latency
    for i in range(5):
        await RisingEdge(dut.clk)  
    tb.assert_state()

factory = TestFactory(run_test)
# idle_inserter - insert gaps, or non-valid periods, to input AXI stream
#       None        - no gaps, always valid
#       cycle_pause - repeated pattern of zeros and ones
#       random_ones - random pauses
# payload_gen_func - payload generation function
#       payload_counter - produces incrementing size packet (1B,2B, 3B) with 8b counter values of bytes
#       payload_random - generate random packet with random bytes values
factory.add_option("idle_inserter",    [None, cycle_pause, random_ones])
factory.add_option("payload_gen_func", [payload_counter,payload_random])
factory.generate_tests()