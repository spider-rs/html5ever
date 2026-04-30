# spider-html5ever

A `Send`-friendly fork of [`html5ever`](https://github.com/servo/html5ever) for high-concurrency HTML parsing.

[![crates.io](https://img.shields.io/crates/v/spider-html5ever.svg)](https://crates.io/crates/spider-html5ever)

## Why this fork?

Upstream `html5ever`'s `Tokenizer`, `TreeBuilder`, and `Parser` are `!Send` because they hold `StrTendril` (and types containing it) internally. `StrTendril` is `!Send` in upstream `tendril` because its refcount is non-atomic. The transitive effect: no future holding an html5ever parser across an `.await` point can be `Send`, so the parser can't run on tokio's multi-threaded runtime via `tokio::spawn`.

This fork swaps two dependencies:

- `tendril` → [`spider-tendril`](https://github.com/spider-rs/tendril) (atomic refcount default)
- `markup5ever` → [`spider-markup5ever`](https://github.com/spider-rs/markup5ever) (uses spider-tendril)

The html5ever source code itself is unchanged. The `Send`-ness propagates through the type system via the new tendril atomicity default.

Result:

- `Parser<Sink>: Send` whenever `Sink: Send`.
- `Tokenizer`, `TreeBuilder`, `BufferQueue`: `Send`.
- Async futures holding the parser across `.await` points are `Send`, enabling `tokio::spawn` on multi-threaded runtimes for true cooperative streaming HTML parsing.

The cost is a few extra atomic ops per refcount bump (≈5–10 ns each, ≪ µs in aggregate per parse). Behavior, parse output, and the public API are identical to upstream.

## Use

```toml
[dependencies]
spider-html5ever = "0.39"
```

```rust
use html5ever::{parse_document, ...};
```

The library still imports as `html5ever`, so existing code requires no changes — only the dependency line in `Cargo.toml` needs to swap.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT) at your option, matching the upstream `html5ever` license.
