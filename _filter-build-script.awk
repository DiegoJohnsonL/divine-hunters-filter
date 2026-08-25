BEGIN {
	# Rules disabled outright
	nk = split("$type->ut->rare $tier->gear3a|$type->ut->rare $tier->j3a|$type->ut->rare $tier->j2a|$type->ut->rare $tier->j3b|$type->ut->rare $tier->anyremaining4j|$type->ut->magic $tier->gear3a|$type->ut->magic $tier->j3a|$type->ut->magic $tier->j2a|$type->ut->magic $tier->j3b|$type->ut->magic $tier->anyremaining4j|$type->gems->uncut $tier->othersupporteg|$type->rr->jewelleryeg $tier->t1 |$type->rr->jewelleryeg $tier->t2 |$type->rr->jewellery $tier->t1 |$type->endgame->normalcraft->economy $tier->group2t2 |$type->endgame->normalcraft->economy $tier->group3t2 |$type->gold $tier->stack2 |$type->uniques $tier->vaaltypeuniques ", KILL, "|")
	# Optional unique rules stock ships commented out; keep the four useful 9L rules.
	# Plain IsVaalUnique items follow live value; only actual Vaal-modified states bypass the floor.
	nu = split("$type->uniques $tier->overqualityuniques |$type->uniques $tier->oversocketuniques1 |$type->uniques $tier->oversocketuniques2 |$type->uniques $tier->loreweaverecipe ", UNCOMMENT, "|")
	# Unique tiers stock hides that 9L shows
	nf = split("$type->uniques $tier->t3boss |$type->uniques $tier->t3 ", FLIP, "|")
	# Rules whose UnidentifiedItemTier >= 4 becomes >= 5
	nb = split("$type->ut->rare $tier->gear4a|$type->ut->rare $tier->gear4b|$type->ut->rare $tier->j4a|$type->ut->rare $tier->j4b|$type->ut->rare $tier->j4c|$type->ut->magic $tier->gear4a|$type->ut->magic $tier->gear4b|$type->ut->magic $tier->j4a|$type->ut->magic $tier->j4b|$type->ut->magic $tier->j4c", BUMP, "|")
	killing = 0; bumping = 0; splint = 0; jewel = 0
}

function isrule(s, arr, n,   i) { for (i = 1; i <= n; i++) if (index(s, arr[i])) return 1; return 0 }

# ---------- Strip the online-filter metadata header ----------
# The base is the copy the game downloaded into OnlineFilters\, so it starts with
# "#Online Item Filter" plus a #hash: of the original bytes. We rewrite the content, so that
# hash is wrong, and a local file has no business claiming to be a synced online filter.
NR < 15 && /^#Online Item Filter$/ { next }
NR < 15 && /^#(name|version|realm|errors|hash|filterVersion|filterType|lastUpdate|monthTimeStamp):/ { next }

