# OpsForge v0.7 — PostgreSQL Backup and Restore Verification

## Scope

This is a **local lab runbook** for the *manual* `kind-opsforge` cluster, namespace `opsforge`, PostgreSQL pod `opsforge-db-0`. It does not touch Terraform-managed `opsforge-tf`.

- `scripts/backup-postgres.ps1` makes a PostgreSQL **logical** custom-format archive using `pg_dump` inside the database pod, checks its table of contents, copies it with `kubectl cp`, and writes a SHA-256 checksum.
- `scripts/verify-postgres-restore.ps1` checks the backup checksum, uploads the archive, creates a uniquely named **separate test database** in the same PostgreSQL instance, restores it, verifies the `incidents` table is queryable, reports the row count, and removes that test database by default.
- This intentionally does not overwrite production `opsforge`, delete the PVC, or restart Kubernetes workloads.

**Reason for this method:** Windows PowerShell 5.1 processes native stdout as text. Do **not** use `kubectl exec ... pg_dump -Fc > backup.dump` in Windows PowerShell 5.1, which could corrupt binary backup bytes. A local file created by `kubectl cp` preserves the binary archive.

## Use on Windows PowerShell

From repository root:

```powershell
# Only once: add a gitignore rule before creating any dumps.
if (-not (Select-String -Path .gitignore -Pattern '/backups/' -SimpleMatch -Quiet)) {
    Add-Content .gitignore "`n/backups/"
}
git check-ignore backups/example.dump

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\backup-postgres.ps1
Get-ChildItem .\backups\*.dump
```

Then verify the newest backup by restoring it into a separate throwaway database:

```powershell
$backup = Get-ChildItem .\backups\*.dump | Sort-Object LastWriteTime -Descending | Select-Object -First 1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify-postgres-restore.ps1 -BackupPath $backup.FullName
```

Expected: `BACKUP CREATED`, then `RESTORE VERIFIED` and an incident row count. In the Kubernetes PostgreSQL pod, the temporary restoration database is deleted by default. **The production `opsforge` database remains intact.**

To inspect the separate restored database later, add `-KeepRestoredDatabase` to the second script; it will print the generated database name. Remove it manually when finished with `kubectl exec` and `dropdb` after checking the name.

## Security and disaster recovery limitations

- Database dumps can include confidential user data. They are **unencrypted at rest** on the Windows PC. `backups/` must be gitignored, and archives must not be posted publicly, including in Issues or Actions logs.
- A backup kept only on the same laptop is **not** protection against total disk loss. For real recovery, create an encrypted copy on separate trusted storage, with an access policy and a retention schedule.
- This is logical backup/restore, **not** point-in-time recovery (PITR). It does not back up all Kubernetes manifests, Secrets, filesystem volumes or the cluster itself. A real production design also needs WAL archiving, backup retention, scheduling, restore drills, and operational monitoring.
- The verification uses an isolated database in the **same PostgreSQL instance**; a larger-scale disaster recovery test should restore to an independent PostgreSQL server.
- Every backup/restore consumes storage and CPU. Check available disk space before large dumps.
- When committing v0.7, commit the scripts, this document, and `.gitignore` only; **never** add the `backups/` directory.

## Windows kubectl cp path handling (v0.7.1 fix)

`kubectl cp` treats `:` in a path as a separator for Kubernetes remote copy targets.
Absolute Windows paths such as `C:\Users\...` are therefore ambiguous. Both scripts
now temporarily change into the backup file's containing directory and pass a
relative file path to `kubectl cp`, preserving the binary PostgreSQL dump.

If an earlier v0.7 attempt failed during step 3/4 (`kubectl cp`), rerun
`backup-postgres.ps1` with these fixed scripts. The live database is unchanged.
