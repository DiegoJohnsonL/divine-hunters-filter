# Divine Hunters agent field guide

This is a routing and verification guide for future agents. Read `AGENTS.md` and `README.md`
first; use this file to find the right source, evidence, and test for a specific task.

## Start every investigation here

1. Run `git status --short` and preserve unrelated user changes.
2. Remember that this repository is also the user's live PoE2 folder. Replacing a filter or
   sound here changes the installed game asset immediately.
3. `.gitignore` is an allowlist because the repository lives in the game-data folder. Before
   creating a new tracked filename, add a matching `!filename` entry; otherwise normal status and
   commit checks will silently omit it.
4. Search for the exact item, rule comment, and asset before inferring intent:

   ```powershell
   rg -ni -C 6 'part of the item name' `
     'Divine Hunters.filter' '_filter-build-script.awk' '_filter-economy-update.ps1' 'README.md'
   ```

5. Voice dictation can turn item names into plausible but nonexistent names. Treat dictated
   names as fuzzy search input until the repository or a game-data source confirms the exact
   `BaseType`. If several candidates remain, report them or ask which one is intended. Do not
   alter the nearest-sounding asset as an assumption.
6. For a filter result, locate the **first matching block** in the generated filter. A later
   `Show` or `Hide` block is irrelevant unless the earlier block uses `Continue`.

## Which file owns the change?

| Task | Source of truth | Generated/installed result |
|---|---|---|
| Stable personal rule or style | `_filter-build-script.awk` | `Divine Hunters.filter` |
| Live unique, essence, or lineage policy | `_filter-economy-update.ps1` | `[CUSTOM][ECONOMY]` blocks in `Divine Hunters.filter` |
| Stock/economy input | freshest valid file under `OnlineFilters\` | transformed by the AWK and PowerShell pipeline |
| Custom alert audio | the named MP3 beside the filter | referenced by a rule generated from `_filter-build-script.awk` |
| Installer/updater behavior | `DivineHuntersSetup.cs`, `DivineHuntersFilterChannel.cs`, `DivineHuntersUpdater.cs` | `DivineHuntersSetup.exe` and its embedded updater |

Never hand-edit `Divine Hunters.filter`. A successful rebuild must reproduce every intended
change from the source files above.

## If an item shows or hides unexpectedly

Use this order:

1. Copy the item's exact in-game name if possible. For an unidentified unique, note that the
   filter normally knows only its base type, not which unique name it will become.
2. Search `Divine Hunters.filter` for every block that can match its class, base, rarity, area,
   item level, corruption, quality, and sockets.
3. Identify the first match and whether it has `Continue`.
4. Find the source that generated that block. Stable custom rules come from the AWK script;
   generated economy blocks come from the PowerShell updater.
5. Run the updater with `-DryRun` and require `structure : OK` before installing a rebuild.
6. After installation, search the generated output again and compare rule order—not just rule
   text.

### Unique-base ambiguity

Do not hide a unique base merely because most outcomes are cheap. An unidentified `Wide Belt`,
for example, cannot be separated by unique name at filter time. If the same base can produce a
chase unique, hiding the base can hide the chase drop too. The updater therefore preserves
NeverSink `PreventHiding` bases, unique scepters, special corruption/Vaal/quality/socket states,
and bases with insufficient evidence.

For the current thresholds and safety logic, read the **Useful parameters** and **Customisations**
sections in `README.md`; do not copy threshold values into new code from memory.

## Market and game-data source ladder

Use sources for the job they are good at and record the league and retrieval time in any report.

1. [poe2scout API/Swagger](https://api.poe2scout.com/swagger/index.html) — primary automated
   source for the project's live item categories, divine/exalted conversion, listings, and price
   history. `_filter-economy-update.ps1` is the executable documentation for the exact endpoints
   and response fields currently consumed.
2. [NeverSink PoE2 filter](https://github.com/NeverSinkDev/NeverSink-Filter-for-PoE2) — upstream
   stock rule structure and strictness/economy tierlists.
3. [NeverSink economy aspects](https://github.com/NeverSinkDev/Filter-ItemEconomyAspects) —
   authoritative input for this project when mapping unique names to filter bases and honoring
   `NonDrop`, `PreventHiding`, and related safety metadata.
4. [PoE2DB](https://poe2db.tw/us/) — exact game names, base classes, modifiers, and acquisition or
   drop-mechanic investigation. It is game data, not proof of current market value.
5. [Official item-filter reference](https://www.pathofexile.com/item-filter/about) — syntax and
   action semantics, including `Continue`, PoE2-only conditions, and the 0-300 alert-volume range.
6. [Exiled Exchange 2](https://github.com/Kvan7/Exiled-Exchange-2) and the official trade/market
   UI — useful manual cross-checks for a specific identified item. They are not substitutes for
   a reproducible bulk history feed.
7. Community design references such as
   [cdr's endgame filter](https://github.com/cdrg/cdr-poe2filter) — useful for seeing what strict
   endgame players hide, but never copy rules without checking current PoE2 syntax, league data,
   base ambiguity, and this project's safety policy.

Price-history points are market-listing snapshots, not confirmed sales. A current price with few
listings can be a rare chase item or a manipulated/stale listing. Do not use a universal minimum-
listing cutoff as proof of low value. This project uses conservative historical statistics for
thin unique markets and keeps unknown or insufficiently evidenced items visible.

### Economy-specific pointers

- Unique history and confidence logic: search `_filter-economy-update.ps1` for
  `UniqueHistoryMinPoints`, `history-median`, and `history-floor`.
- Lineage supports: search for `lineagesupportgems`, `lineageAliases`,
  `lineageMissingLowValue`, `lineageShow`, `lineageKeep`, and `lineageHide`.
  Unknown/unpriced API entries are a deliberate safety net; reviewed low-value names that are
  entirely absent from poe2scout may use a narrow fallback until the live API publishes them.
- Essences/Runes of Aldur: inspect the live price and history block; do not infer value from a
  stale NeverSink tier label alone.
- Unique drop/base mapping: inspect the cached `uniques.aspects.json` and the upstream aspects
  source before concluding that a trade-site base name is the filter's `BaseType`.

## Custom-sound work

The custom mapping is documented in `README.md` and generated by the `soundrule` function in
`_filter-build-script.awk`. At the time of writing all custom rules use:

```text
CustomAlertSoundOptional "file.mp3" 300
```

The filter number and the MP3's encoded loudness are separate controls. Two files at filter
volume 300 can sound very different. Since 300 is already the filter syntax maximum, make small
per-asset loudness corrections in the audio only after identifying the exact item-to-file map.

### Safe loudness procedure

1. Verify the exact rule and filename in both `_filter-build-script.awk` and
   `Divine Hunters.filter`.
2. Compare every plausible candidate if the spoken item name is uncertain.
3. Use FFmpeg's EBU loudness analysis and record integrated loudness (`input_i`, LUFS) and true
   peak (`input_tp`, dBTP):

   ```powershell
   ffmpeg -hide_banner -nostats -i '.\sound.mp3' `
     -af 'loudnorm=I=-24:LRA=7:TP=-1:print_format=json' -f null NUL
   ```

   If FFmpeg is unavailable, use a portable Windows build linked from
   [ffmpeg.org](https://ffmpeg.org/download.html) in a temporary folder; do not commit the tool.
4. Calculate gain as `reference LUFS - target LUFS`. Render from the committed/original source,
   not from an already normalized MP3, to avoid successive lossy re-encodes:

   ```powershell
   $gainDb = -17.05 - (-19.43) # example: desired LUFS minus freshly measured source LUFS
   ffmpeg -i '.\original.mp3' -af "volume=${gainDb}dB" `
     -codec:a libmp3lame -b:a 320k -ar 48000 -ac 2 '.\candidate.mp3'
   ```

5. Re-measure the candidate. For a requested match, aim within 0.1 LU (tighter when practical),
   keep true peak below 0 dBTP with sensible headroom, and verify duration, sample rate, channels,
   decoding, and the final SHA-256.
6. Replace only the intended MP3 after the candidate passes. Run `git status --short` and
   `git diff --stat`; no similarly named sound should be modified.

`OrbOfAnnulment.mp3` already contains both its voice and the stock Divine ding. Its filter rule
must not gain `Continue`, or the parent alert can play a second ding. The repeatable source mix is
documented in `OrbOfAnnulment-audio-process.md`. Its current acceptance target is 0.20 LU louder
than `HibOmenLight.mp3`; re-measure the reference rather than assuming an old LUFS number.

## Publishing and installer updates

Filter and sound changes do **not** need a new installer executable. A push to `main` touching
`Divine Hunters.filter` or any required MP3 triggers
`.github/workflows/publish-filter-channel.yml`, which replaces the fixed `filter-latest` release
assets. Rebuild/release `DivineHuntersSetup.exe` only when installer or updater code changes.

Before reporting a rollout complete:

1. Confirm the commit contains only intended files and `origin/main` equals `HEAD`.
2. Confirm the `publish-filter-channel` workflow completed successfully for that commit.
3. Query the `filter-latest` release, find the changed asset, and compare its GitHub SHA-256
   digest with the local file. Downloading the asset to a temporary file and hashing it is the
   strongest check.
4. Explain client behavior precisely:
   - running the v1.4+ installer downloads the current channel immediately;
   - a registered v1.4+ daily updater downloads only files whose digest changed;
   - the updater postpones while PoE2 is running;
   - pre-v1.4 installations need the migration installer once;
   - absence of a scheduled task on the developer's PC does not mean the channel is broken.

If `gh` is unavailable, GitHub's read-only REST endpoints are sufficient:

```text
GET /repos/DiegoJohnsonL/divine-hunters-filter/actions/workflows/publish-filter-channel.yml/runs
GET /repos/DiegoJohnsonL/divine-hunters-filter/releases/tags/filter-latest
```

The release asset's `digest` field must match a fresh SHA-256 of the installed file.

## Binary recovery and verification notes

- Keep candidate outputs in a temporary folder until verified.
- A tracked binary can be recovered from `HEAD` with `git restore` when normal Git writes are
  available. If an environment prevents index locking, `git archive HEAD -- <file>` can extract a
  clean committed copy without hand-reconstructing the binary.
- Do not commit backups, downloaded analysis tools, temporary renders, or release-verification
  downloads.
- The game does not reliably hot-reload filters or sounds. Tell the user to reselect the filter
  or restart PoE2 after an installed change.