# ---------- Header note ----------
/^# BUILDNOTES:/ {
	print
	print "#"
	print "#------------------------------------"
	print "# CUSTOMIZED COPY - built on stock 6-UBER-PLUS-STRICT. Search [CUSTOM] for each edit."
	print "# BASE: use the FilterBlade-generated copy the game caches in OnlineFilters\\4pQrzmUJ, NOT the"
	print "#       GitHub release - GitHub lags the economy retiering by weeks. See the VERSION line above:"
	print "#       a .YYYY.DDD.N suffix means economy-fresh, a bare 0.10.3 means the stale GitHub build."
	print "#------------------------------------"
	print "# 1) SUPERSEDED by note 17 - Exalted Orb is now hidden at every stack size."
	print "# 2) Splinters (Breach/Petition/Runic/Simulacrum): singles hidden, 2+ still shown."
	print "# 3) UnidentifiedItemTier: endgame gear/jewellery is evaluated at tier 5 only. All >=2/>=3"
	print "#    rules disabled, all >=4 raised to >=5. The endgame pickup policy below hides ground rare/magic"
	print "#    tier-5 gear except two narrow magic crafting-base safeguards. Levelling (AreaLevel <= 64) left at stock."
	print "# 4) Uniques: multispecial/multispecialhigh untouched - they keep Headhunter (Heavy Belt),"
	print "#    Mageblood (Utility Belt) and Astramentis (Stellar Amulet) visible."
	print "# 5) Belts: endgame magic/rare ground drops are hidden. White belts left at STOCK behaviour"
	print "#    (Heavy Belt + Utility Belt via the chancing rule only). Unique belts untouched."
	print "# 6) Jewels: STOCK behaviour - rare Emerald/Ruby/Sapphire show, magic+normal hidden."
	print "# 7) Greater orbs: only Exalted and above. Greater Jeweller's / Augmentation / Transmutation /"
	print "#    Regal all hidden, matching 9L OmegaStrict tier d+e. Greater Chaos stays; Greater"
	print "#    Exalted is now hidden too - see note 17."
	print "# 8) Uncut Support Gems hidden in maps."
	print "# 9) Runes: STOCK, untouched - plain/Lesser and Greater Adept-type runes stay hidden."
	print "# 10) Endgame rare jewellery ([[1400]]) disabled entirely - matches 9L. Only tier-5 gear shows."
	print "# 11) Uniques: ported 9L logic - T3 + T3-boss now SHOWN, and 4 optional rules stock ships"
	print "#     off are enabled (over-quality, over-socket x2, Loreweaver rings). The plain Vaal-type"
	print "#     rule stays off so cheap crafting ingredients follow live value. T4 stays hidden."
	print "# 12) Economy crafting bases: only the ilvl 82 group survives (group1t1 + group1t2)."
	print "#     group2t2 (ilvl 81) and group3t2 (ilvl 79) are disabled - that was the white Sacred Focus."
	print "# 13) Uniques, $tier->hideable (184 bases): left HIDDEN, as stock. Verified against live prices -"
	print "#     the most valuable one is ~4ex, none above 0.05 div. The nightly economy script will"
	print "#     promote any of them that climbs past 0.5 div, so nothing valuable stays buried."
	print "# 14) Custom drop sounds on Divine Orb, Omen of Light, Omen of Abyssal Echoes, Omen of"
	print "#     the Liege and Orb of Annulment. Each gets a single-base rule above its parent. The"
	print "#     first three copy their parent's styling; Omen of the Liege uses a deep-violet failure"
	print "#     style, and OrbOfAnnulment.mp3 already combines voice + Divine ding (no Continue)."
	print "#     Needs hibdivine.mp3, HibOmenLight.mp3, Echoes.mp3, OmenOfTheLiege.mp3 and"
	print "#     OrbOfAnnulment.mp3 beside the .filter file."
	print "# 15) Gold: in maps only stacks of 5000+ show, and at font 30 instead of the stock 40. The"
	print "#     2000+ rule is disabled. Levelling (AreaLevel <= 24 / <= 64) left at stock."
	print "# 16) Quality currency: Gemcutter's Prism, Arcanist's Etcher (caster weapons) and Glassblower's"
	print "#     Bauble (flasks) hidden at AreaLevel >= 65. Armourer's Scrap and Blacksmith's Whetstone"
	print "#     were already hidden by stock tier->d. Levelling (AreaLevel <= 64) stays stock."
	print "# 17) Exalted family + Vaal Orb (supersedes note 1). Plain Exalted Orb and Greater Exalted"
	print "#     Orb are hidden at EVERY stack size. Vaal Orb shows only in stacks of 2+. Perfect"
	print "#     Exalted Orb is untouched and still fires the stock tier->s alert - it is the only"
	print "#     member of the family that shows. These rules sit ABOVE the whole currency tierlist"
	print "#     rather than mid-list, so an economy retier cannot promote a base past them."
	print "# 18) Chaos Orbs: all three still show. Plain keeps stock tier->b. Greater Chaos is pulled"
	print "#     out of tier->s and given the tier->a look (white text on salmon, red circle) - the"
	print "#     same styling as Omen of Abyssal Echoes, but keeping the stock tier->a alert sound so"
	print "#     it does not share Echoes.mp3. Perfect Chaos Orb alone keeps the white Divine look."
	print "#     Perfect Jeweller's Orb rides the same rule - also demoted out of the Divine white."
	print "# 19) Essences: the economy updater inserts a live Runes of Aldur pickup policy above the"
	print "#     stock essence tierlist. Default is 0.10 divine with liquidity guards; lower-value"
	print "#     known essences are hidden so stale NeverSink S/A/B/C labels cannot re-show them."
	print "# 20) Uniques: the economy updater hides tracked visible bases below the live 0.50-divine"
	print "#     floor, but keeps every unique Sceptre for same-class Vaal rerolling and preserves"
	print "#     special corruption, actual Vaal modifiers, quality and genuinely exceptional socket"
	print "#     states. NeverSink PreventHiding is advisory: the most valuable trusted droppable outcome"
	print "#     governs each unidentified base, while any untrusted outcome protects the whole base."
	print "# 21) Lineage Support Gems: the economy updater uses live prices with liquidity/chase safeguards;"
	print "#     unknown API entries remain visible, with narrow fallbacks for reviewed low-value omissions."
	print "# 22) Endgame tier-5 rare/magic gear: all rare drops are hidden; magic drops are hidden except"
	print "#     Ancestral Tiara and Obliterator Bow as narrow crafting-base safeguards."
	print "# 23) Ritual reward scanning: 12 known low-priority Ritual Omens are hidden above the whole"
	print "#     Omen tierlist. The 16 selected Ritual Omens retain stock styling; Abyss-only and"
	print "#     unknown/future Omens are untouched."
	next
}

