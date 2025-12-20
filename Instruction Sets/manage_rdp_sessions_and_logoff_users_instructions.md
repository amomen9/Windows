# Manage user sessions and log off users (Instruction Set)

This guide shows how to query sessions and log off disconnected users.

---

## 1) List sessions

```cmd
query user
```

---

## 2) Parse `query user` output and log off disconnected sessions (example)

> Adapt parsing (`tokens`) based on your `query user` output formatting.

```bat
@echo off
setlocal

for /f "skip=1 tokens=1,2,3" %%a in ('query user') do (
  set "user=%%a"
  set "sessionId=%%b"
  set "state=%%c"

  rem This is just a template; you may need to adjust for spacing and column shifts.
  if /I "%%c"=="Disc" (
    echo Logging off disconnected session ID %%b for user %%a
    logoff %%b
  )
)
```

If you only want to target a specific username, filter the loop output accordingly.
