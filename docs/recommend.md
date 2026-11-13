# Song recommendations (Recommender)

`scripts/library/recommender.gd` (`class_name Recommender`) suggests songs for
all six modes: mania, orbit, rally, dirigent, trace, rebound. Pure logic,
static and deterministic. UI: the "For you" block in the song browser
(`scripts/song_select.gd`), level chips Easy / Challenge / Push per mode, can be hidden. Optional.
The block shows the player's style profile, a short reason per suggestion, pages
("Show more") and a group "Online" with maps that are not downloaded yet.

## Levels

| Level | Star range (P = own level) | Target |
|---|---|---|
| Easy | P-1.3 .. P-0.3 (always reaches down to 1 star) | P-0.6 |
| Challenge (default) | P .. P+0.6 | P+0.3 |
| Push | P+0.4 .. P+1.3, only maps that would enter the own top 10 | biggest gain |

If no map would enter the top 10, Push shows the next step at P+0.6 with the
reason "A step up: about N % expected".

## Skill per mode

Everything comes from the player's own runs, nothing is tuned to one player.

- **Level P** = the stars at which the player usually reaches rank B to A
  (`PLAY_ACC` 90 %, band 85-95 %). Each run implies a level: its stars, shifted by
  at most +-0.8 stars when its accuracy is outside the B-A band. Failed or aborted
  runs imply at most `stars - 1` and count half.
- **Weighting**: only the newest 60 runs; a run loses half its weight per 45 days
  behind the newest run. A default curve per mode counts like 3 runs, so players
  with fewer than 5 runs get careful suggestions.
- **Accuracy curve**: `acc(stars) = 0.90 - slope * (stars - P)`, slope fitted from
  the runs (0.03-0.15 accuracy per star, default 0.07 counts like 8 runs). Push may
  assume a good day of at most +3 %.
- **Performance**: Mania pp like the game (rosu-pp form:
  `kappa * max(stars-0.15, 0.05)^2.2 * max(0, 5*acc-4)`, 0 pp at 80 %, kappa fitted
  from the player's own pp); other modes `4 * stars^2 * acc^4` points, like the server
  ranking. Top list weighted 0.95^i.

## Style profile

One profile per mode, from that mode's runs, best scores and play counts
(`Recommender.taste`). Weight per map: 1 + 0.5 per replay (up to 4) + 0.5 at
accuracy >= 93 % + 1.5 if it is in a collection, times 0.7-1.0 by length (play time).
Needs 5 played maps with features.

| Part | Source |
|---|---|
| Patterns | note data: streams, jumpstream, jacks, chords, long notes (Mania); jumps, density (others); SV share |
| BPM range, length | 20 %-80 % quantile of the played maps, median length |
| Star range | 20 %-80 % quantile of the played stars (mode stars) |
| Genre, language, tags | `Tags` and `Source` of the .osu (`Recommender.genre_from_tags`) |
| Artist, mapper | map metadata |

Note data and tags are read in the background and cached in `user://rec_style.cfg`.

**Visible**: a line above the suggestions shows `Recommender.profile_text`, at most
5 parts: "Your style: Jumpstream, 170-190 BPM, ★ 2.4-3.1, Electronic" (de: "Dein
Stil: ..."). Its tooltip lists every part; the head shows the level.

**Bonus**: a matching map gets a bonus worth up to 0.3 stars of distance (Push:
+30 % gain). Parts: patterns 0.35, artist 0.2, genre/language 0.15, BPM 0.15,
length 0.15, mapper 0.1, tags 0.1, SV 0.1; missing features do not count.

**Reason**: every suggestion shows the expected accuracy (Push: the gain) and, from a
match of 0.45, what fits: "fits: 180 BPM, Jumpstream, like Night Drive" (de: "passt:
..."). At most two features plus one example map of the same pattern.

## Variety

- At most 2 maps per set and per artist.
- Novelty: a suggestion that was shown but not played loses 0.12 stars of distance
  per day shown (at most 4 times; Push: 8 % gain each). Counts live in
  `user://rec_seen.cfg`, expire after 21 days and reset when the map is played.
- "Show more" pages through up to 6 pages (`page_slice`). All pages come from the same
  background run, so paging does not stutter.

## Online suggestions

Maps that are not in the library, as their own group "Online" under the local ones.

- Query (`online_query`): 4K for all modes, osu!standard for Orbit; star range of the
  level; the favourite genre as search text. The mirror only knows osu! stars, so
  other modes shift the range by the median difference between osu! stars and mode
  stars of the player's own maps.
- Request: `OnlineBrowser.quiet_search`, the same mirrors and fallback chain as the
  online tab (osu.direct sorted by plays, catboy, osu.direct). One request per query,
  cached 12 h in `user://rec_online.cfg`; a second page only if fewer than 3
  suggestions remain; after a failure 10 minutes pause. Without internet the group is
  simply missing, no error text.
- Ranking (`online_rank`): closest difficulty to the level target, style bonus,
  a little popularity, novelty, one map per artist. Owned sets are removed.
- Card (2 per page): cover, title, stars, BPM, reason. Click plays the preview, "Get"
  downloads through the online browser; the map is selected as soon as it is installed.

## Suggestions

    Recommender.suggest(mode, level, candidates, n = 5, runs = [], now = 0, taste = {}, seen = {})
    Recommender.page_slice(items, page, per_page)
    Recommender.runs_from_store(mode, stars_of)   # runs from ScoreStore

Run: `{set, diff, stars, accuracy, pp, failed, unranked, grade, date}`.
Candidate: `{set, diff, stars, osu_mode (3 = 4K, 0 = standard), max_pp?, last_played?,
best_grade?, artist?, title?, mapper?, genre?, language?, tags?, bpm?, length?, style?, sv?}`.
Result: `[{set, diff, stars, expected_acc, expected_perf, reason, style_reason}]`, best first.

Filters: not played in the last 24 h, no SS, playable diffs only (trace/rebound/mania:
4K; orbit/rally/dirigent: standard and 4K), unknown stars skipped.

## Limits

- Stars of different modes are not comparable; every mode has its own curve.
- Mania stars of stored runs come from the caller (`stars_of`); ScoreStore does not keep them.
- Expected performance knows the note style only through the style bonus, not
  through skill per style (stamina vs. precision).
- Genre and language are guessed from tags; maps without tags have none.
- Online stars of non-Mania modes are an estimate (osu! stars minus the median shift).

## Example

Mania player, about 440 pp, mostly 2.7-star maps at rank B-A: level about 2.5.
Easy about 1.9 stars (~94 %), Challenge about 2.8 stars (~88 %), Push 2.9-3.1 stars
with reasons like "+7 pp, would be top 7". A 4.7-star map is never suggested.

## Tests

`tests/run_recommender_tests.gd` (synthetic profiles for all six modes: beginner, mid, pro, under 5 runs, only fails, 1000 runs; an anonymized real profile; Push; style; filters; determinism;
style profile, reasons, paging, novelty, online candidates and cache with fake data, no network):

    Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tests/run_recommender_tests.gd
