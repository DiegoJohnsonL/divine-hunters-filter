# FinancialAdvisor Filter — PoE2 Loot Filter

A customised build of **NeverSink's 6-UBER-PLUS-STRICT** filter for Path of Exile 2, with
personal edits layered on top and a nightly rebuild that re-tiers uniques against live
market prices from [poe2scout](https://poe2scout.com).

Everything lives in `%USERPROFILE%\Documents\My Games\Path of Exile 2\`.

---

## Enable the filter in game

1. Make sure `FinancialAdvisor Filter.filter` is in the folder above.
2. In game: **Escape → Options → Game → Loot Filter**, pick `FinancialAdvisor Filter`.
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

## Custom drop sounds

Three rules use custom audio. These files must sit **beside** the `.filter`:

| File | Plays for |
|---|---|
| `hibdivine.mp3` | Divine Orb |
| `HibOmenLight.mp3` | Omen of Light |
| `Echoes.mp3` | Omen of Abyssal Echoes |

They are wired with `CustomAlertSoundOptional`, not `CustomAlertSound` — if a file goes
missing the rule falls back to the default sound instead of breaking the whole filter load.

---

## How the filter is built

> **Do not edit `FinancialAdvisor Filter.filter` by hand.** It is generated output. The next
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
  FinancialAdvisor Filter.filter  ← installed (previous kept as .bak)
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
| `-MinListings` | `20` | Ignore uniques with fewer live listings — guards against troll prices. |
| `-DivS` / `-DivA` / `-DivB` | `10` / `2` / `0.5` | Divine thresholds for promoting a base. |
| `-QuietFloor` | `0.25` | Apex bases below this get the quiet treatment instead of a siren. |
| `-NoQuiet` | off | Disable that softening. |
| `-BaseFilter` | auto | Force a specific base instead of the freshest cached one. |
| `-Output` | installed path | Write somewhere else. |

The script refuses to install if its structural checks fail (orphaned directives, comments
inside a rule block, empty `BaseType` lists, or mojibake from a codepage mishap).

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
| 3 | `UnidentifiedItemTier`: endgame gear/jewellery needs tier 5; levelling left at stock |
| 4 | Uniques: multispecial untouched — Headhunter, Mageblood, Astramentis stay visible |
| 5 | Belts: magic/rare only at tier 5; white belts stock |
| 6 | Jewels: stock — rare Emerald/Ruby/Sapphire show |
| 7 | Greater orbs: Jeweller's / Augmentation / Transmutation / Regal hidden |
| 8 | Uncut Support Gems hidden in maps |
| 9 | Runes: stock |
| 10 | Endgame rare jewellery disabled entirely |
| 11 | Uniques: T3 + T3-boss shown, 5 optional rules enabled (9L parity) |
| 12 | Economy crafting bases: only the ilvl 82 group survives |
| 13 | Uniques `$tier->hideable`: left hidden, economy script promotes any that climb |
| 14 | Custom drop sounds on Divine Orb, Omen of Light, Omen of Abyssal Echoes |
| 15 | Gold: maps show 5000+ only, at font 30. Levelling left at stock |
| 16 | Quality currency (Arcanist's Etcher, Glassblower's Bauble) hidden at AreaLevel ≥ 65 |
| 17 | Exalted Orb + Greater Exalted hidden at any stack; Vaal Orb only in stacks of 2+; Perfect Exalted untouched |
| 18 | Greater Chaos Orb + Perfect Jeweller's Orb demoted from the white Divine look to the Abyssal Echoes styling; Perfect Chaos keeps Divine |

---

## Files

| File | Role |
|---|---|
| `FinancialAdvisor Filter.filter` | **Generated.** The installed filter. Do not hand-edit. |
| `FinancialAdvisor Filter.filter.bak` | Previous build, kept automatically on install |
| `_filter-build-script.awk` | **Source of truth** for personal customisations |
| `_filter-economy-update.ps1` | Build + economy pipeline |
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
