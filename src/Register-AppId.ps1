<#
.SYNOPSIS
    Registers the AppUserModelID (AUMID) for Claude Code Toast notifications.
.DESCRIPTION
    Creates a registry entry under HKCU so Windows can display branded toast
    notifications without requiring admin privileges.
    Also creates a Start menu shortcut with the AUMID property, which is
    required by Windows to route toast button activation events.
#>
param(
    [string]$Aumid = "ClaudeCode.Toast",
    [string]$DisplayName = "Claude Code",
    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $IconPath) {
    $IconPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\claude-icon.png"
}

# --- Registry entry for toast branding ---
$regPath = "HKCU:\Software\Classes\AppUserModelId\$Aumid"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

New-ItemProperty -Path $regPath -Name "DisplayName" -Value $DisplayName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "IconUri" -Value $IconPath -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "IconBackgroundColor" -Value "FFDA7738" -PropertyType String -Force | Out-Null

Write-Host "Registered AUMID: $Aumid" -ForegroundColor Green
Write-Host "  DisplayName: $DisplayName"
Write-Host "  IconUri: $IconPath"

# --- Start menu shortcut (required for toast button activation) ---
# Windows needs a .lnk with System.AppUserModel.ID to route protocol
# activation from toast action buttons back to the correct handler.
$shortcutPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Claude Code.lnk"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ToastShortcutHelper {
    [DllImport("shell32.dll", SetLastError = true)]
    static extern int SHGetPropertyStoreFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
        IntPtr pbc, int flags,
        ref Guid riid, out IntPtr ppv);

    [DllImport("ole32.dll")]
    static extern int PropVariantClear(ref PROPVARIANT pv);

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct PROPERTYKEY {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPVARIANT {
        public ushort vt;
        public ushort r1, r2, r3;
        public IntPtr data;
        public IntPtr data2;
    }

    public static void SetAppUserModelId(string lnkPath, string appId) {
        Guid IID = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        IntPtr storePtr;
        int hr = SHGetPropertyStoreFromParsingName(lnkPath, IntPtr.Zero, 2, ref IID, out storePtr);
        if (hr != 0) Marshal.ThrowExceptionForHR(hr);

        // System.AppUserModel.ID = {9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}, 5
        PROPERTYKEY key;
        key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        key.pid = 5;

        PROPVARIANT pv = new PROPVARIANT();
        pv.vt = 31; // VT_LPWSTR
        pv.data = Marshal.StringToCoTaskMemUni(appId);

        // IPropertyStore::SetValue is at vtable index 6, Commit at index 7
        // SetValue(PROPERTYKEY, PROPVARIANT)
        var setValue = Marshal.GetDelegateForFunctionPointer<SetValueDelegate>(
            Marshal.ReadIntPtr(Marshal.ReadIntPtr(storePtr), 6 * IntPtr.Size));
        hr = setValue(storePtr, ref key, ref pv);

        // Commit()
        var commit = Marshal.GetDelegateForFunctionPointer<CommitDelegate>(
            Marshal.ReadIntPtr(Marshal.ReadIntPtr(storePtr), 7 * IntPtr.Size));
        commit(storePtr);

        PropVariantClear(ref pv);
        Marshal.Release(storePtr);
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int SetValueDelegate(IntPtr pThis, ref PROPERTYKEY key, ref PROPVARIANT pv);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int CommitDelegate(IntPtr pThis);
}
"@ -ReferencedAssemblies @() -ErrorAction Stop

# Create the .lnk first
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -Command `"exit`""
$shortcut.Description = $DisplayName
if ($IconPath -and (Test-Path $IconPath)) {
    $shortcut.IconLocation = "$IconPath,0"
}
$shortcut.Save()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell) | Out-Null

# Set AppUserModelID property on the shortcut
[ToastShortcutHelper]::SetAppUserModelId($shortcutPath, $Aumid)

Write-Host "  Shortcut: $shortcutPath" -ForegroundColor Green
