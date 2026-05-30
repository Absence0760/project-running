# Competitive landscape — what we're up against, and what's actually beatable

A frank read of the four watches we'd be competing with in the ultra-marathon segment, written as if you were going to bet money on the outcome. Most of the "we can beat them" thinking that founders bring to consumer hardware is wrong; this doc tries to be specific about *which* parts are wrong and which parts are actually right.

The four watches we'd be measured against, with their best-case advertised numbers:

| Watch | GPS battery | Display | GNSS | Price |
|---|---|---|---|---|
| Garmin Fenix 7X Pro Solar | ~89hr (single-band) | 1.4" MIP | Dual-band | $900 |
| Garmin Enduro 3 | ~110hr (single-band) | 1.4" MIP | Dual-band | $900 |
| COROS Vertix 2 / 2S | ~140hr / ~118hr | 1.4" MIP | Dual-band | $700 |
| Suunto Vertical | ~85hr (Performance mode) | 1.4" MIP | Dual-band | $700 |

Headline numbers are best-case single-band; multi-band-with-music typically drops them 40–60%. Treat them as marketing, not as what you'd see on the wrist during a 100-miler. The analysis below assumes the buyer knows this.

## What you literally cannot beat them on

These metrics aren't about engineering effort or budget. They're about being a 20-year-old vertically-integrated company with supplier relationships and accumulated IP that you can't access on day one.

**Chip-level hardware.** Garmin and COROS both source their dual-band GNSS from Sony (the CXD5610 family) and their optical-HR AFE from Maxim. Their displays come from Sharp. Their barometers come from Bosch. Their batteries come from one of three Asian Li-Po suppliers. You would source from exactly the same companies, because there are no other companies. The watch you build would have the same silicon inside as the watch you're competing with. The hardware-component comparison is a wash.

**GNSS algorithm tuning.** This is where Garmin's twenty years actually show. Multi-path rejection in urban canyons, foliage-attenuated signal recovery, false-fix detection — all of this is firmware IP that they've iterated on against the world's largest GPS test corpus. Even with the same chip and a well-written NMEA parser, your first-generation watch will drift more in tree canopy than a 2018 Fenix. Apple, with infinite money, took three product generations to get the Apple Watch Ultra to roughly Garmin-quality on this — and outdoors-runner reviewers still rate Garmin slightly higher.

**Optical-HR algorithm tuning.** Maxim sells a baseline algorithm with the MAX86177 AFE — both Garmin and COROS license it, then tune it further with their own signal-processing engineers. You'd start at the baseline; closing the gap takes years and DSP expertise you'd have to hire.

**Sensor accessory ecosystem.** Garmin owns ANT+ (the Dynastream acquisition in 2006 was strategic, not accidental) and ships with 200+ certified ANT+ accessories — HR straps, foot pods, bike power meters, radar, dashcams, indoor trainers, the InReach satellite messenger family. Your watch would start with zero accessories. You'd be limited to whatever BLE-standard HR straps and foot pods you can pair with directly.

**Brand trust and field longevity.** A 10-year-old Garmin Fenix 5 still works. The runner buying a $700 watch is making a 5–7 year commitment, and they know it. Your watch has zero field hours, no warranty infrastructure, and a brand they've never heard of.

**Retail distribution.** Garmin is in REI, every running specialty store, every airport Hudson News, every European sporting-goods chain. COROS is in most of those. Both are at every race expo. You'd be online-only at best.

**Repair and warranty infrastructure.** Garmin's RMA process is slow but it exists, and it works. The COROS process is similar. Yours would be "DM the founder on Discord."

The trap here is thinking effort can substitute for time. It can't. Even matching Garmin on GNSS algorithm quality in three years would require hiring a team of ex-Garmin GPS engineers, which (a) costs $2M+ a year and (b) probably won't happen, because most of them are happy at Garmin.

## Garmin's real, exploitable faults

This is what runners actually complain about. Not "I wish my Garmin had more GPS modes" — Garmin already has every GPS mode. The faults below are the things their own customers grumble about, and they're consistent across forums, reviews, and Reddit threads going back years.

**The UI is hostile.** Nested menus, inconsistent terminology, proprietary metric names ("Body Battery", "Training Status", "Endurance Score", "Acute Load", "VO2 Max", "Race Predictor") that aren't explained anywhere obvious. New users don't know what's actionable. The watch ships with seven different battery-life dashboards and the user can't tell which one means what they think it means. This is the single biggest complaint in every Garmin review, and Garmin has been told this for a decade and hasn't meaningfully fixed it.

