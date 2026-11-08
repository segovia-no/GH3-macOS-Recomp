// Dump every basic block of every function as `start<TAB>end` (hex VAs,
// end inclusive). tools/find_false_entries.py uses it to tell real pointers
// into a function's middle (SEH handlers, catch blocks, switch targets: all
// block starts) from constants that merely fall inside code.
//
// Headless:
//   analyzeHeadless work/ghidra GH3 -process GH3.exe -noanalysis -readOnly \
//     -scriptPath tools/ghidra -postScript ExportBlockStarts.java <out.txt>
//@category Recomp

import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.block.BasicBlockModel;
import ghidra.program.model.block.CodeBlock;
import ghidra.program.model.block.CodeBlockIterator;

public class ExportBlockStarts extends GhidraScript {
  @Override
  protected void run() throws Exception {
    String[] args = getScriptArgs();
    String out = args.length > 0 ? args[0] : "blockstarts.txt";
    BasicBlockModel model = new BasicBlockModel(currentProgram);
    int n = 0;
    try (PrintWriter w = new PrintWriter(out)) {
      CodeBlockIterator it = model.getCodeBlocks(monitor);
      while (it.hasNext() && !monitor.isCancelled()) {
        CodeBlock b = it.next();
        w.printf("%08X\t%08X%n", b.getFirstStartAddress().getOffset(),
            b.getMaxAddress().getOffset());
        n++;
      }
    }
    println("ExportBlockStarts: " + n + " blocks -> " + out);
  }
}
