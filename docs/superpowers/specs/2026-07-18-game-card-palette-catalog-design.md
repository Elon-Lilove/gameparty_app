# Game Card Palette Catalog Design

Date: 2026-07-18
Status: Approved visual direction; ready for implementation planning

## Summary

Replace the current hue-generated card colors with a bundled catalog of 96 curated, multi-color palettes. Each game may explicitly select a palette by ID. Games without an override receive a deterministic palette derived from the game ID, so filtering, sorting, or inserting games does not unexpectedly change existing card colors.

The palette direction is based on the supplied reference screenshot: jewel-dark surfaces with luminous accents and pale ornament colors, paired with cream/pastel surfaces and stronger accent colors. The implementation will reuse the color relationships only. It will not copy Genshin artwork, card ornaments, logos, or character assets.

## Current State and Problems

`GameHeaderPalettes.swift` currently builds 100 palettes from hue seeds and a golden-angle sequence. Each palette is mostly a single hue with different brightness values.

This creates four problems:

1. The palettes look algorithmic and do not match the multi-color reference direction.
2. Some views select colors by the index in a filtered list. A game can therefore change color when filters or ordering change.
3. Games cannot request a specific palette or replace it later without changing code.
4. Several card views still use hard-coded foreground colors, which prevents safe use of dark card backgrounds.

## Goals

- Provide exactly 96 curated palettes for the first release.
- Preserve the approved V2 color direction: 12 color families multiplied by 8 surface structures.
- Store palettes as a bundled JSON resource that can be edited without rewriting SwiftUI views.
- Give every palette a stable, human-readable ID.
- Allow each game to specify an optional `paletteID`.
- Give unassigned games a deterministic fallback based only on `game.id`.
- Keep the same game color across the home deck, filtered library, and detail view.
- Support both dark jewel cards and light pastel cards with readable semantic foreground colors.
- Validate data shape, unique IDs, color syntax, and contrast through automated tests.
- Decode the catalog once and keep lookup cost constant.

## Non-goals

- Reproducing the reference card artwork or ornamental design.
- Providing a runtime palette editor or admin interface.
- Guaranteeing that thousands of games all have unique palettes; controlled reuse is expected after 96 assignments.
- Downloading palettes from a server in this phase.
- Introducing a third-party color or JSON dependency.

## Approved Palette System

The catalog contains 12 families:

1. Emerald
2. Star Violet
3. Red Gold
4. Deep Ocean
5. Celadon
6. Star Sea
7. Amethyst
8. Rose
9. Coral
10. Amber
11. New Leaf
12. Silver Blue

Each family contains eight structures:

- `D1`: reference dark
- `D2`: lacquer dark
- `D3`: smoked dark
- `D4`: highlighted dark
- `L1`: reference light
- `L2`: cream light
- `L3`: mist light
- `L4`: vivid light

The initial emerald, violet, red, mint, lavender, and gold anchors come from color sampling of the supplied screenshot. The remaining families reuse the same relationships between surface, accent, ornament, and text colors.

Palette IDs are stable slugs such as `emerald-d1`, `violet-l2`, and `amber-d4`. Display names are metadata only and do not participate in lookup.

## JSON Resource

Add `PartyGames/Resources/game_card_palettes.json`. The existing Swift package already processes the complete `Resources` directory, so no new resource rule is required.

The file uses a versioned envelope:

```json
{
  "version": 1,
  "palettes": [
    {
      "id": "emerald-d1",
      "family": "emerald",
      "style": "reference-dark",
      "colors": {
        "backgroundTop": "#137647",
        "backgroundBottom": "#052214",
        "primaryText": "#FFF8EA",
        "secondaryText": "#D7DED4",
        "badge": "#2FAF70",
        "badgeText": "#052214",
        "tagStrongBackground": "#2B6348",
        "tagStrongText": "#FFF8EA",
        "tagMutedBackground": "#1E4A35",
        "tagMutedText": "#EDF5EA",
        "ornament": "#70C49C",
        "artBorder": "#88A18F"
      }
    }
  ]
}
```

All colors are opaque six-digit hexadecimal RGB values. Alpha is applied by the consuming SwiftUI view where needed, rather than being embedded in the resource.

## Swift Components

### `GameCardPaletteRecord`

A private `Decodable` representation of the JSON structure. It contains strings and metadata only and performs no UI work.

### `GameHeaderPalette`

The existing semantic palette type remains the view-facing API. It will expose:

- background top and bottom
- primary and secondary text
- badge and badge text
- strong and muted tag surfaces and text
- ornament/accent color
- art border color

Views consume semantic roles and never parse hexadecimal strings.

### `GameCardPaletteCatalog`

Responsibilities:

