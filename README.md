# Reciprocity failure calculator

When shooting photos on photographic film in low light, the amount of sensitivity a film stock has degrades over time as the film continues to be exposed. When taking pictures at night for example, this can become a problem. Exposing photos according to a light meter will lead to underexposed photos. Thankfully however, this is a [well understood problem](<https://en.wikipedia.org/wiki/Reciprocity_(photography)?useskin=vector>).

Film manufacturers publish the "reciprocity factory", which allows us to calculate proper exposure times given a reading from a light meter. Different film stocks can have very different factors however, so this app functions as a database as much as a calculator.

## Examples

[Ilford](https://www.ilfordphoto.com/wp/wp-content/uploads/2024/05/Reciprocity-Failure-Compensation-v2.pdf) lists the factor for HP5+ at `1.31`. This means a meter reading of 10 seconds would give us roughly a `20 second` exposure time to properly expose the image. Delta 400 however with a factor of `1.41` would give an exposure time of `26 seconds`, or roughly a third of a stop difference.

```
Exposed_time = Metered_time ^ factor
```

Kodak and Fujifilm publish tables instead of a single factor (e.g. Tri-X: metered 1 s → 2 s, 10 s → 50 s, 100 s → 1200 s). For those films the app interpolates between published points on a log-log scale, and flags any result past the last published point as an estimate.

## Features

- Pick a film from the built-in database (searchable by name or ISO), or add your own with either a factor or a table.
- Enter the metered time however you write it: `30`, `1/2`, `2m30s`, `4:00`.
- See the corrected time, the extra stops, and a quick reference table for common times.
- Start a countdown timer for the corrected exposure. It keeps the screen awake and sends a notification when time is up.

## Film data

Built-in films live in [`data.json`](<Reciprocity Failure Calculator/data.json>). Each entry has either a power-law `factor` or a `table`:

```json
{ "brand": "Ilford", "stock": "HP5+", "iso": 400, "type": "bw", "factor": 1.31, "starts_at": 1 }
{ "brand": "Kodak", "stock": "Tri-X 400", "iso": 400, "type": "bw",
  "table": [{ "metered": 0.1, "corrected": 0.1 }, { "metered": 1, "corrected": 2 }] }
```

- `starts_at`: the metered time in seconds at or below which no correction is applied (default 1).
- `table`: start with the longest time that needs no correction (same value on both sides), then the manufacturer's rows.
- Optional: `iso`, `type` (`bw`, `color`, `slide`), `notes`, `source` (datasheet URL).

User-added films are stored separately on the device, in `custom-films.json`.

### References

- [Ilford](https://www.ilfordphoto.com/wp/wp-content/uploads/2024/05/Reciprocity-Failure-Compensation-v2.pdf)
- [Kodak](https://125px.com/docs/techpubs/kodak/e31-2002_07.pdf)

# Shooting with flash

With manual flash, the burst of light is far shorter than the shutter speed, so exposure comes down to two things: how far the light travels to the subject, and how wide the aperture is. Flash manufacturers rate their flashes with a [guide number](https://en.wikipedia.org/wiki/Guide_number) (GN) that ties the two together.

The guide number on the spec sheet is for full power at one ISO (usually 100) and one zoom setting. Light falls off with the square of distance, so doubling the ISO or the flash power multiplies the guide number by √2 rather than 2. This app handles that math and turns it into a setting you can dial in.

## Examples

A flash with a guide number of `36` (meters, at ISO 100) on full power lights a subject `4.5 m` away at f/8. Load ISO 400 film and the guide number becomes `72`, which reaches `9 m` at f/8. Drop to 1/4 power and it's back to `4.5 m`.

```
Guide_number = Distance × f_number
```

In daylight, the sun sets the exposure and the flash only fills in the shadows. The app uses the [Sunny 16 rule](https://en.wikipedia.org/wiki/Sunny_16_rule) to find the daylight aperture at your sync speed, then works out the flash power that puts the flash a set number of stops under the daylight. Around `−1⅔` stops opens up shadows without looking flashed.

## Features

- Enter your flash's guide number in meters or feet, and the ISO it's rated at.
- Manual mode: solve for subject distance, aperture, or flash power from the other two. A reference table shows the result at every power level.
- Power settings snap to what your flash can actually do: third or whole stops, down to its lowest setting (1/16 to 1/256).
- When a shot needs more than full power or less than the lowest setting, the app says so and tells you how far to move.
- Fill flash mode: pick how strong the fill should be (0 to −2 stops) and get the power for each lighting condition, from bright sun to open shade, or from your own meter reading.
- In fill mode the shutter stays at sync speed unless that would need an aperture wider than f/2.8. Apertures past f/22 are flagged, since most lenses stop there (use an ND filter instead).

### References

- [Guide number](https://en.wikipedia.org/wiki/Guide_number)
- [Sunny 16 rule](https://en.wikipedia.org/wiki/Sunny_16_rule)