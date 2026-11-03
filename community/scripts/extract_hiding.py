#!/usr/bin/env python3
"""Write the hiding kernel's (last step's) bytecode and precomputed VK from a Chonk ivc-inputs.msgpack.

usage: extract_hiding.py <ivc-inputs.msgpack> <out_dir>  ->  <out_dir>/hiding_bytecode, <out_dir>/vk
"""
import os
import sys

import msgpack

steps = msgpack.unpackb(open(sys.argv[1], "rb").read(), raw=False, strict_map_key=False)
last = steps[-1]
os.makedirs(sys.argv[2], exist_ok=True)
open(os.path.join(sys.argv[2], "hiding_bytecode"), "wb").write(last["bytecode"])
open(os.path.join(sys.argv[2], "vk"), "wb").write(last["vk"])