**The Garmin Connect mobile app feels like 2018.** Slow, cluttered, search doesn't work well, the activity feed is hard to scroll. The web version is missing features the app has and vice versa.

**The Connect IQ marketplace is mostly garbage.** High friction to find quality watch faces. Most third-party data fields are amateur side projects. Garmin's review process is restrictive enough to discourage serious developers and permissive enough to let in junk.

**Software update cadence is glacial.** Fenix 7 shipped with GPS bugs that took six months to fix. Major feature drops happen roughly annually. Bug fixes for non-flagship SKUs can take longer still.

**Social and community features are anemic.** Garmin Connect "groups" exist but they're a feature graveyard. Activity comments are perfunctory. There's no real club / event / meetup layer. Runners who want a community use Strava on top of Garmin.

**Coach features are rule-based.** Garmin Coach offers canned 5k / 10k / half / marathon plans from external coaches. There's no real adaptation to your actual run history, no LLM-style explanation of *why* today's workout is what it is, no conversational interface.

**Battery numbers are best-case marketing.** Multi-band-with-music drops the headline figure by 40–60%. Garmin knows this and doesn't fix it because everyone in the industry does it.

**Repair-hostile.** Battery isn't user-replaceable. Screen replacement costs more than half the watch. Closed ecosystem means no third-party repair.

**Map rendering lag.** Pan and zoom on older Fenix SKUs is sluggish enough to be embarrassing. Newer models are better but the renderer is still slower than what a modern vector renderer could deliver.

## COROS's real, exploitable faults

COROS is more software-competent than Garmin overall — their UI is cleaner, their app is better, their update cadence is faster. But they have their own gaps.

**Map UX is still weak.** Vector maps were added late. Rendering speed is below Garmin's. Route loading and rerouting is slower than it should be.

**No music storage.** Watch can't store audio; the runner has to bring a phone if they want music.

**No mobile payments.** No equivalent of Garmin Pay.

**No satellite SOS / InReach equivalent.** This is a real safety gap for backcountry ultra runners. Garmin's inReach integration is the killer feature for the audience COROS is targeting and they don't have an answer.

**Chinese-company / data-sovereignty concerns.** This matters to a non-trivial slice of the European and US privacy-conscious market. COROS has regional servers but the perception persists.

**Smaller accessory ecosystem.** Better than yours would start out, much worse than Garmin's.

## Where you can credibly win

Stack-ranked by how achievable and impactful each is for a team your size:

1. **Software polish and UI clarity.** The bar is on the floor. Your existing SvelteKit and Flutter apps already demonstrate the taste delta — settings screens that make sense, copy that explains what things mean, design that respects the user's time. Free, because it's your existing skillset.

2. **The mobile companion app.** Garmin Connect and the COROS app both lose to your existing app today, before you've shipped a single piece of hardware. Already done.

3. **AI coach quality.** Both incumbents have rule-based coaches; you have an LLM-coach roadmap. This is genuinely uncontested space — neither competitor has even tried to be conversational about why today's workout is what it is.

4. **Social, community, and club features.** Both incumbents abandoned community to Strava years ago. You're already building this. The ultra-runner specifically values clubs (running club night, ultra training groups, FKT communities) and nobody is serving them in-watch.

5. **Software update cadence.** Ship monthly vs Garmin's annual. Trivial to win. The compounding effect over two years is huge.

6. **Forum and community responsiveness.** Solo founder beats faceless Garmin support every time, until you grow past it. Buys real loyalty in the early years.

7. **Open data, right-to-export, privacy-first posture.** Both incumbents are sensor-data-to-cloud businesses. End-to-end encrypted backups or self-hosted sync options are a real wedge for the privacy-conscious slice of the market.

8. **Repairability as brand position.** User-replaceable battery, replaceable strap pins, schematics released after warranty expires. Nobody else does this. It resonates with the ultra demographic specifically — the people who'll wear a watch for 30 hours in the rain are the same people who care that they could fix it.

9. **Underserved geographies.** Garmin is English-first and lukewarm on most languages. If your existing app is already i18n'd, you can pick a specific market (Brazilian Portuguese, Indonesian, Polish) and be the best ultra-runner watch in that language. Small but defensible.

10. **Niche-event integration.** parkrun, IRONMAN, UTMB. The big players treat these as afterthoughts. You're already deep in parkrun.