# ---------- Gold: shrink the surviving 5000+ pile ----------
# The 2000+ rule is disabled via KILL above, so in maps this is the only gold rule left.
# Gold drops constantly and a 40pt white-bordered box eats the screen. 30 is under the 32 default.
/^Show # .*\$type->gold \$tier->stack3 / { goldshrink = 1; print; next }
goldshrink {
	if ($0 ~ /^[[:space:]]*$/) { goldshrink = 0; print ""; next }
	# No trailing comment: the stock filter never puts one on a directive line, and an
	# unparsed line breaks the whole filter in-game. Documented in header note 15 instead.
	if ($0 ~ /^[[:space:]]+SetFontSize /) { print "\tSetFontSize 30"; next }
	print
	next
}

# ---------- Uniques: enable the optional rules stock ships commented out ----------
/^#Show # .*\$type->uniques \$tier->/ { if (isrule($0, UNCOMMENT, nu)) uncom = 1 }
uncom {
	if ($0 ~ /^[[:space:]]*$/) { uncom = 0; print ""; next }
	sub(/^#/, "")
	if ($0 ~ /^Show/) sub(/$/, "   # [CUSTOM] enabled (stock has this off, 9L has it on)")
	print
	next
}

# ---------- Uniques: flip the T3 hides to shows, and give them audible treatment ----------
/^Hide # .*\$type->uniques \$tier->t3/ {
	if (isrule($0, FLIP, nf)) {
		sub(/^Hide/, "Show")
		print $0 "   # [CUSTOM] was Hide - 9L shows this tier"
		flipping = 1
		next
	}
}
flipping {
	if ($0 ~ /^[[:space:]]*$/) {
		print "\tPlayAlertSound 3 300"
		print "\tPlayEffect Brown"
		print "\tMinimapIcon 1 Brown Star"
		print ""
		flipping = 0
		next
	}
}

# ---------- Comment out disabled rules ----------
/^(Show|Hide)/ { if (isrule($0, KILL, nk)) killing = 1 }
killing { if ($0 ~ /^[[:space:]]*$/) { killing = 0; print ""; next } print "#" $0; next }

# ---------- Raise >=4 to >=5 ----------
/^(Show|Hide)/ { if (isrule($0, BUMP, nb)) bumping = 1 }
bumping {
	if ($0 ~ /^[[:space:]]*$/) { bumping = 0; print ""; next }
	if ($0 ~ /^[[:space:]]+UnidentifiedItemTier >= 4[[:space:]]*$/) { sub(/>= 4/, ">= 5"); print; next }
}

