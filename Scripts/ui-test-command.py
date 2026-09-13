#!/usr/bin/env python3
"""Deliver a command exclusively to an offscreen test process."""
import os, pathlib, sys, time
control = pathlib.Path(os.environ['UI_TEST_CONTROL'])
control.mkdir(parents=True, exist_ok=True)
name = str(time.time_ns())
tmp = control / (name + '.tmp')
tmp.write_text(sys.argv[1])
tmp.rename(control / (name + '.command'))
