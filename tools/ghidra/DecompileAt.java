// Decompile the functions at the given addresses into one text file,
// creating a function first where Ghidra has none (e.g. QB C-functions,
// reached only through the C-function table). With -readOnly nothing is
// saved.
//
// Headless:
//   analyzeHeadless work/ghidra GH3 -process GH3.exe -noanalysis -readOnly \
//     -scriptPath tools/ghidra -postScript DecompileAt.java <out.c> <hexva>...
//@category Recomp

import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class DecompileAt extends GhidraScript {
  @Override
  protected void run() throws Exception {
    String[] args = getScriptArgs();
    DecompInterface di = new DecompInterface();
    di.openProgram(currentProgram);
    try (PrintWriter w = new PrintWriter(args[0])) {
      for (int i = 1; i < args.length; i++) {
        Address a = toAddr(Long.parseLong(args[i], 16));
        Function f = getFunctionAt(a);
        if (f == null) {
          disassemble(a);
          f = createFunction(a, null);
        }
        if (f == null) {
          w.printf("// %s: could not create a function%n%n", args[i]);
          continue;
        }
        DecompileResults r = di.decompileFunction(f, 120, monitor);
        w.printf("// ==== %s @ %s ====%n", f.getName(true), f.getEntryPoint());
        w.println(r.decompileCompleted() ? r.getDecompiledFunction().getC()
                                         : "// decompile failed: " + r.getErrorMessage());
      }
    }
  }
}
