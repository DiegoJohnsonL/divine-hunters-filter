# Divine Hunters Filter — PoE2 Loot Filter

A customised build of **NeverSink's 6-UBER-PLUS-STRICT** filter for Path of Exile 2, with
personal edits layered on top and a rebuild command that re-tiers uniques against live
market prices from [poe2scout](https://poe2scout.com).

Everything lives in `%USERPROFILE%\Documents\My Games\Path of Exile 2\`.

---

## Quick install for humans

Close Path of Exile 2 first. The destination folder is:

```text
%USERPROFILE%\Documents\My Games\Path of Exile 2\
```

Choose one option:

### Recommended: one-file installer

1. Download `DivineHuntersSetup.exe` from the repository (or download the ZIP and extract it).
2. Double-click `DivineHuntersSetup.exe`.
3. Click **Next**, choose your PoE2 folder, leave Ritual filtering checked if wanted, and click
   **Install**.

The small bootstrapper securely downloads the current filter and five sounds from the rolling
GitHub filter channel, verifies every SHA-256 digest, and installs them. An internet connection
is required, but no Git, PowerShell, or command prompt is needed.
`Install-DivineHuntersFilter.cmd` remains available as a script fallback.

## Automatic updates

The one-file installer can optionally register a per-user Windows task named
`Divine Hunters Filter Update`. Once enabled, it checks the fixed `filter-latest` GitHub
prerelease once per day, compares the installed files with GitHub's SHA-256 asset digests, and
downloads only changed filter/sound assets. It skips the check while Path of Exile 2 is running,
keeps one filter backup, and preserves the Ritual setting.

The helper, installed filter digest, and log live under `%LOCALAPPDATA%\DivineHuntersFilter`,
not in the game folder. The updater never runs `git pull`, never downloads another installer,
and never changes the game's Ritual setting during an update. It does **not** run
`_filter-economy-update.ps1`; live poe2scout re-tiering is refreshed when that script is run and
the resulting generated filter is pushed to `main`.
To disable it later, rerun the installer with the checkbox cleared or run:

```powershell
schtasks /Delete /TN "Divine Hunters Filter Update" /F
```

### Option A: GitHub (requires Git)

Open PowerShell and run:

```powershell
$repo = "$env:TEMP\divine-hunters-filter"
$game = "$env:USERPROFILE\Documents\My Games\Path of Exile 2"
git clone https://github.com/DiegoJohnsonL/divine-hunters-filter.git $repo
Copy-Item "$repo\Divine Hunters.filter" $game -Force
Copy-Item -Path @(
  "$repo\hibdivine.mp3"
  "$repo\HibOmenLight.mp3"
  "$repo\Echoes.mp3"
  "$repo\OmenOfTheLiege.mp3"
  "$repo\OrbOfAnnulment.mp3"
) -Destination $game -Force
```

### Option B: Download manually

1. Open the [GitHub repository](https://github.com/DiegoJohnsonL/divine-hunters-filter).
2. Select **Code → Download ZIP**, then extract it.
3. Copy `Divine Hunters.filter`, `hibdivine.mp3`, `HibOmenLight.mp3`, `Echoes.mp3`,
   `OmenOfTheLiege.mp3`, and `OrbOfAnnulment.mp3` into the destination folder above.

Then:

1. Start the game and select **Divine Hunters** under **Options → Game → Loot Filter**.
2. To apply the filter inside Ritual rewards, close the game, open
   `poe2_production_Config.ini` in the same folder, and change
   `apply_item_filter_to_ritual=false` to `apply_item_filter_to_ritual=true`. Save the file,
   then start the game again.
3. If the filter does not appear immediately, reselect it or restart the game.

## For AI agents and contributors

1. Read `AGENTS.md`, this README, and the task-oriented
   [`AGENT-FIELD-GUIDE.md`](AGENT-FIELD-GUIDE.md) before editing.
2. Never hand-edit `Divine Hunters.filter`; it is generated output. Put personal rules
   in `_filter-build-script.awk`.
3. Remember that the first matching rule wins. Put an override above the stock rule it must beat;
   currency overrides that must survive economy re-tiering belong above `$tier->s`.
4. The public installer is a stable bootstrapper built from `DivineHuntersSetup.cs`,
   `DivineHuntersFilterChannel.cs`, and `DivineHuntersUpdater.cs`. Rebuild and version it only
   when installer/updater code changes. Filter and sound changes are published separately by
   `.github/workflows/publish-filter-channel.yml` and do not require another EXE.
5. Dry-run and validate the filter build:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "_filter-economy-update.ps1" -DryRun
   ```

6. If the dry-run reports `structure : OK`, install the filter build:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "_filter-economy-update.ps1"
   ```

7. Verify the generated rule and its position, then tell the user to reload or reselect the filter
   in-game. Keep generated output, cache files, and user-owned unrelated changes intact.

### Publishing model

- Initial rollout order matters: push these changes and wait for the rolling-channel workflow to
  create `filter-latest`; only then publish the normal `v1.4.0` release with the rebuilt
  `DivineHuntersSetup.exe` asset.
- `v1.4.0` is the one-time migration installer release. It moves existing scheduled clients from
  executable downloads to the rolling content channel.
- A push to `main` that changes `Divine Hunters.filter` or one of the five sounds validates and
  replaces those assets on the fixed `filter-latest` prerelease.
- Existing `v1.4.0+` scheduled clients compare per-file SHA-256 digests and download only changed
  assets. No executable rebuild or new executable release version is needed.
- Rebuild `DivineHuntersSetup.exe` only when the bootstrapper/updater code itself changes. Run
  `Test-DivineHuntersSetup.ps1` before publishing such a migration build.

---

## Enable the filter in game

1. Make sure `Divine Hunters.filter` is in the folder above.
2. In game: **Escape → Options → Game → Loot Filter**, pick `Divine Hunters`.
   (Some builds list it under **Options → UI**, near the bottom.)
3. The game does **not** hot-reload. After every rebuild, reselect the filter — or restart.

---

## Enable the filter for Rituals

By default your loot filter does **not** apply to items offered at Ritual altars — you get the
raw, unfiltered wall of items. There is a setting that fixes this, but it is **not exposed in
the options UI**; it only exists in the config file.

1. **Close Path of Exile 2 completely.** The game rewrites this file when it exits and will
   overwrite your edit if it is running.
2. Open `poe2_production_Config.ini` in this same folder.
3. Find this line (it is in the `[UI]` block, around line 133):

   ```ini
   apply_item_filter_to_ritual=false
   ```

4. Change it to:

   ```ini
   apply_item_filter_to_ritual=true
   ```

5. Save, then start the game.

Your filter's Show/Hide rules and styling now apply inside the Ritual reward window, so the
same tiering and colours you get on the ground carry into ritual offers.

> **Current state in this install:** `false` — not yet enabled.

Related key worth knowing, a few lines below:

```ini
hide_all_filtered_ground_items=true
```

Credit for surfacing the ritual setting: [NeverSink](https://x.com/NeverSinkDev/status/2003115126589894881)
and the walkthrough video [Hidden POE2 Setting: Filters in Rituals](https://www.youtube.com/watch?v=6hiQtcQhB3k).

---

## Custom drop sounds (included)

The GitHub and ZIP downloads include all five custom sound files. Keep them **beside** the
`.filter` file:

| File | Plays for |
|---|---|
| `hibdivine.mp3` | Divine Orb |
| `HibOmenLight.mp3` | Omen of Light |
| `Echoes.mp3` | Omen of Abyssal Echoes |
| `OmenOfTheLiege.mp3` | Omen of the Liege; deep-violet failure alert for a missed Abyss smoke pull |
| `OrbOfAnnulment.mp3` | Orb of Annulment voice mixed with the stock Divine ding |

They are wired with `CustomAlertSoundOptional` as a safety fallback, but the intended installation
includes all five files.
The annulment MP3 already contains both layers, so its rule does **not** use `Continue`; this avoids
playing the Divine ding twice. The other four assets already contain their full custom audio.
See [`OrbOfAnnulment-audio-process.md`](OrbOfAnnulment-audio-process.md) for the repeatable FFmpeg recipe.

---

## How the filter is built

> **Do not edit `Divine Hunters.filter` by hand.** It is generated output. The next
> rebuild overwrites it and your change vanishes.

```
  OnlineFilters\<id>              ← FilterBlade copy the game caches (freshest economy tiering)
          │
          ▼
  _filter-build-script.awk        ← THE SOURCE OF TRUTH for personal customisations
          │
          ▼
  _filter-cache\staged.filter     ← intermediate
          │
          ▼
  _filter-economy-update.ps1      ← splices the [ECONOMY] unique-promotion block, sanity checks
          │
          ▼
  Divine Hunters.filter  ← installed (previous kept as .bak)
```

**Why the cached online copy and not the GitHub release:** GitHub tags rarely — `0.10.3` shipped
2026-06-25 and is still current months later — while FilterBlade regenerates tiering almost
daily. Check the `# VERSION:` line: a `.YYYY.DDD.N` suffix means economy-fresh, a bare `0.10.3`
means the stale GitHub build.

---

## Rebuilding

Always dry-run first — it builds and runs the structural checks without installing:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "_filter-economy-update.ps1" -DryRun
```

Then install:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "_filter-economy-update.ps1"
```

### Useful parameters

| Parameter | Default | Purpose |
|---|---|---|
| `-DryRun` | off | Build + validate, install nothing. Output lands in `_filter-cache\staged.filter`. |
| `-League` | auto | Override league detection. |
| `-UniqueMinListings` | `5` | Live-liquidity fallback for uniques (`-MinListings` remains a compatibility alias). |
| `-UniqueHistoryMinPoints` | `5` | Minimum historical snapshots for pricing thin or zero-listing uniques. Thin markets use the conservative lower quartile; bases with insufficient evidence are never hidden. |
| `-DivS` / `-DivA` / `-DivB` | `10` / `2` / `0.5` | Divine thresholds for promoting a base. |
| `-QuietFloor` | `0.25` | Apex bases below this get the quiet treatment instead of a siren. |
| `-NoQuiet` | off | Disable that softening. |
| `-EssenceFloor` | `0.10` | Minimum divine value for a normal essence pickup. |
| `-EssenceMinListings` | `10` | Minimum current listings for the normal essence floor. |
| `-EssenceThinFloor` | `0.25` | Minimum value for a thinner essence market. |
| `-EssenceThinMinListings` | `5` | Minimum listings for the thinner-market exception. |
| `-LineageFloor` | `0.50` | Normal lineage-support pickup floor. |
| `-LineageMinListings` | `5` | Minimum listings at the normal lineage floor. |
| `-LineageThinFloor` | `1.00` | Thin-market lineage-support floor. |
| `-LineageThinMinListings` | `3` | Minimum listings at the thin-market lineage floor. |
| `-LineageChaseFloor` | `2.00` | Always retain a priced lineage support at or above this value. |
| `-UniqueFloor` | `0.50` | Hide tracked visible unique bases below this value; `PreventHiding` bases, unique scepters, and special states remain visible. |
| `-BaseFilter` | auto | Force a specific base instead of the freshest cached one. |
| `-Output` | installed path | Write somewhere else. |

The script refuses to install if its structural checks fail (orphaned directives, comments
inside a rule block, empty `BaseType` lists, or mojibake from a codepage mishap).

Unique history from poe2scout is a sequence of market-listing snapshots, not confirmed sales.
The updater therefore uses a historical median for liquid uniques and the lower quartile after
at least five snapshots for thin or zero-listing uniques. If neither history nor live liquidity
is sufficient, the base is treated as uncertain and is never added to the generated hide rule.

---

## Making a change

1. Edit `_filter-build-script.awk`.
2. Dry-run.
3. Verify the built output actually does what you meant (see below).
4. Install, then reload the filter in game.

### The one rule that governs everything

The game reads the filter **top to bottom, and the first rule an item matches wins.** Nothing
below is consulted for that item. So there are two ways to change an item's behaviour: edit the
rule that currently catches it, or put a new rule *above* that one.

### Why custom rules sit above the tierlist

NeverSink re-tiers currency constantly. Between the June GitHub build and the August FilterBlade
build, **30 currency bases changed tier** — `Greater Exalted Orb` went `b → c`, `Arcanist's Etcher`
went `e → c` (hidden → shown), `Greater Chaos Orb` went `b → s`.

A rule placed mid-tierlist only governs the tiers *below* it. If the economy pass promotes a base
past that point, the rule is jumped clean over and the item reappears. So personal currency
overrides are emitted **above `$tier->s`**, where nothing outranks them.

For the same reason, prefer a separate `Hide` above the tierlist over deleting a name from a
stock `BaseType` list — the stock list is a shared bucket that also holds items you want, and its
membership changes under you.

### Verifying a change

Simulate first-match-wins against the built file rather than eyeballing it:

```bash
awk -v TARGETS='Exalted Orb,Vaal Orb,Divine Orb' -f first.awk "_filter-cache/staged.filter"
```

`BaseType ==` is an **exact** match, so `"Exalted Orb"` never catches `Perfect Exalted Orb` or
`Greater Exalted Orb`. That is what lets the three be treated differently.

---

## Customisations

Every edit is marked `[CUSTOM]` in the built filter — search for it. The full numbered list is
reproduced in the filter's own header. Summary:

| # | Change |
|---|---|
| 1 | *Superseded by 17.* |
| 2 | Splinters (Breach/Petition/Runic/Simulacrum): singles hidden, 2+ shown |
| 3 | `UnidentifiedItemTier`: endgame gear/jewellery is evaluated at tier 5; levelling left at stock |
| 4 | Uniques: multispecial untouched — Headhunter, Mageblood, Astramentis stay visible |
| 5 | Endgame magic/rare belts hidden; white belts stock |
| 6 | Jewels: stock — rare Emerald/Ruby/Sapphire show |
| 7 | Greater orbs: Jeweller's / Augmentation / Transmutation / Regal hidden |
| 8 | Uncut Support Gems hidden in maps |
| 9 | Runes: stock |
| 10 | Endgame rare jewellery disabled entirely |
| 11 | Uniques: T3 + T3-boss shown, 5 optional rules enabled (9L parity) |
| 12 | Economy crafting bases: only the ilvl 82 group survives |
| 13 | Uniques `$tier->hideable`: left hidden, economy script promotes any that climb |
| 14 | Custom drop sounds on Divine Orb, Omen of Light, Omen of Abyssal Echoes, Omen of the Liege, and Orb of Annulment |
| 15 | Gold: maps show 5000+ only, at font 30. Levelling left at stock |
| 16 | Quality currency (Gemcutter's Prism, Arcanist's Etcher, Glassblower's Bauble) hidden at AreaLevel ≥ 65 |
| 17 | Exalted Orb + Greater Exalted hidden at any stack; Vaal Orb only in stacks of 2+; Perfect Exalted untouched |
| 18 | Greater Chaos Orb + Perfect Jeweller's Orb demoted from the white Divine look to the Abyssal Echoes styling; Perfect Chaos keeps Divine |
| 19 | Essences use live Runes of Aldur prices: normal floor 0.10 divine, thin-market exception 0.25 divine; known lower-value essences are hidden |
| 20 | Visible unique bases below the live 0.50-divine floor are hidden; `PreventHiding` bases such as Wide Belt, unique scepters, and special states remain visible |
| 21 | Lineage Support Gems use live prices: 0.50-divine floor with liquidity/chase safeguards; unknown API entries remain visible, while reviewed low-value names omitted by poe2scout can use narrow fallbacks |
| 22 | Endgame Tier-5 rare gear hidden; Tier-5 magic gear hidden except Ancestral Tiara and Obliterator Bow crafting-base safeguards |
| 23 | Twelve low-priority Ritual Omens are hidden for faster reward scanning; the selected Ritual Omens, Abyss-only Omens, and unknown/future Omens keep their normal rules |

---

## Files

| File | Role |
|---|---|
| `Divine Hunters.filter` | **Generated.** The installed filter. Do not hand-edit. |
| `AGENT-FIELD-GUIDE.md` | Task router, trusted sources, investigation recipes, audio checks, and rollout verification for future agents. |
| `Divine Hunters.filter.bak` | Previous build, kept automatically on install |
| `Divine Hunters.filter.before-divinehunters-*.bak` | Installer restore point; only the newest is retained |
| `_filter-build-script.awk` | **Source of truth** for personal customisations |
| `_filter-economy-update.ps1` | Build + economy pipeline |
| `DivineHuntersSetup.exe` | Small Windows bootstrapper; downloads current channel assets |
| `DivineHuntersSetup.cs` | Bootstrapper UI, Ritual toggle, and task registration |
| `DivineHuntersFilterChannel.cs` | Shared download, digest validation, backup, and atomic-install logic |
| `DivineHuntersUpdater.cs` | Silent rolling-channel updater used by the daily task |
| `DivineHuntersVersion.cs` | Release version embedded in the installer and updater |
| `Build-DivineHuntersSetup.ps1` | Rebuilds the bootstrapper only when its code changes |
| `Test-DivineHuntersSetup.ps1` | Isolated installer/updater integration and rollback test |
| `.github/workflows/publish-filter-channel.yml` | Publishes validated filter/sound assets after pushes to `main` |
| `OrbOfAnnulment-audio-process.md` | Repeatable FFmpeg recipe for voice + ding alerts |
| `Install-DivineHuntersFilter.cmd` | Script-based installer fallback |
| `_filter-economy-update.log` | Run history |
| `_filter-cache\staged.filter` | Intermediate build output |
| `_filter-cache\uniques.aspects.json` | Cached NeverSink aspect data |
| `OnlineFilters\` | FilterBlade copies the game downloaded |
| `poe2_production_Config.ini` | Game config — holds the ritual setting above |

---

## Troubleshooting

**Filter won't load / "Unable to parse parameter for BaseType rule"** — usually mojibake from a
codepage mishap mangling a non-ASCII base name. The build script has a tripwire for this and
refuses to install; if it slipped through, rebuild.

**A change didn't take effect** — the game does not hot-reload. Reselect the filter.

**An item you hid is showing again** — it was probably promoted into a tier above your rule. Move
the rule above `$tier->s`. See *Why custom rules sit above the tierlist*.

**`awk not found`** — the pipeline needs Git for Windows' awk. The script probes `PATH` and the
standard Git install locations.
