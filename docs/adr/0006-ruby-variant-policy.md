# ADR 0006: the ruby-platform variant ships as the fallback, unvendored

## Context
The 1.9.0-era CHANGELOG said "never publishes ruby-platform releases
without the vendored library — platform variants only", and an early
fix removed the `gem:native:any` task. The 1.9.0 lockstep restored
the `ruby` matrix entry deliberately, and every release since has
published the variant — practice contradicting the recorded policy.

## Decision
The `ruby`-platform gem ships as the fallback/source variant WITHOUT
a vendored library, by design. It is safe because library resolution
is eager (issue #49): on a machine without a usable libleptris the
gem fails at `require` with the actionable remedy (install the
platform-specific variant or set LEPTRIS_LIB_PATH) instead of deep
inside Document.parse. Bundler prefers platform-specific gems
wherever they exist (9 of 10 published variants are precompiled);
the ruby variant serves source installs and exotic platforms that
accept providing their own library.

## Consequences
Do not re-propose removing the `platform: any` release leg without
new evidence that bundler misresolves it in practice. A future
change to the eager-load behavior (ADR 0005 ordering aside) must
keep the ruby variant failing loudly at require time.
