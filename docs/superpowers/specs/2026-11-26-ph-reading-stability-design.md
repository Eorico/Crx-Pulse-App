# pH reading stability — design (2026-11-26)

## Intent
The live pH value briefly jumps to 9–10 and falls back on the next poll. Remove that flicker without hiding a genuine out-of-range reading.

## What is known
The app never computes pH. `LocalEsp32Service._onRows` reads the value straight from the device/cloud row; `SensorCard`, alerts, analytics and the cache all consume that same field. There is no filtering in the path today. The firmware source is not in this workspace, so only the app side can change.

## Chosen approach: reject unconfirmed jumps at ingestion
- Add a pure helper (`lib/core/ph_reading_filter.dart`) that holds the last accepted pH and one pending candidate.
- A reading within 0.5 of the accepted value is used immediately. A jump larger than 0.5 is held: the previous value stays on screen until the next reading confirms the new one. If the next reading returns near the accepted value, the candidate is discarded.
- The first reading, and the first reading after readings are cleared (disconnect or stale data), is accepted immediately. Null/invalid input keeps the value null and resets the filter.
- Wire it into `LocalEsp32Service` where `ph` is assigned in `_onRows`, and reset it in `_clearReadings`. Filtering at ingestion means the card, alerts, analytics and cache all see the same stable value.

## Alternatives considered
- Median of the last three readings: discards a single spike but blends every value and needs a buffer. Not chosen.
- Clamp the displayed number into 6.5–8.5: would hide real breaches and break the pH alert. Rejected.
- Fix the probe's calibration in firmware: source is not available here.

## Non-goals
- Changing ammonia, turbidity or temperature readings.
- Changing how the device computes or transmits pH.

## Constraints
- No new dependencies.
- Existing uncommitted notification-detail work stays untouched.
- Tests cover: one spike ignored, two consecutive elevated readings accepted, small drift immediate, reset after clear, null handling.
