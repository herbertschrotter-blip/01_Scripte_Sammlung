<#
ManifestHint:
  ExportFunctions = @()
  Description     = "Mehrere Quellordner per Multi-Select wählen und alle Fotos daraus in einen Zielordner verschieben (optional rekursiv)."
  Category        = "Media"
  Tags            = @("Photos","Move","MultiSelect","FolderPicker","IFileOpenDialog","Windows","Recursive")
  Dependencies    = @()

Fehlercodes:
  E010 Abbruch durch User
  E020 Quellordner ungültig / keine Auswahl
  E030 Zielordner ungültig / keine Auswahl
  E040 Keine passenden Bilddateien gefunden
  E100 Verschieben fehlgeschlagen
#>

[CmdletBinding()]
param(
    [switch]$Recurse
)

# ------------------------------------------------------------
# Multi-Select Folder Picker via IFileOpenDialog (COM)
# ------------------------------------------------------------
try {
    if (-not ("Win32.FolderPicker" -as [type])) {

        Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace Win32 {
  public static class FolderPicker {
    [Flags]
    public enum FOS : uint {
      FOS_OVERWRITEPROMPT = 0x00000002,
      FOS_STRICTFILETYPES = 0x00000004,
      FOS_NOCHANGEDIR = 0x00000008,
      FOS_PICKFOLDERS = 0x00000020,
      FOS_FORCEFILESYSTEM = 0x00000040,
      FOS_ALLOWMULTISELECT = 0x00000200,
      FOS_PATHMUSTEXIST = 0x00000800
    }

    [ComImport]
    [Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    internal class FileOpenDialog { }

    [ComImport]
    [Guid("D57C7288-D4AD-4768-BE02-9D969532D960")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileOpenDialog {
      [PreserveSig] int Show(IntPtr parent);
      void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
      void SetFileTypeIndex(uint iFileType);
      void GetFileTypeIndex(out uint piFileType);
      void Advise(IntPtr pfde, out uint pdwCookie);
      void Unadvise(uint dwCookie);
      void SetOptions(FOS fos);
      void GetOptions(out FOS pfos);
      void SetDefaultFolder(IShellItem psi);
      void SetFolder(IShellItem psi);
      void GetFolder(out IShellItem ppsi);
      void GetCurrentSelection(out IShellItem ppsi);
      void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
      void GetFileName(out IntPtr pszName);
      void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
      void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
      void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
      void GetResult(out IShellItem ppsi);
      void AddPlace(IShellItem psi, int fdap);
      void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
      void Close(int hr);
      void SetClientGuid(ref Guid guid);
      void ClearClientData();
      void SetFilter(IntPtr pFilter);
      void GetResults(out IShellItemArray ppenum);
      void GetSelectedItems(out IShellItemArray ppsai);
    }

    [ComImport]
    [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem {
      void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
      void GetParent(out IShellItem ppsi);
      void GetDisplayName(SIGDN sigdnName, out IntPtr ppszName);
      void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
      void Compare(IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport]
    [Guid("B63EA76D-1F85-456F-A19C-48159EFA858B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItemArray {
      void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppvOut);
      void GetPropertyStore(int flags, ref Guid riid, out IntPtr ppv);
      void GetPropertyDescriptionList(ref PROPERTYKEY keyType, ref Guid riid, out IntPtr ppv);
      void GetAttributes(uint dwAttribFlags, uint sfgaoMask, out uint psfgaoAttribs);
      void GetCount(out uint pdwNumItems);
      void GetItemAt(uint dwIndex, out IShellItem ppsi);
      void EnumItems(out IntPtr ppenumShellItems);
    }

    internal enum SIGDN : uint {
      SIGDN_FILESYSPATH = 0x80058000
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    internal struct PROPERTYKEY {
      public Guid fmtid;
      public uint pid;
    }

    public static string[] PickFoldersMulti(string title) {
      var dlg = (IFileOpenDialog)new FileOpenDialog();
      dlg.SetTitle(title);

      dlg.GetOptions(out FOS opts);
      opts |= (FOS.FOS_PICKFOLDERS | FOS.FOS_FORCEFILESYSTEM | FOS.FOS_ALLOWMULTISELECT | FOS.FOS_PATHMUSTEXIST);
      dlg.SetOptions(opts);

      int hr = dlg.Show(IntPtr.Zero);
      if (hr != 0) return null;

      dlg.GetResults(out IShellItemArray results);
      results.GetCount(out uint count);
      if (count == 0) return new string[0];

      var paths = new string[count];
      for (uint i = 0; i < count; i++) {
        results.GetItemAt(i, out IShellItem item);
        item.GetDisplayName(SIGDN.SIGDN_FILESYSPATH, out IntPtr psz);
        paths[i] = Marshal.PtrToStringUni(psz);
        Marshal.FreeCoTaskMem(psz);
      }
      return paths;
    }

    public static string PickFolderSingle(string title) {
      var dlg = (IFileOpenDialog)new FileOpenDialog();
      dlg.SetTitle(title);

      dlg.GetOptions(out FOS opts);
      opts |= (FOS.FOS_PICKFOLDERS | FOS.FOS_FORCEFILESYSTEM | FOS.FOS_PATHMUSTEXIST);
      dlg.SetOptions(opts);

      int hr = dlg.Show(IntPtr.Zero);
      if (hr != 0) return null;

      dlg.GetResult(out IShellItem item);
      item.GetDisplayName(SIGDN.SIGDN_FILESYSPATH, out IntPtr psz);
      string path = Marshal.PtrToStringUni(psz);
      Marshal.FreeCoTaskMem(psz);
      return path;
    }
  }
}
"@
    }
}
catch {
    Write-Host ("E100 Add-Type fehlgeschlagen: {0}" -f $_.Exception.Message)
    return
}

# ------------------------------------------------------------
# Auswahl: Quellordner (Multi) + Zielordner (Single)
# ------------------------------------------------------------
$sourceFolders = [Win32.FolderPicker]::PickFoldersMulti("Quellordner auswählen (Mehrfachauswahl)")
if (-not $sourceFolders -or $sourceFolders.Count -eq 0) {
    Write-Host "E020 Keine Quellordner ausgewählt"
    return
}

foreach ($sf in $sourceFolders) {
    if (-not (Test-Path -LiteralPath $sf)) {
        Write-Host ("E020 Quellordner existiert nicht: {0}" -f $sf)
        return
    }
}

$targetFolder = [Win32.FolderPicker]::PickFolderSingle("Zielordner auswählen (alle Fotos werden dorthin verschoben)")
if (-not $targetFolder) {
    Write-Host "E030 Kein Zielordner ausgewählt"
    return
}
if (-not (Test-Path -LiteralPath $targetFolder)) {
    Write-Host ("E030 Zielordner existiert nicht: {0}" -f $targetFolder)
    return
}

Write-Host "`nQuellordner:"
$sourceFolders | ForEach-Object { Write-Host (" - {0}" -f $_) }
Write-Host "`nZielordner:"
Write-Host (" - {0}" -f $targetFolder)

# ------------------------------------------------------------
# Dateien sammeln
# ------------------------------------------------------------
$imgExt = @(".jpg",".jpeg",".png",".heic",".webp")
$gciParams = @{
    File        = $true
    ErrorAction = "SilentlyContinue"
}

$allFiles = @()

foreach ($sf in $sourceFolders) {
    $files = if ($Recurse) {
        Get-ChildItem -LiteralPath $sf -Recurse @gciParams
    } else {
        Get-ChildItem -LiteralPath $sf @gciParams
    }

    $files = $files | Where-Object {
        $_.Extension -and ($imgExt -contains $_.Extension.ToLowerInvariant())
    }

    if ($files) { $allFiles += $files }
}

if (-not $allFiles -or $allFiles.Count -eq 0) {
    Write-Host "E040 Keine passenden Bilddateien gefunden"
    return
}

Write-Host ("`nGefundene Fotos: {0}" -f $allFiles.Count)

# ------------------------------------------------------------
# Verschieben (mit eindeutigen Namen bei Kollisionen)
# ------------------------------------------------------------
$ok = 0
$fail = 0

foreach ($f in $allFiles) {

    $baseName = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $ext = $f.Extension
    $dest = Join-Path $targetFolder $f.Name

    if (Test-Path -LiteralPath $dest) {
        $i = 1
        do {
            $newName = "{0}__{1}{2}" -f $baseName, $i, $ext
            $dest = Join-Path $targetFolder $newName
            $i++
        } while (Test-Path -LiteralPath $dest)
    }

    try {
        Move-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop
        $ok++
    }
    catch {
        $fail++
        Write-Host ("E100 Verschieben fehlgeschlagen: {0}" -f $_.Exception.Message)
        Write-Host ("Quelle: {0}" -f $f.FullName)
        Write-Host ("Ziel:   {0}" -f $dest)
    }
}

Write-Host "`nFertig."
Write-Host ("Verschoben: {0}" -f $ok)
Write-Host ("Fehler:     {0}" -f $fail)
Write-Host ("Recurse:    {0}" -f ([bool]$Recurse))
