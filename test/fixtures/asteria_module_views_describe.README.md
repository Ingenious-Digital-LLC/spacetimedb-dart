# `asteria_module_views_describe.json` provenance

Captured from a real module's `spacetime describe --json` output, not hand-written. This is the second fixture referenced as a known gap in `asteria_describe_2.8.3.README.md` — it resolves that gap by covering the `Views` section.

- **SpacetimeDB CLI/server:** 2.8.3
- **Source module:** the [Asteria](https://github.com/Ingenious-Digital-LLC) project's `spacetimedb/` module on branch `feat/module-client-views` (commit `b44cf72`), published anonymously as database `asteria-local` on a local instance at `http://127.0.0.1:13000`.
- **Command:** `spacetime describe --server http://127.0.0.1:13000 asteria-local --json`, with the leading `WARNING: This command is UNSTABLE and subject to breaking changes.` line stripped and the remaining JSON pretty-printed.
- **Contents:** 2 tables (`birth_profile`, `natal_chart_result`, both `"table_access": {"Private": []}` — `describe` lists tables regardless of client visibility; neither is a client-subscribable public table), 4 reducers (`compute_natal_chart`, `delete_birth_profile`, `save_birth_profile`, `save_birth_profile_with_house_method`), 17 named types, 4 procedures, and **2 public views**: `my_birth_profiles` and `my_natal_charts` (`"is_public": true`).

## What this fixture proves that the first one couldn't

The `Views` section holds **bare `ViewSchema`-shaped objects** directly — e.g.:

```json
{
  "source_name": "my_birth_profiles",
  "index": 0,
  "is_public": true,
  "is_anonymous": false,
  "params": { "elements": [] },
  "return_type": { "Sum": { "variants": [...] } }
}
```

**not** wrapped in `{"View": {...}}` the way the legacy `misc_exports` array wraps them. An earlier version of the `_fromSections` parser assumed the wrapped shape by analogy with the legacy format (documented as best-effort, unverified) — that assumption was wrong and would have silently produced an empty views list against this real fixture, repeating the exact class of bug this PR exists to fix. `database_schema.dart` now parses `Views` section items directly, without a wrapper; `MiscExports` (if some server version ever emits it) is still accepted using the legacy wrapped convention as a defensive fallback, but that path remains unverified against a real fixture.
