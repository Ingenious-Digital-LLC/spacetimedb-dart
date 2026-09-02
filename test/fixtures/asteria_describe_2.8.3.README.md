# `asteria_describe_2.8.3.json` provenance

Captured from a real module's `spacetime describe --json` output, not hand-written.

- **SpacetimeDB CLI/server:** 2.8.3 (`spacetime --version` reported `spacetimedb tool version 2.8.3; spacetimedb-lib version 2.8.3`)
- **Source module:** the [Asteria](https://github.com/Ingenious-Digital-LLC) project's `spacetimedb/` module (Rust, `#[spacetimedb::table]`/`#[spacetimedb::reducer]`/`#[spacetimedb::procedure]`), built with `spacetime build --module-path spacetimedb` and published anonymously to a fresh ephemeral local instance (`spacetime start --listen-addr 127.0.0.1:13000 --data-dir <fresh> --in-memory --non-interactive`, `spacetime publish --server http://127.0.0.1:13000 --module-path spacetimedb --anonymous --yes asteria-flutter-spike`).
- **Command:** `spacetime describe --json asteria-flutter-spike --server http://127.0.0.1:13000`, with the leading `WARNING: This command is UNSTABLE and subject to breaking changes.` line stripped and the remaining JSON pretty-printed.
- **Contents:** 1 table (`birth_profile`, private), 2 reducers (`save_birth_profile`, `save_birth_profile_with_house_method`), 16 named types, and 4 `#[spacetimedb::procedure]` entries under a `Procedures` section this SDK does not yet model. No views: the module declares none.
- **Why it matters:** this is the first real-world evidence that SpacetimeDB 2.8's `describe --json` output is shaped as `{"sections": [{"Typespace":...}, {"Types":...}, {"Tables":...}, {"Reducers":...}, {"Procedures":...}, {"ExplicitNames":...}]}`, not the flat `tables`/`reducers`/`types`/`typespace` root-key shape `DatabaseSchema.fromJson` previously required. Against this exact fixture, the generator (`dart run spacetimedb:generate`) reported `Tables: 0, Reducers: 0, Views: 0, Types: 0` with no error before this fix.

## Views gap — resolved

This fixture's module declares no views, so it can't cover the `Views` section. That gap is now closed by `asteria_module_views_describe.json`, captured from Asteria's `feat/module-client-views` branch once it published a module with two public views. See that fixture's README — it also documents a real parser bug the first attempt at "best-effort" views handling had (assumed a `{"View": {...}}` wrapper that the real `Views` section does not use).
