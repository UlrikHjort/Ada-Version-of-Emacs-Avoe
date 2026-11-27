# ***************************************************************************
#                             Avoe - test_hdl_modes
#
#           Copyright (C) 2026 By Ulrik Hørlyk Hjort
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# ***************************************************************************

"""VHDL, Verilog and UCF modes (share/avoe/{vhdl,verilog,ucf}-mode.avoe)."""

from harness import run, batch, ctl, check, path, finish

files = [path("hdl/a.vhd", "x\n"), path("hdl/b.vhdl", "x\n"), path("hdl/c.v", "x\n"),
         path("hdl/d.vh", "x\n"), path("hdl/e.ucf", "x\n")]
code, out, err = batch('Message (Mode_Name);\n'
                       + "".join('Select_Buffer ("%s");\nMessage (Mode_Name);\n' % n
                                 for n in ("b.vhdl", "c.v", "d.vh", "e.ucf")), files)
check("modes chosen from .vhd .vhdl .v .vh .ucf",
      code == 0 and out == "VHDL\nVHDL\nVerilog\nVerilog\nUCF\n", repr((code, out, err)))

f = path("hdl/hl.vhd", 'ENTITY top IS\n'
                       '  port (clk : in Std_Logic);  -- the clock\n'
                       'end top;\n'
                       'process begin wait until clk\'event; end process;\n')
code, out = run([f], [ctl("x"), ctl("c")])
check("VHDL: keywords in any case, types, -- comments",
      b"\x1b[1;35mENTITY" in out and b"\x1b[1;35mport" in out
      and b"\x1b[1;36mStd_Logic" in out and b"\x1b[32m-- the clock" in out
      and b"\x1b[1;35mwait" in out and b"[VHDL]" in out, repr(code))

f = path("hdl/hl.v", "module top(input wire clk);\n"
                     "  reg [7:0] r = 8'hFF;  // reset\n"
                     "  always @(posedge clk) r <= r + 1; /* count */\n"
                     "  MODULE x;\n"
                     "endmodule\n")
code, out = run([f], [ctl("x"), ctl("c")])
check("Verilog: keywords, types, comments, 8'hFF is not a string",
      b"\x1b[1;35mmodule" in out and b"\x1b[1;35mposedge" in out
      and b"\x1b[32m// reset" in out and b"\x1b[32m/* count */" in out
      and b"\x1b[1;36mreg" in out and b"\x1b[1;35mMODULE" not in out and b"[Verilog]" in out, repr(code))

f = path("hdl/hl.ucf", '# pins\n'
                       'NET "clk" LOC = "P56" | IOSTANDARD = LVCMOS33;\n'
                       'net "clk" TNM_NET = clk;  # 50 MHz\n'
                       'TIMESPEC TS_clk = PERIOD "clk" 20 ns HIGH 50%;\n')
code, out = run([f], [ctl("x"), ctl("c")])
check("UCF: statements, constraints, strings, # comments",
      b"\x1b[32m# pins" in out and b"\x1b[1;35mNET" in out and b"\x1b[1;35mnet" in out
      and b"\x1b[1;36mLOC" in out and b"\x1b[33m\"P56\"" in out
      and b"\x1b[32m# 50 MHz" in out and b"\x1b[1;35mTIMESPEC" in out
      and b"[UCF]" in out, repr(code))

finish()
