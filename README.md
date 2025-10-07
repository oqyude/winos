It's just a simple deployment. You may need it for something more. **Portable programs often have their disadvantages, which symlinks can fix**. Try to make this something more automated so you don't have to use your mouse again to install packages on Windows. 

*Apps configurations are restored individually, I made them for myself, keep in mind! Everything written here may be a very **unprepared solution** for you!*

This project lets you store app data in a single folder and automatically create symlinks to restore configurations.

## Overview

* Simple apps use `from` and `to` columns in a CSV for linking.
* Isolated apps have separate `connect` and `disconnect` scripts in `isolated/` folder.
* Module `apps-data-manager` provides three functions:

  1. `connect` — creates symlinks.
  2. `disconnect` — removes symlinks.
  3. `reconnect` — disconnects and reconnects.

## Features

* Add simple symlinks by adding a line to the CSV.
* Fully automated via PowerShell; no extra software required.

> ⚠️ Note: Isolated app scripts are custom and may require adjustments.