- Decode the bundled JSON once.
- Convert valid hexadecimal colors into SwiftUI `Color` values.
- Build an ID-to-palette dictionary for explicit lookup.
- Preserve the ordered palette array for deterministic fallback assignment.
- Expose palette count for warm-up and tests.
- Return a built-in safe light palette if the bundled resource cannot be decoded.

No file I/O occurs during normal card rendering after the catalog is initialized.

### `Game`

Add:

```swift
var paletteID: String? = nil
```

The property is optional so existing JSON and sample-game initializers remain compatible. Future game records can select a palette with a field such as:

```json
"paletteID": "violet-l1"
```

### Palette Resolver

All call sites use one API:

```swift
GameHeaderPalettes.palette(for: game)
```

Resolution order:

1. If `game.paletteID` matches a catalog ID, return that palette.
2. Otherwise compute a deterministic FNV-1a hash of the UTF-8 bytes in `game.id`.
3. Select `hash % paletteCount` from the ordered catalog.
4. If the catalog is empty or invalid, return the built-in safe palette.

Swift's standard `Hasher` will not be used because its seed is intentionally randomized between processes.

An unknown explicit palette ID falls back to the deterministic game-ID assignment. Debug builds should emit an assertion or diagnostic that names the invalid palette ID, while release builds continue safely.

## View Integration

Update the home deck, library grid, and detail screen to resolve palettes from the `Game` value rather than a filtered-list index.

The following hard-coded card foregrounds will use palette roles:

- main card title
- main card badge
- main card description
- metadata/stat text
- library card player label
- detail card intro
- inactive favorite icon when it sits on the palette surface
- art frame/border

The existing start-button gradient remains unchanged because it is a global action style, not part of the card palette.

This phase changes color tokens only. It does not add the ornamental frame graphics shown in the reference screenshot.

## Data Flow

1. `AppBootstrap` warms the palette catalog with the existing game payload.
2. `GameStore` decodes games, including an optional `paletteID`.
3. A card view asks `GameHeaderPalettes.palette(for: game)` for its semantic palette.
4. The resolver uses an explicit ID or deterministic fallback.
5. The same palette object drives the home, library, and detail representations.

Filtering and sorting affect which games are visible, but never participate in color assignment.

## Accessibility and Contrast

Every palette must pass automated contrast checks against both gradient endpoints:

- primary text: at least 4.5:1
- secondary/body text: at least 4.5:1 because current card copy is small
- badge text against badge surface: at least 4.5:1
- strong and muted tag text against their surfaces: at least 4.5:1

If a candidate color fails, the JSON color is corrected. Runtime color mutation is avoided so the previewed and shipped colors remain identical.

Color is not the only signal for game type, favorites, tags, or actions; existing text and icons remain.

## Error Handling

- Missing resource: use the built-in safe palette and emit a debug diagnostic.
- Unsupported catalog version: use the safe palette rather than partially decoding unknown data.
- Invalid hex string: reject the affected catalog load in tests; production falls back safely.
- Duplicate palette ID: reject the catalog in tests; production keeps the safe fallback.
- Unknown game `paletteID`: use stable game-ID fallback and emit a debug diagnostic.
- Empty game ID: hash the empty byte sequence consistently; the game model remains responsible for requiring meaningful IDs.

## Performance

The catalog contains only 96 small records. It is decoded once during bootstrap warm-up. Lookup uses a dictionary for explicit IDs and an array for fallback selection. No network, database, image processing, or per-frame color generation is added.

## Testing

Add focused unit tests that verify:

1. The bundled catalog decodes successfully and reports version 1.
2. It contains exactly 96 palettes.
3. Every palette ID is non-empty and unique.
4. Every required color is valid six-digit hexadecimal RGB.
5. All required contrast pairs pass the specified threshold at both gradient endpoints.
6. An explicit `paletteID` wins over automatic assignment.
7. An unknown `paletteID` falls back safely.
8. The same `game.id` resolves to the same palette regardless of list order or filtering.
9. Different processes receive the same fallback assignment because the resolver does not use randomized `Hasher`.
10. Existing games without `paletteID` continue to decode.

Run the full Swift package test suite and an iOS build after the focused tests pass.

## Migration Sequence

1. Add catalog decoding and validation tests.
2. Add the 96-record JSON resource.
3. Add semantic foreground roles and deterministic resolution.
4. Add optional `Game.paletteID` support.
5. Replace index-based palette calls in the home, library, and detail views.
6. Replace hard-coded foreground colors on palette surfaces.
7. Run focused tests, the full test suite, and the iOS build.

## Success Criteria

- The shipped palette catalog contains the approved 96 color combinations.
- The first six reference-derived combinations remain visually traceable to the supplied screenshot.
- A game's color does not change when the user filters or reorders games.
- A content author can replace a game's palette by editing only its `paletteID`.
- Dark and light cards remain readable in every card surface.
- No reference artwork, logo, or ornament graphic is copied.