# ---------- Belt block, inserted just before the tiered-gear section ----------
# The same header text appears in the table of contents, so only act on the 2nd occurrence.
/^# \[\[0800\]\] High Unidentified Mod Tier$/ {
	if (++seen0800 < 2) { print; next }
	print "#==============================================================================================================="
	print "# [CUSTOM] Belts - endgame magic/rare pickup disabled"
	print "#==============================================================================================================="
	print "# White belts are NOT touched here: they keep stock behaviour (Heavy Belt + Utility Belt show via the"
	print "# chancing rule above, everything else white falls into the normal/magic hide layer). Uniques excluded by Rarity."
	print ""
	print "Hide # [CUSTOM][ECONOMY] endgame magic/rare belts - no ground pickup"
	print "\tRarity Magic Rare"
	print "\tClass == \"Belts\""
	print "\tAreaLevel >= 65"
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	print "# [CUSTOM][ECONOMY] Endgame Tier-5 gear pickup policy - regenerated in full on every run"
	print "# Tier-5 rare drops are hidden; only two narrow magic crafting-base safeguards remain."
	print ""
	print "Show # [CUSTOM][ECONOMY] retained Tier-5 magic crafting bases"
	print "\tUnidentifiedItemTier >= 5"
	print "\tRarity Magic"
	print "\tBaseType == \"Ancestral Tiara\" \"Obliterator Bow\""
	print "\tAreaLevel >= 65"
	print "\tSetFontSize 42"
	print "\tSetTextColor 0 240 190 255"
	print "\tSetBorderColor 0 240 190 255"
	print "\tSetBackgroundColor 0 75 30 255"
	print "\tPlayAlertSound 3 300"
	print "\tPlayEffect Blue"
	print "\tMinimapIcon 0 Blue Diamond"
	print ""
	print "Hide # [CUSTOM][ECONOMY] all other endgame Tier-5 rare items"
	print "\tUnidentifiedItemTier >= 5"
	print "\tRarity Rare"
	print "\tAreaLevel >= 65"
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	print "Hide # [CUSTOM][ECONOMY] all other endgame Tier-5 magic items"
	print "\tUnidentifiedItemTier >= 5"
	print "\tRarity Magic"
	print "\tAreaLevel >= 65"
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	print "# [CUSTOM][ECONOMY] END endgame Tier-5 gear pickup policy"
	print "#==============================================================================================================="
	print "#==============================================================================================================="
	print
	next
}

# ---------- Greater Orb of Transmutation + quality currency, before the tier-C currency rule ----------
# The Exalted-family and Vaal Orb rules used to live here. They now sit above the whole
# tierlist at the $tier->s anchor below - see the comment there for why.
/^Show # %H6 \$type->currency \$tier->c !currency_c$/ {
	print "# 9L OmegaStrict hides all four of these in its tier d/e. Greater Chaos stays visible."
	print "Hide # [CUSTOM] Greater orbs below Exalted"
	print "\tClass == \"Incubators\" \"Stackable Currency\""
	print "\tBaseType == \"Greater Jeweller's Orb\" \"Greater Orb of Augmentation\" \"Greater Orb of Transmutation\" \"Greater Regal Orb\""
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	print "# Quality currency for flasks and caster weapons. Cheap, constant, not worth a stop in maps."
	print "# Armourer's Scrap and Blacksmith's Whetstone are already hidden by stock tier->d."
	print "Hide # [CUSTOM] quality currency hidden in maps"
	print "\tClass == \"Incubators\" \"Stackable Currency\""
	print "\tBaseType == \"Arcanist's Etcher\" \"Glassblower's Bauble\""
	print "\tAreaLevel >= 65"
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	print
	next
}

# ---------- Splinters: replace the no-StackSize T5 rule with a Hide ----------
/^Show # %H6 \$type->currency->splinter \$tier->t5 !fragments_splinter5$/ {
	print "Hide # [CUSTOM] single splinters hidden (stacks of 2+ still shown by the t4 rule above)"
	print "\tClass == \"Incubators\" \"Stackable Currency\""
	print "\tBaseType == \"Breach Splinter\" \"Petition Splinter\" \"Runic Splinter\" \"Simulacrum Splinter\""
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	splint = 1
	next
}
splint { if ($0 ~ /^[[:space:]]*$/) { splint = 0; print "" } next }

