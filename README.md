A personal project of PowerShell scripts for automating my Windows environment.
Not meant as a universal solution — **use or adapt at your own risk**.

The scripts handle:

* redirecting and restoring app data through symlinks (`AppsData`);
* mounting folders and shared locations from *CSV configs*;
* managing autostart programs via Windows Task Scheduler;
* full environment apply/clean actions with a single command;
* maybe more in the future.

Everything runs through PowerShell scripts with no external dependencies.
Intended for quick setup on clean systems and portable workflow experiments.

```powershell
.\run.ps1
```

> ⚠️ **Built for personal use.**

> Paths, scripts, and configs are tailored to *my setup* and may not fit yours.
