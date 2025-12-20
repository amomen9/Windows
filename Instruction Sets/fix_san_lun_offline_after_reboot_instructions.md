# Fix SAN LUN going offline after reboot (DiskPart SAN policy) (Instruction Set)

Symptom: A shared/SAN-attached disk goes `Offline` after every reboot.

A common cause is the system SAN policy being set to `OfflineShared`.

---

## Steps

1. Open an elevated Command Prompt.
2. Start DiskPart:

```cmd
diskpart
```

3. Check current SAN policy:

```text
san
```

4. If you see `Offline Shared`, set the policy to online all:

```text
san policy=OnlineAll
```

5. Verify again:

```text
san
```

---

## One-place transcript (as typed)

```text
diskpart
san
san policy=OnlineAll
san
```
