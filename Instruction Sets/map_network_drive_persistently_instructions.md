# Map a network drive persistently (Instruction Set)

This guide shows two common approaches:

- Map a drive using `NET USE`.
- (Advanced) manipulate the `Z:` mapping via registry (use carefully).

---

## 1) Map using `NET USE`

1. Map the share (example uses a placeholder password):

```cmd
NET use * "\\SERVER\share" /user:DOMAIN\User1 <PASSWORD> /persistent:yes
```

2. Example for VMware shared folders:

```cmd
NET use * "\\vmware-host\Shared Folders" /persistent:yes
```

---

## 2) (Advanced) adjust an existing drive mapping via registry

> This is easy to misconfigure. Prefer `NET USE` unless you specifically need the registry approach.

1. Force-create/update a drive key (example for `Z:`):

```cmd
reg add "HKEY_CURRENT_USER\Network\Z" /f
```

2. Relevant registry location:

```text
Computer\HKEY_CURRENT_USER\Network\Z
```
