# Warlock Services Forever

A World of Warcraft warlock service addon. Initial development release; client
compatibility must still be verified in game. The reported version is `1.60.1`,
but its addon interface number has not been confirmed. The TOC value `16001` is
provisional, not a verified compatibility declaration.

## Install

1. Exit WoW.
2. Copy the entire `WarlockServicesForever` folder into your game's
   `Interface/AddOns` folder (or the corresponding client-specific folder).
3. Check that the path ends in
   `Interface/AddOns/WarlockServicesForever/WarlockServicesForever.toc`.
4. At character selection, open **AddOns** and enable the addon. If it appears
   out of date, enable **Load out of date AddOns** for testing.
5. Log in on a warlock and type `/wsf`. Drag the panel to reposition it.

If the addon does not load, obtain the interface number with:

```lua
/run local v,b,d,i=GetBuildInfo(); print("Version:",v,"Build:",b,"Interface:",i)
```

Report that output and any Lua error. A matching interface number alone does
not establish API compatibility. This version uses secure action buttons and
requires the modern event/callback model; original 1.12 clients are unsupported.

## Features

- Carried soul shard count with a configurable threshold; bank items excluded.
- Carried healthstone count, including improved vanilla healthstone variants.
- Click-to-cast creation buttons for healthstones, soulstones, firestones,
  spellstones, and Ritual of Souls. Availability depends on client and training;
  the game reports missing spells, reagents, or other casting requirements.
- **Offer healthstone** places the first matching stone from ordinary bags into
  a free trade slot after you open a trade and click the button. Accept manually.
  Unsupported trade APIs fall back to instructions for manual placement.
- Exact `123` messages, with optional surrounding whitespace, in party, raid,
  or whispers populate a session-only queue. Sender names retain realm suffixes;
  case-insensitive duplicates are ignored. Public and guild chat are excluded.
- Each requester appears in a boxed, clickable row. Click their name to target
  them and select them, then click **Summon selected** to cast Ritual of Summoning.
  Previous/Next navigates the queue, with eight clickable rows per page.
  Invite the recipient to your party yourself first.
  Normal spell requirements, including helpers and reagents, still apply.
- Requests received during combat are deferred until combat ends. Summon target
  and queue selection controls cannot change during combat.
- Automatically remove a requester when the combat log reports your successful
  Summon Player effect (spell 7720), or a summon event for spell 698/7720, with
  that recipient. Ritual cast-start, interruptions, failures, and other casters
  do not remove anyone. A success reported during combat is applied afterward.
  This confirms the summon effect, not that the recipient accepted or arrived.
  If the server does not emit those events, use **Remove selected** as a fallback.
  Realm-less log names resolve only when unambiguous. No unsolicited chat is sent.

## Commands

| Command | Action |
| --- | --- |
| `/wsf` | Show/hide panel outside combat |
| `/wsf shards 10` | Set low-shard threshold (0–100) |
| `/wsf clear` | Clear summon queue outside combat |
| `/wsf version` | Print client build and interface number |
| `/wsf help` | Show commands |

Threshold and panel position persist between sessions. Requests do not persist.
Soulstone cooldown reminders, configurable request channels, rank selection,
arrival/acceptance detection, and localization beyond spell names are future
work. Spell creation and trade acceptance are never automatic.

## Development checks

No game account or server is needed for the offline tests. Python 3 and the
Lua 5.1 runtime bundled in `lupa==2.6` are used:

```sh
python -m venv /workspace/.wsf-venv
/workspace/.wsf-venv/bin/python -m pip install lupa==2.6
PYTHONDONTWRITEBYTECODE=1 /workspace/.wsf-venv/bin/python -m unittest discover -s tests -v
```

Run the tests from the repository root. Tests cover queue parsing, deduplication,
selection/removal, combat deferral, macro injection rejection, class filtering,
clickable row selection, queue pagination, successful-recipient removal,
ambiguous realm names, and offering a stone without overwriting a filled trade slot. WoW APIs are mocked;
these checks cannot establish secure action behavior or real client compatibility.

## Required in-game checks

1. Enable Lua errors (`/console scriptErrors 1`), load on a warlock, and verify
   `/wsf version`, panel movement, and saved position after `/reload`.
2. Compare counts against bags, create a healthstone, and verify count refresh.
3. Have a party member and a whisper sender send `123`; verify duplicate messages
   do not add duplicate entries. Click each boxed name and confirm both your target
   and the selected row match. Test Previous/Next with more than eight requests.
4. With a valid group and helpers, summon the selected requester; verify the
   intended target and successful cast. Verify the successful recipient is removed
   automatically. Cancel or interrupt another attempt and verify its request stays.
   If this client does not report the supported summon effect, use Remove selected
   and report the missing behavior so its event API can be adapted.
5. Receive requests during combat; verify the summon target stays unchanged and
   deferred requests appear afterward without protected-action errors.
6. Open a trade, click Offer healthstone, verify the item and recipient, and
   accept manually. Repeat with occupied slots, no stones, and a full trade.
7. Verify available creation spells and their required ranks on this client.