# ---------- Custom drop sounds ----------
# Divine Orb, Omen of Light, Omen of Abyssal Echoes and Orb of Annulment each live inside a
# multi-base rule.
# Each gets a single-base rule directly above its parent. Most copy the parent's styling; a rule
# can use a deliberate custom style when the item needs a different meaning. CustomAlertSoundOptional,
# not CustomAlertSound: a missing file then falls back
# to the default sound instead of breaking the whole filter load. When cont is true, Continue
# lets the parent rule also run; use it only when the custom file does not already contain the
# parent alert sound. OrbOfAnnulment.mp3 is pre-mixed, so its rule does not use Continue.
function soundrule(title, cls, base, style, sound, cont,   n, i, parts) {
	print "Show # [CUSTOM] " title " - custom drop sound"
	print "\tClass == " cls
	print "\tBaseType == \"" base "\""
	n = split(style, parts, "|")
	for (i = 1; i <= n; i++) print "\t" parts[i]
	print "\tCustomAlertSoundOptional \"" sound "\" 300"
	if (cont) print "\tContinue"
	print ""
}

/^Show # \$type->currency \$tier->s !apex_stier$/ {
	# ---------- Exalted family + Vaal Orb ----------
	# These sit ABOVE the entire currency tierlist on purpose. NeverSink retiers currency with
	# the economy on a near-daily FilterBlade rebuild: between GitHub 0.10.3 (2026-06-25) and
	# the 2026.225 build, 30 currency bases changed tier - Greater Exalted Orb went b -> c and
	# Arcanist's Etcher e -> c. A rule placed mid-tierlist only governs the tiers below it, so
	# a promotion to tier s/a/b would jump straight over it. Above tier->s nothing outranks them.
	# BaseType == is an exact match, so "Perfect Exalted Orb" is NOT caught here - it keeps its
	# stock $tier->s treatment, which is the whole point.
	print "#==============================================================================================================="
	print "# [CUSTOM] Currency overrides - deliberately above the tierlist, see build script"
	print "#==============================================================================================================="
	print ""
	print "# Greater Chaos Orb and Perfect Jeweller's Orb both sit in stock $tier->s, which is the"
	print "# white-background Divine look. Demoted to the $tier->a treatment - the same styling Omen"
	print "# of Abyssal Echoes uses, but with the stock tier->a alert rather than Echoes.mp3, so the"
	print "# Omen keeps its own voice line. Perfect Chaos and Perfect Exalted still keep the Divine"
	print "# look; plain Chaos Orb keeps tier->b."
	print "Hide # [CUSTOM] Gemcutter's Prism hidden in maps"
	print "\tClass == \"Incubators\" \"Stackable Currency\""
	print "\tBaseType == \"Gemcutter's Prism\""
	print "\tAreaLevel >= 65"
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	print "Show # [CUSTOM] Greater Chaos + Perfect Jeweller's - Abyssal Echoes styling, not Divine white"
	print "\tClass == \"Incubators\" \"Stackable Currency\""
	print "\tBaseType == \"Greater Chaos Orb\" \"Perfect Jeweller's Orb\""
	print "\tSetFontSize 45"
	print "\tSetTextColor 255 255 255 255"
	print "\tSetBorderColor 255 255 255 255"
	print "\tSetBackgroundColor 245 105 90 255"
	print "\tPlayAlertSound 1 300"
	print "\tPlayEffect Red"
	print "\tMinimapIcon 0 Red Circle"
	print ""
	print "Show # [CUSTOM] Vaal Orb - stacks of 2+ only"
	print "\tStackSize >= 2"
	print "\tClass == \"Incubators\" \"Stackable Currency\""
	print "\tBaseType == \"Vaal Orb\""
	print "\tSetFontSize 42"
	print "\tSetTextColor 0 0 0 255"
	print "\tSetBorderColor 0 0 0 255"
	print "\tSetBackgroundColor 245 139 87 255"
	print "\tPlayAlertSound 2 300"
	print "\tPlayEffect White"
	print "\tMinimapIcon 1 Yellow Circle"
	print ""
	print "Hide # [CUSTOM] plain + Greater Exalted Orbs at any stack size, single Vaal Orbs"
	print "\tClass == \"Incubators\" \"Stackable Currency\""
	print "\tBaseType == \"Exalted Orb\" \"Greater Exalted Orb\" \"Vaal Orb\""
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	print "#==============================================================================================================="
	print ""
	soundrule("Divine Orb", "\"Incubators\" \"Stackable Currency\"", "Divine Orb", \
	          "SetFontSize 45|SetTextColor 255 0 0 255|SetBorderColor 255 0 0 255|SetBackgroundColor 255 255 255 255|PlayEffect Red|MinimapIcon 0 Red Star", \
	          "hibdivine.mp3")
	soundrule("Orb of Annulment", "\"Incubators\" \"Stackable Currency\"", "Orb of Annulment", \
	          "SetFontSize 45|SetTextColor 255 0 0 255|SetBorderColor 255 0 0 255|SetBackgroundColor 255 255 255 255|PlayEffect Red|MinimapIcon 0 Red Star", \
	          "OrbOfAnnulment.mp3")
	print; next
}

