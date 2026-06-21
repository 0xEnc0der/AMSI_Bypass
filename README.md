# AMSI (Anti-Malware Scan Interface) Mechanics & Bypass Theory

AMSI (Anti-Malware Scan Interface) is a core Windows security feature. When PowerShell starts, Windows loads `amsi.dll` into the PowerShell process space. 

Before executing any script content, PowerShell passes the code to the following functions inside `amsi.dll`:

* **`AmsiScanBuffer(scriptContent)`** → Returns `CLEAN` (0) or `MALICIOUS` (1+)
* **`AmsiScanString(scriptContent)`** → Returns `CLEAN` (0) or `MALICIOUS` (1+)
* **`AmsiOpenSession(...)`** → Initializes a scan session

> [!IMPORTANT]
> If any of these functions return a value indicating `MALICIOUS`, PowerShell immediately blocks execution of the script.

---

## The Memory Patching Technique

The bypass technique patches these functions directly in the process memory so they always return `CLEAN` (0), regardless of what script content is actually passed to them.

### Step-by-Step Mechanism

1. **Locate the Functions:** Get the memory address of each target function in `amsi.dll` via:
   ```c
   GetProcAddress(GetModuleHandle("amsi.dll"), "AmsiScanBuffer")

``

2. **Modify Memory Permissions:** Change the memory protection of the target address from read-only to writable and executable using `VirtualProtect` with the `PAGE_EXECUTE_READWRITE` (`0x40`) flag.
3. **Overwrite with Assembly:** Overwrite the first few bytes of the function with machine code that forces an early, clean exit:
```assembly
xor eax, eax    ; Set return value register to 0 (AMSI_RESULT_CLEAN)
ret             ; Return immediately

```


* **x64 Hex:** `31 C0 C3`
* **x86 Hex:** `31 C0 C2 18 00`


4. **Restore Permissions:** Restore the original memory protection flags to avoid leaving anomalous `RWX` pages.
5. **Managed Flag Fallback:** Set `amsiInitFailed = true` via .NET reflection on `System.Management.Automation.AmsiUtils`. This is a separate managed internal flag that tells the runtime: *"AMSI failed to initialize, skip scanning entirely."*

---

## Result

Every script that subsequently passes through AMSI receives a `CLEAN` status instantly. Because the patched functions return `0` at the very beginning of their execution, the underlying anti-malware engine is never actually called to scan the content.
