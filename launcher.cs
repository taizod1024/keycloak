using System;
using System.Diagnostics;
using System.IO;
using System.Linq;

// Placeholder @ENTRY_SCRIPT@ is replaced with entryScript from winget.config.json at build time.
class Program {
  static int Main(string[] args) {
    string dir = Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName);
    string script = Path.Combine(dir, @"@ENTRY_SCRIPT@");
    string a = string.Join(" ", args.Select(x => x.Contains(" ") || x.Length == 0 ? "\"" + x + "\"" : x));
    var psi = new ProcessStartInfo("cmd.exe", "/d /c \"\"" + script + "\" " + a + "\"") { UseShellExecute = false };
    using (var p = Process.Start(psi)) { p.WaitForExit(); return p.ExitCode; }
  }
}
