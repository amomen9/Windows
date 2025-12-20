# Install Git and clone/pull a repository (Instruction Set)

This guide consolidates the Git install and clone/pull steps.

> Security note
>
>- Do not store personal access tokens in plaintext inside scripts. Use a credential manager or prompt at runtime.

---

## 1) Install Git silently

```cmd
"\\SERVER\share\Git-2.46.1-64-bit.exe" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NOCANCEL /NORESTART /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS /RESTARTAPPLICATIONS /LOGCLOSEAPPLICATIONS
```

## 2) Verify installation

```cmd
"C:\Program Files\Git\cmd\git.exe" -v
```

## 3) Clone a repository

```cmd
cd \
mkdir DBA_Git
cd DBA_Git

"C:\Program Files\Git\cmd\git.exe" clone https://<user>:<TOKEN>@git.example.com/org/repo.git
```

## 4) Pull latest changes

```cmd
cd C:\DBA_Git\repo
"C:\Program Files\Git\cmd\git.exe" pull
```
