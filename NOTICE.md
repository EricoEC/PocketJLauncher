# PocketJ Launcher notices

PocketJ Launcher is a modified version of the GPL-3.0 licensed Amethyst-iOS project and incorporates work from the PojavLauncher, Boardwalk, and StikDebug ecosystems.

## Modification notice

- Modified project name: PocketJ Launcher / 掌上Java启动器
- Maintainer of this modified version: Erico
- Modification date: 2026-11-05
- License: GNU General Public License version 3

This modified version includes an Apple-native launcher interface, Simplified Chinese and English localization, instance and account workflow changes, diagnostics, control improvements, compatibility fixes, and a modified StikDebug-derived JIT workflow with an independent helper process.

The complete GPL-3.0 license text is provided in `LICENSE`. Source releases and binary distributions of PocketJ Launcher must continue to provide the corresponding source and preserve applicable copyright, license, and warranty notices.

## Upstream projects

- Amethyst-iOS: https://github.com/AngelAuraMC/Amethyst-iOS
- PojavLauncher ecosystem: https://github.com/PojavLauncherTeam
- Boardwalk: https://github.com/zhuowei/Boardwalk
- StikDebug: https://github.com/StikDebug/StikDebug (GNU AGPL-3.0)

The incorporated StikDebug-derived code is marked under `Natives/stikdebug/`.
Its AGPL-3.0 license text is distributed as
`THIRD_PARTY_LICENSES/StikDebug-AGPL-3.0.txt`. Distribution of a combined
binary must satisfy all applicable GPL-3.0 and AGPL-3.0 source and notice
requirements.

Copyright in upstream code remains with its respective authors. PocketJ Launcher is not an official Mojang Studios or Microsoft product. Minecraft is a trademark of Microsoft Corporation.

Third-party components and their licenses are listed in `README.md` and in the license files distributed with those components.

## v1.6 additions

On-device pairing uses the MIT-licensed `jkcoxson/idevice` library with PocketJ-owned native and Rust glue. The module reuses the workspace pairing-tool source through the shared dependency directory; no AirBeep or StikPair implementation was copied. The binary includes `PocketJPairing-THIRD-PARTY-NOTICES.txt` for its dependency notices.

The bundled Chinese mod-name/alias subset and its CC BY-SA 4.0 attribution are documented in `Natives/resources/POCKETJ_MOD_ALIASES_NOTICE.md`, also included in the app. This data subset is distinct from the launcher code license.
