# AGENTS.md

Read [README.md](README.md) before doing anything in this repo. It covers the whole setup:
how the filter is built, how to rebuild it, and how to make changes safely.

Then use [AGENT-FIELD-GUIDE.md](AGENT-FIELD-GUIDE.md) as the task router. It records the
exact files, external sources, verification commands, audio workflow, and publishing checks
that have already caused expensive mistakes or investigation in previous sessions.

Two things that are easy to get wrong and are explained there in full:

- **Never hand-edit `Divine Hunters.filter`.** It is generated output and the next
  rebuild overwrites it. Personal customisations belong in `_filter-build-script.awk`.
- **Rule order decides everything.** The game takes the first rule an item matches and ignores
  the rest, so where a rule sits matters as much as what it says.