11. **Vector map quality on-watch.** Both incumbents are weak here. A modern renderer plus your existing tile pipeline is a real differentiator if you build it.

## The strategic implication

> **Status note (2026-05-28) — primary strategic recommendation superseded by [§ 92](../architecture/decisions.md#92-custom-watch-decisions-optimise-for-tier-3-production-quality-period--scope-and-effort-are-not-constraints) + its [Resolution](../architecture/decisions.md#resolution-2026-05-28--hybrid--92-long-term-goal---80-tier-1-preserved-as-deliberate-first-prototype-compromise).** § 92 codified the long-term goal as "build the best watch ever" — building our own watch IS now the primary strategic path, not the deferred alternative this section originally framed it as. The vectors below remain useful as **parallel-validation tracks** (Vector 1 / Connect IQ is explicitly committed to per [§ 87](../architecture/decisions.md#87-strategic-vector-1-connect-iq-app-runs-in-parallel-with-tier-1-firmware) and runs alongside tier-1 firmware), but not as "instead of own hardware" alternatives. The "What this means for the tier-1 firmware work" section below should be read as describing the deliberate-first-prototype-compromise framing of tier-1, not as "tier-1 is just for partnership credibility" — per the § 92 Resolution, tier-1 IS step 1 of the optimal road, just with the pragmatic nRF52840 compromise to keep first-prototype costs down. Keep reading for the original analysis — it's still accurate on what's hard about Garmin and where the genuine differentiation opportunities live.

You're not going to win by building a better Fenix. You'll lose for five years on hardware fundamentals you can't catch up on, then either run out of money or accidentally become a hardware company that doesn't ship enough units to amortize tooling.

The asymmetric play is to be the *software* that makes someone else's adequate hardware feel like a Garmin-killer. Three viable strategic vectors, in order of how cheap they are to test:

**Vector 1: Build a Connect IQ app or data field for existing Garmin owners.** Risk is zero, cost is a few weeks. You're addressing Garmin's #1 fault (UI / data presentation) without competing with their hardware at all. Distribution is via Garmin's own store, free reach. Downside: Garmin could sherlock you whenever they want — but they've been bad at building first-party data fields for a decade, so the risk is small. This is the cheapest possible market test of "does our software actually feel different to a Garmin owner?"

**Vector 2: Build a Wear OS app that's so good it makes a Galaxy Watch or Pixel Watch a credible Garmin alternative for sub-12hr runners.** Risk is low, cost is months. You already ship Wear OS. Differentiation: AI coach, social, community, polish — all things Garmin loses on. The trade is that you concede the 100hr-GPS ultra-marathon market entirely; Wear OS hardware can't get there. But the sub-12hr segment is bigger than the ultra segment, and Garmin's hold on it is much weaker.

**Vector 3: White-label or firmware-partner with a mid-tier ODM.** Mobvoi, Amazfit/Zepp, Polar's lower SKUs. Risk is medium, cost is significant but no tooling capital. You ship your software on their hardware, brand it as yours. Polar in particular has decent hardware and openly-criticised software — this is the COROS-of-2018 playbook. The trade is that you're tied to their hardware roadmap and have to negotiate the relationship.

What's *not* on this list: building your own watch from scratch. That's what the [§71 deferral](../architecture/decisions.md#71-own-hardware-an-ultra-marathon-watch-stays-research-only-watch-development-is-deferred-indefinitely) is about. The competitive analysis here is the evidence behind that deferral.

## What this means for the tier-1 firmware work

Tier 1 is still worth doing as personal investigation. You find out whether you enjoy firmware development. You build the domain credibility for the eventual Connect IQ or ODM-partner conversations. The bench prototype demystifies the whole hardware stack so you can talk to ODMs as an equal rather than as a software-only outsider.

But go in with the explicit framing that **tier 1's deliverable is knowledge plus a credible technical story for partnership conversations**, not "step 1 of building a Fenix-killer." That distinction is what protects you from sunk-cost escalation at tier 2.

If tier 1 goes well and you find that you genuinely love firmware development, the natural next move is **vector 3** (the ODM partnership) — you'll be a credible technical partner for an ODM, and you can put your tier-1 firmware architecture into their hardware without having to build a factory.

If tier 1 reveals that firmware isn't your jam, the natural next move is **vector 1 or 2** (Connect IQ app or Wear OS app) — both pure-software plays on existing hardware that benefit from the hardware knowledge you'll have built up.

Either way, the work isn't wasted.
