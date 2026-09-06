# Shadow Dungeon 8-Socket Endless Loading — Temporary Fix

This repository contains a small, version-specific PowerShell patcher for a Shadow Dungeon endless-loading bug caused by an invalid crafted weapon with eight sockets.

It does **not** contain or redistribute any game DLL. The script only changes a supported DLL already installed on your own computer.

## What is happening

The affected save can contain a crafted weapon with `AocaoCount = 8` / `MaxAocaoCount = 8`. While rebuilding the inventory during character loading, the game tries to activate one socket UI object for every saved socket. The UI array contains fewer entries, so the load fails with:

```text
IndexOutOfRangeException: Index was outside the bounds of the array.
  at ItemScript.NewPagePut(...)
  at InventoryManager.RestoreInventoryItems(...)
```

A related exception can occur in `WarehouseManager.PutItem`. Because the transfer is not atomic, moving the affected item between inventory and stash may also duplicate it.

The patch temporarily skips the vulnerable socket-icon activation loop. It allows the character to load, but it does **not** repair the invalid item or the crafting rule that created it.

## Supported game version and DLL

This release is for **Shadow Dungeon 1.1.5** (Steam build `25148878`) and intentionally supports exactly one `Assembly-CSharp.dll` build:

```text
Original SHA-256: F1D130502E9F16477E779475B352F8BB127A1F7E6A0266FA9E761742899BF6B6
Patched SHA-256:  E97604ABA94E19AE0B3A5FB134508C2A7B31CA12C2644D1B164048A44A3CAB78
```

If the hash is different, the script refuses to modify the file. This is expected after many game updates; do not try to bypass the check.

## Before you run it

1. Close Shadow Dungeon.
2. Back up the entire save folder:

   ```text
   C:\Users\<your-name>\AppData\LocalLow\OO Cat\Shadow Dungeon
   ```

3. Download `ShadowDungeon-v1.1.5-SocketFix.ps1` from this repository and inspect it if you wish. It downloads nothing and does not edit save files.

## Apply the temporary fix

Open PowerShell in the folder containing the script and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ShadowDungeon-v1.1.5-SocketFix.ps1
```

The script normally finds the game in your Steam libraries automatically. If it cannot, pass the full path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ShadowDungeon-v1.1.5-SocketFix.ps1 `
  -AssemblyPath "D:\SteamLibrary\steamapps\common\Shadow Dungeon\Shadow Dungeon_Data\Managed\Assembly-CSharp.dll"
```

The script:

- checks that Shadow Dungeon is closed;
- verifies the complete original DLL SHA-256 and the exact bytes to be changed;
- creates a timestamped backup beside the DLL;
- writes and verifies a temporary patched copy before replacing the installed DLL;
- restores the backup automatically if final verification fails.

After it reports success, start the game normally through Steam and try loading the character.

## Restore the original DLL

Close the game, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ShadowDungeon-v1.1.5-SocketFix.ps1 -Restore
```

You can also use **Steam → Shadow Dungeon → Properties → Installed Files → Verify integrity of game files**. A Steam update or integrity check may remove the temporary patch automatically.

The restore command refuses to copy an old backup over an unknown/newer DLL build.

## Important limitations

- This is an unofficial, temporary workaround. Use it at your own risk.
- Socket icons for weapons may not be displayed correctly while the DLL is patched.
- The invalid weapon and its socket data remain in the save.
- Avoid repeatedly moving the affected item between inventory and stash; duplication has been observed when the transfer throws an exception partway through.
- Keep your save backup until the developer ships an official fix and the character loads correctly without this patch.
- If the game updates, first try the unmodified new DLL. Do not force this patch onto a build with a different hash.

## Suggested developer-side fix

The immediate bounds error can be prevented by limiting the UI loop to the available slot objects, for example:

```csharp
int visibleSocketCount = Math.Min(weapon.AocaoCount, aocao.Length);
for (int i = 0; i < visibleSocketCount; i++)
{
    // Activate/update socket UI.
}
```

The root fix should also validate the maximum socket count when crafting and deserializing items. Inventory/stash transfers should be atomic so an exception cannot leave a duplicated item.

Related Steam discussion: [Endless loading thread](https://steamcommunity.com/app/4423580/discussions/0/588437021425438291/)

## License

The patcher script and documentation in this repository are released under the MIT License. Shadow Dungeon and its game files belong to their respective copyright holders.
