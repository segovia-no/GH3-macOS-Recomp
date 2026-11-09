// A stand-in for llvm-undname, for SwARc's tools/pe_symbols.py in the
// builder kit (no LLVM install on the user's Mac). Same line protocol:
// each input line is echoed, then its demangled form (an error goes to
// stderr instead), then a blank line. Built against LLVM's static demangler only.
#include <llvm/Demangle/Demangle.h>

#include <cstdlib>
#include <iostream>
#include <string>

int main() {
  std::string line;
  while (std::getline(std::cin, line)) {
    std::cout << line << '\n';
    int status = 0;
    char* d = llvm::microsoftDemangle(line, nullptr, &status);
    if (d && status == 0)
      std::cout << d << '\n';
    else
      std::cerr << "error: Invalid mangled name\n";
    std::cout << '\n';
    std::free(d);
  }
}
