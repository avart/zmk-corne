---
name: flash-left
description: Build and flash the ZMK firmware to the left half of the Corne Choc Pro over USB (UF2 volume /Volumes/KEEBART). Use when the user asks to flash, install or "lägga in" the firmware on the keyboard / left half.
---

# Flash the left half

Only the left half needs flashing for keymap changes (it is the central). The right
half is only flashed when the user explicitly asks; this skill does not cover it.

## Steps

1. Tell the user, in one line, to connect the left half by USB and press reset
   (double-tap if a single press doesn't mount it). Do this **before** running the
   script so they can act while it builds.
2. Run the script with the Bash tool, `timeout: 600000`:

   ```sh
   .claude/skills/flash-left/flash-left.sh
   ```

   It builds `nice_view-corne_choc_pro_left-zmk` with `./build.sh`, waits up to
   5 minutes for `/Volumes/KEEBART`, copies the `.uf2` there, and waits for the
   volume to unmount, which means the flash succeeded.

   Options:
   - `--no-build` — flash the existing `firmware/` file (when it was just built).
   - `--settings-reset` — flash `settings_reset-corne_choc_pro_left-zmk.uf2`
     instead (clears bonds/settings). Only when the user asks for it; afterwards they
     must flash the normal firmware again, so offer to run the skill again.
3. Report the result from the last line of output:
   - `OK: ...` — flashed. Remind the user that if they have saved changes in ZMK
     Studio, they may need "Restore Stock Settings" to see keymap changes.
   - `TIMEOUT` (exit 3) — the volume never appeared. Ask the user to reconnect and
     press reset, then rerun with `--no-build`.
   - exit 4 — something else is mounted at that path; do not copy, tell the user.
   - `FAILED` (exit 5) — the volume stayed mounted. Tell the user; don't retry blindly.
   - Build failure — show the compiler error, don't flash.

A `cp` I/O error followed by `OK` is normal: the bootloader reboots mid-copy.
