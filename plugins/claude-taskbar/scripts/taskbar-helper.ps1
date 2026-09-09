<#  Claude Code session helper (claude-taskbar plugin). Launched hidden by
    taskbar-start.ps1 from a SessionStart hook; not meant to be run by hand. While the watched claude.exe
    is alive it:
      1. Gives the Windows Terminal window hosting the session its own taskbar
         group with the Claude icon and name (shell AppUserModel properties on
         the window). Windows Terminal cannot do this per profile itself.
      2. Optionally shows a Claude icon in the notification area.
    When claude.exe exits it clears the window stamp and removes itself. #>
param(
    [Parameter(Mandatory)][int]$WatchPid,
    [int]$WtPid = 0,
    [string]$Title = "Claude Code",
    [string]$PidFile = "",
    [switch]$NoTrayIcon
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
[StructLayout(LayoutKind.Sequential, Pack=4)] public struct PropertyKey { public Guid fmtid; public uint pid; public PropertyKey(Guid g, uint p){fmtid=g;pid=p;} }
[StructLayout(LayoutKind.Sequential)] public struct PropVariant { public ushort vt; public ushort r1, r2, r3; public IntPtr p; public IntPtr p2; }
[ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore {
  int GetCount(out uint c); int GetAt(uint i, out PropertyKey k); int GetValue(ref PropertyKey k, out PropVariant v); int SetValue(ref PropertyKey k, ref PropVariant v); int Commit();
}
public static class ClaudeTaskbar {
  [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr h, ref Guid iid, out IPropertyStore ps);
  [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant v);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  static readonly Guid AUM = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
  const uint PID_RelaunchCommand = 2, PID_RelaunchIcon = 3, PID_RelaunchName = 4, PID_ID = 5;

  public struct Win { public IntPtr Handle; public string Title; }
  public static List<Win> TerminalWindows(uint pid) {
    var r = new List<Win>();
    EnumWindows((h, l) => {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != pid || !IsWindowVisible(h)) { return true; }
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      if (c.ToString() != "CASCADIA_HOSTING_WINDOW_CLASS") { return true; }
      var t = new StringBuilder(512); GetWindowText(h, t, 512);
      r.Add(new Win { Handle = h, Title = t.ToString() });
      return true; }, IntPtr.Zero);
    return r;
  }
  static IPropertyStore Store(IntPtr h) {
    Guid iid = typeof(IPropertyStore).GUID; IPropertyStore ps;
    int hr = SHGetPropertyStoreForWindow(h, ref iid, out ps);
    if (hr != 0) { throw new COMException("SHGetPropertyStoreForWindow", hr); }
    return ps;
  }
  static string GetStr(IPropertyStore ps, uint pid) {
    var k = new PropertyKey(AUM, pid); PropVariant v;
    if (ps.GetValue(ref k, out v) != 0 || v.vt != 31) { return null; }
    string s = Marshal.PtrToStringUni(v.p); PropVariantClear(ref v); return s;
  }
  public static bool IsStamped(IntPtr h, string id, string icon) {
    var ps = Store(h); return GetStr(ps, PID_ID) == id && GetStr(ps, PID_RelaunchIcon) == icon;
  }
  static void Set(IPropertyStore ps, uint pid, string val) {
    var k = new PropertyKey(AUM, pid); var v = new PropVariant();
    if (val != null) { v.vt = 31; v.p = Marshal.StringToCoTaskMemUni(val); }   // VT_LPWSTR, or VT_EMPTY to clear
    int hr = ps.SetValue(ref k, ref v); PropVariantClear(ref v);
    if (hr != 0) { throw new COMException("SetValue " + pid, hr); }
  }
  public static void Stamp(IntPtr h, string id, string icon, string name, string cmd) {
    var ps = Store(h); Set(ps, PID_ID, id); Set(ps, PID_RelaunchIcon, icon); Set(ps, PID_RelaunchName, name); Set(ps, PID_RelaunchCommand, cmd); ps.Commit();
  }
  public static void Clear(IntPtr h) {
    var ps = Store(h); Set(ps, PID_ID, null); Set(ps, PID_RelaunchIcon, null); Set(ps, PID_RelaunchName, null); Set(ps, PID_RelaunchCommand, null); ps.Commit();
  }
}
'@

# ---- taskbar stamping -------------------------------------------------------
$AppId    = 'Anthropic.ClaudeCode.Terminal'
$IcoPath  = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\claude-app.ico'
$AppIcon  = $IcoPath + ',0'
$AppName  = 'Claude Code'
$WtExe    = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
$Relaunch = "`"$WtExe`" -p `"Claude Code`""
# Claude Code prefixes the terminal title with a spinner glyph; the profile tab says "Claude Code".
$ClaudeTitle = '^[\u2733\u273B\u273D\u2736\u2722\u00B7\u25D0-\u25D3]\s|Claude'
$script:stamped = @{}

function Get-WtPids {
    if ($WtPid) { return @($WtPid) }
    # Default-terminal handoff: WindowsTerminal.exe is COM-activated (-Embedding) and never an
    # ancestor of claude.exe, so the launcher passes WtPid 0. Scan every Terminal instead.
    @(Get-Process WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
}

function Update-Taskbar {
    try {
        foreach ($id in Get-WtPids) {
            $wins = [ClaudeTaskbar]::TerminalWindows([uint32]$id)
            if ($wins.Count -eq 0) { continue }
            # Known host with one window: it must be ours. Otherwise only windows whose title looks like Claude.
            $targets = if ($WtPid -and $wins.Count -eq 1) { $wins } else { $wins | Where-Object { $_.Title -match $ClaudeTitle } }
            foreach ($w in $targets) {
                # Re-stamp if missing or pointing at an old icon path (e.g. after a plugin update).
                if (-not [ClaudeTaskbar]::IsStamped($w.Handle, $AppId, $AppIcon)) {
                    [ClaudeTaskbar]::Stamp($w.Handle, $AppId, $AppIcon, $AppName, $Relaunch)
                }
                $script:stamped[$w.Handle] = $true
            }
        }
    } catch {}
}

function Clear-Taskbar {
    foreach ($h in @($script:stamped.Keys)) {
        try { [ClaudeTaskbar]::Clear($h) } catch {}
    }
}

# ---- notification-area icon --------------------------------------------------
$ni = $null
$tip = $Title
if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 60) + '...' }   # NotifyIcon.Text limit

$script:quit = {
    $timer.Stop()
    Clear-Taskbar
    if ($ni) { $ni.Visible = $false; $ni.Dispose() }
    if ($PidFile -and (Test-Path $PidFile)) { Remove-Item $PidFile -Force -ErrorAction SilentlyContinue }
    [System.Windows.Forms.Application]::Exit()
}

if (-not $NoTrayIcon) {
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = New-Object System.Drawing.Icon($IcoPath)
    $ni.Text = $tip
    $ni.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $header = $menu.Items.Add($tip)
    $header.Enabled = $false
    $menu.Items.Add('-') | Out-Null
    $menu.Items.Add('Hide icon').add_Click({ $ni.Visible = $false }) | Out-Null
    $ni.ContextMenuStrip = $menu
}

# ---- main loop -------------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.add_Tick({
    if (-not (Get-Process -Id $WatchPid -ErrorAction SilentlyContinue)) { & $script:quit; return }
    Update-Taskbar
})
Update-Taskbar
$timer.Start()

[System.Windows.Forms.Application]::Run()
