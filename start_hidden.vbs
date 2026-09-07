Set sh = CreateObject("WScript.Shell")
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = dir
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\serve_https.ps1""", 0, False
WScript.Sleep 2000
chrome = ""
pf = sh.ExpandEnvironmentStrings("%ProgramFiles%")
pf86 = sh.ExpandEnvironmentStrings("%ProgramFiles(x86)%")
la = sh.ExpandEnvironmentStrings("%LocalAppData%")
cands = Array( _
  pf & "\Google\Chrome\Application\chrome.exe", _
  pf86 & "\Google\Chrome\Application\chrome.exe", _
  la & "\Google\Chrome\Application\chrome.exe")
For Each c In cands
  If CreateObject("Scripting.FileSystemObject").FileExists(c) Then chrome = c : Exit For
Next
If chrome <> "" Then
  sh.Run """" & chrome & """ https://127.0.0.1:8787/?source=pwa", 1, False
Else
  sh.Run "https://127.0.0.1:8787/?source=pwa", 1, False
End If
