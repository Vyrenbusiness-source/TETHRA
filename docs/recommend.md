# Song recommendations (Recommender)

`scripts/library/recommender.gd` (`class_name Recommender`) suggests songs for
all six modes: mania, orbit, rally, dirigent, trace, rebound. Pure logic,
static and deterministic. No UI yet (own task). Using it is optional.

## Levels

| Constant | ID | Meaning |
|---|---|---|
| `LEVEL_EASY` | `easy` | Easy: below the comfort level |
| `LEVEL_CHALLENGE` | `challenge` | Challenge (default): comfort level up to the limit |
| `LEVEL_PUSH` | `push` | Push: at/above the limit, chase new top performance |

The per-mode setting `Settings.recommend_level` is a later UI task; here only
the constants and `Recommender.normalize_level()` (unknown -> Challenge).
Texts are English sources passed through `TranslationServer.translate()`;
translations may keep the same terms.

## Skill per mode

Run performance:

- Mania: the run's `pp` (`StarService.pp_for`). Without pp: `kappa * stars^2 * acc^4`
  (`kappa` = median of own pp ratios, default `MANIA_K` = 10).
- Other modes: `4 * stars^2 * acc^4` (same as the server leaderboard). Failed or
  unranked runs count 0.

Rating = best value per map sorted descending, weighted `0.95^i`.

Accuracy curve (linear, per mode, slope 0.02 acc per star):

    acc(stars) = 0.97 - slope * (stars - comfort),  clamped 0.5 .. 0.995

Each run implies `comfort_i = stars + (acc - 0.97) / slope` (clamped to
stars-4 .. stars+3). A failed run (or grade F) counts with at most
`acc = 0.80 - 0.05`, so failures lower the estimate. The estimate is the
median of the latest 30 runs, blended with the default curve as if it were 3
extra runs:

    comfort = (median * n + default * 3) / (n + 3)

Defaults: mania 2.5 stars, all others 1.5 stars. So few runs give a cautious
estimate; one lucky 99 % run at 6 stars gives about 2.9, not 6.

- Comfort level = stars with expected acc 97 %.
- Limit = comfort + (0.97 - 0.915) / slope = comfort + 2.75 stars (expected acc 91.5 %).

## Suggestions

    Recommender.suggest(mode, level, candidates, n = 5, runs = [], now = 0)
    Recommender.runs_from_store(mode, stars_of)   # runs from ScoreStore

Run: `{set, diff, stars, accuracy, pp, failed, unranked, grade, date}`.
Candidate: `{set, diff, stars, osu_mode (3 = 4K, 0 = standard), max_pp?, last_played?, best_grade?}`.
Result: `[{set, diff, stars, expected_acc, expected_perf, reason}]`, best first.

Star range per level: Easy `comfort-1.5 .. comfort`, Challenge `comfort .. limit`,
Push `comfort .. limit+1.5`.

- Easy: closest to `comfort - 0.8`. Reason "Easy: about 98 % expected".
- Challenge: closest to `comfort + 0.4 * (limit - comfort)`. Reason "Challenge: about 95 % expected".
- Push: only maps with expected acc >= 85 % whose expected performance
  (`max_pp * acc^4`, mania without `max_pp`: `kappa * stars^2 * acc^4`) beats the
  own best on that map and lands in the own top 10. Sorted by gain in the
  weighted rating. Reasons: "+14 pp, would be top 3"; mania rank 1:
  "new top pp: +14 pp"; other modes use "pts".

Filters: not played in the last 24 h (candidate `last_played` or a run), no SS,
playable diffs only (trace/rebound/mania: 4K; orbit/rally/dirigent: standard and 4K),
unknown stars skipped. Variety: first pass one map per set, then at most 2 per set.
No candidates or none in range -> empty list.

## Limits

- Stars of different modes are not comparable; the curve is per mode.
- The slope is fixed (0.02/star), not fitted; players with a very steep or flat curve are over/underestimated.
- Mania `stars` for stored runs come from the caller (`stars_of`), ScoreStore does not keep them for mania.
- Expected performance ignores map type (stamina vs. precision).

## Example

Mania player, 20 runs around 4 stars at about 97 %: comfort about 4.0, limit about 6.75.
Push suggests maps at 4.0 .. 8.25 stars whose `max_pp * acc^4` beats the best pp;
e.g. a 6 star map with expected acc 93 % and 320 max pp: 240 pp, "new top pp: +35 pp".

## Tests

`tests/run_recommender_tests.gd` (synthetic scores: beginner, mid, pro for all six modes; Push; filters; determinism):

    Godot_v4.7-stable_win64_console.exe --headless --audio-driver Dummy --path . --script res://tests/run_recommender_tests.gd
