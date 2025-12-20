# Disable “Give me updates for other Microsoft products” (Instruction Set)

This disables the optional Microsoft Update service so Windows Update won’t include updates for other Microsoft products.

> Run in PowerShell.

---

## Option A: unconditional removal

```powershell
(New-Object -ComObject Microsoft.Update.ServiceManager).RemoveService('7971f918-a847-4430-9279-4a52d1efe18d')
```

## Option B: remove only if present

```powershell
$svcMgr = New-Object -ComObject Microsoft.Update.ServiceManager
if ($svcMgr.Services | Where-Object { $_.ServiceID -eq '7971f918-a847-4430-9279-4a52d1efe18d' }) {
  $svcMgr.RemoveService('7971f918-a847-4430-9279-4a52d1efe18d')
}
```