/^Show # \$type->currency->omen \$tier->s !apex_stier$/ {
	# Keep-list policy for the Ritual reward window. Filter syntax has no Ritual-only condition,
	# so target only the known low-priority Ritual pool by exact name. The selected Ritual Omens,
	# Abyss-only Omens, and unknown/future Omens continue into their normal stock/custom rules.
	print "Hide # [CUSTOM] Low-priority Ritual Omens"
	print "\tClass == \"Omen\""
	print "\tBaseType == \"Omen of Answered Prayers\" \"Omen of Bartering\" \"Omen of Catalysing Exaltation\" \"Omen of Dextral Exaltation\" \"Omen of Sinistral Exaltation\" \"Omen of Greater Exaltation\" \"Omen of Reinforcements\" \"Omen of Resurgence\" \"Omen of the Ancients\" \"Omen of the Blessed\" \"Omen of Refreshment\" \"Omen of Gambling\""
	print "\tSetFontSize 18"
	print "\tSetBackgroundColor 20 20 0 0"
	print ""
	soundrule("Omen of Light", "\"Omen\"", "Omen of Light", \
	          "SetFontSize 45|SetTextColor 255 0 0 255|SetBorderColor 255 0 0 255|SetBackgroundColor 255 255 255 255|PlayEffect Red|MinimapIcon 0 Red Star", \
	          "HibOmenLight.mp3")
	print; next
}

/^Show # %H8 \$type->currency->omen \$tier->a !currency_a$/ {
	soundrule("Omen of Abyssal Echoes", "\"Omen\"", "Omen of Abyssal Echoes", \
	          "SetFontSize 45|SetTextColor 255 255 255 255|SetBorderColor 255 255 255 255|SetBackgroundColor 245 105 90 255|PlayEffect Red|MinimapIcon 0 Red Circle", \
	          "Echoes.mp3")
	print; next
}

/^Hide # %H5 \$type->currency->omen \$tier->d !currency_d$/ {
	# Omen of the Liege is the tell that the Abyss smoke pull was missed. Keep it visible,
	# but make the presentation unmistakably negative without spending the red palette.
	soundrule("Omen of the Liege", "\"Omen\"", "Omen of the Liege", \
	          "SetFontSize 42|SetTextColor 255 255 255 255|SetBorderColor 190 70 220 255|SetBackgroundColor 48 0 72 255|PlayEffect Purple|MinimapIcon 0 Purple Hexagon", \
	          "OmenOfTheLiege.mp3")
	print; next
}

# ---------- Jewels: left at STOCK. Rare Emerald/Ruby/Sapphire show, magic/normal stay hidden. ----------

{ print }
