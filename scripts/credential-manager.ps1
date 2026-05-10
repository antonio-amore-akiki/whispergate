# Windows Credential Manager helper for ntfy operator secrets.
# Uses native Advapi32 credential APIs; no external PowerShell module is required.
$ErrorActionPreference = "Stop"

if (-not ([System.Management.Automation.PSTypeName]'Whispergate.CredentialNative').Type) {
  Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace Whispergate {
  public sealed class CredentialValue {
    public string UserName { get; set; }
    public string Password { get; set; }
  }

  public static class CredentialNative {
    private const UInt32 CredTypeGeneric = 1;
    private const UInt32 CredPersistLocalMachine = 2;
    private const Int32 ErrorNotFound = 1168;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential {
      public UInt32 Flags;
      public UInt32 Type;
      [MarshalAs(UnmanagedType.LPWStr)] public string TargetName;
      [MarshalAs(UnmanagedType.LPWStr)] public string Comment;
      public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
      public UInt32 CredentialBlobSize;
      public IntPtr CredentialBlob;
      public UInt32 Persist;
      public UInt32 AttributeCount;
      public IntPtr Attributes;
      [MarshalAs(UnmanagedType.LPWStr)] public string TargetAlias;
      [MarshalAs(UnmanagedType.LPWStr)] public string UserName;
    }

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredReadW(string target, UInt32 type, UInt32 reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredWriteW(ref Credential credential, UInt32 flags);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredDeleteW(string target, UInt32 type, UInt32 flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);

    public static CredentialValue Read(string target) {
      IntPtr credentialPtr;
      if (!CredReadW(target, CredTypeGeneric, 0, out credentialPtr)) {
        int errorCode = Marshal.GetLastWin32Error();
        if (errorCode == ErrorNotFound) { return null; }
        throw new Win32Exception(errorCode);
      }
      try {
        Credential credential = (Credential)Marshal.PtrToStructure(credentialPtr, typeof(Credential));
        string password = string.Empty;
        if (credential.CredentialBlob != IntPtr.Zero && credential.CredentialBlobSize > 0) {
          byte[] passwordBytes = new byte[credential.CredentialBlobSize];
          Marshal.Copy(credential.CredentialBlob, passwordBytes, 0, passwordBytes.Length);
          password = Encoding.Unicode.GetString(passwordBytes);
        }
        return new CredentialValue { UserName = credential.UserName, Password = password };
      } finally {
        CredFree(credentialPtr);
      }
    }

    public static void Write(string target, string userName, string password) {
      byte[] passwordBytes = Encoding.Unicode.GetBytes(password ?? string.Empty);
      GCHandle handle = GCHandle.Alloc(passwordBytes, GCHandleType.Pinned);
      try {
        Credential credential = new Credential();
        credential.Type = CredTypeGeneric;
        credential.TargetName = target;
        credential.CredentialBlobSize = (UInt32)passwordBytes.Length;
        credential.CredentialBlob = handle.AddrOfPinnedObject();
        credential.Persist = CredPersistLocalMachine;
        credential.UserName = userName;
        if (!CredWriteW(ref credential, 0)) {
          throw new Win32Exception(Marshal.GetLastWin32Error());
        }
      } finally {
        if (handle.IsAllocated) { handle.Free(); }
        Array.Clear(passwordBytes, 0, passwordBytes.Length);
      }
    }

    public static bool Delete(string target) {
      if (CredDeleteW(target, CredTypeGeneric, 0)) { return true; }
      int errorCode = Marshal.GetLastWin32Error();
      if (errorCode == ErrorNotFound) { return false; }
      throw new Win32Exception(errorCode);
    }
  }
}
"@
}

function Get-WindowsCredential {
  param([Parameter(Mandatory = $true)][string]$TargetName)
  $credential = [Whispergate.CredentialNative]::Read($TargetName)
  if ($null -eq $credential) { return $null }
  return [pscustomobject]@{
    TargetName = $TargetName
    UserName = [string]$credential.UserName
    Password = [string]$credential.Password
  }
}

function Set-WindowsCredential {
  param(
    [Parameter(Mandatory = $true)][string]$TargetName,
    [Parameter(Mandatory = $true)][string]$UserName,
    [Parameter(Mandatory = $true)][string]$Password
  )
  [Whispergate.CredentialNative]::Write($TargetName, $UserName, $Password)
}

function Remove-WindowsCredential {
  param([Parameter(Mandatory = $true)][string]$TargetName)
  return [Whispergate.CredentialNative]::Delete($TargetName)
}

function Test-WindowsCredential {
  param([Parameter(Mandatory = $true)][string]$TargetName)
  return ($null -ne (Get-WindowsCredential -TargetName $TargetName))
}
