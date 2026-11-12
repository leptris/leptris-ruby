# 41 — C set-attribute entry (the write floor)

Status: QUEUED (leptris-ruby#622, ask 3)

`set_binding_text` landed (adopted behind a face probe); attribute-set
has no C entry — post-build `set_attribute` pays the binding-layer
crossing per attribute. `add_element_full` (TODO.sota/04) covers
build-time attrs only.

Unlocks: mutation-heavy/builder lanes (the build add_element row is
at 0.975x and rides on this for the post-hoc shape).
