# 26 — Post-mutation memo seeding

Status: DONE (1.9.174.5)

Every mutation invalidates the read memos through the version
bump, so a write-then-read cycle pays a full re-derivation even
when the new value is known at write time. Seed it: Element#[]=
re-stamps @attr_values at the new version and writes the value
into it (a partial fill stays partial — same rules); content=
stores the new text as the @content memo at the new version;
name= already seeds @name.

Gates: []=/content=/name= followed by reads answers from the
seeded memo (spec-observable via identity for strings? — no,
values only); mixed attribute sets then attributes() still
rebuild the full face on demand; invalidation semantics
unchanged for other mutators.

## Outcome (1.9.174.5)

Element#[]= seeds the version-stamped @attr_values at the new
version (a just-invalidated valid partial memo extends in place;
a full face or anything older restarts partial, mirroring the
cold-[] rules); content= seeds @content; name= seeds @name
(already). Measured: the []= + [] read-back cycle runs ~545ns
(write + read combined).
