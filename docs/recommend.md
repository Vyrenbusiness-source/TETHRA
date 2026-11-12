# Song recommendations (Recommender)

`scripts/library/recommender.gd` (`class_name Recommender`) suggests songs for
all six modes: mania, orbit, rally, dirigent, trace, rebound. Pure logic,
static and deterministic. UI: the "For you" block in the song browser
(`scripts/song_select.gd`), level chips Easy / Challenge / Push per mode, can be hidden. Optional.

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

## Style

Preferences come from replays, good scores, collections, artist, BPM, length and note
style (Mania: streams, jumpstream, jacks, chords, long notes; other modes: jumps and
density). From 5 played maps with features on, a matching map gets a bonus worth up
to 0.3 stars of distance (Push: +30 % gain). At most 2 maps per set and per artist.
A style reason ("Jumpstream, like your favourites") only shows at a strong match.
Note styles are read in the background and cached in `user://rec_style.cfg`.

## Suggestions

    Recommender.suggest(mode, level, candidates, n = 5, runs = [], now = 0)
    Recommender.runs_from_store(mode, stars_of)   # runs from ScoreStore

Run: `{set, diff, stars, accuracy, pp, failed, unranked, grade, date}`.
Candidate: `{set, diff, stars, osu_mode (3 = 4K, 0 = standard), max_pp?, last_played?,
best_grade?, artist?, genre?, language?, bpm?, length?, style?}`.
Result: `[{set, diff, stars, expected_acc, expected_perf, reason}]`, best first.

Filters: not played in the last 24 h, no SS, playable diffs only (trace/rebound/mania:
4K; orbit/rally/dirigent: standard and 4K), unknown stars skipped.

## Limits

- Stars of different modes are not comparable; every mode has its own curve.
- Mania stars of stored runs come from the caller (`stars_of`); ScoreStore does not keep them.
- Expected performance knows the note style only through the style bonus, not
  through skill per style (stamina vs. precision).

## Example

Mania player, about 440 pp, mostly 2.7-star maps at rank B-A: level about 2.5.
Easy about 1.9 stars (~94 %), Challenge about 2.8 stars (~88 %), Push 2.9-3.1 stars
with reasons like "+7 pp, would be top 7". A 4.7-star map is never suggested.

## Tests

`tests/run_recommender_tests.gd` (synthetic profiles for all six modes: beginner, mid, pro, under 5 runs, only fails, 1000 runs; an anonymized real profile; Push; style; filters; determinism):

    Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tests/run_recommender_tests.gd
