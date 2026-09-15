# 18 — inner_html in one C pass

Status: DONE (1.9.163.7)

Element#inner_html walks children (bulk since TODO.perf/01) and
then serializes EACH child from Ruby: element children get one
ext dispatch each, text/comment/PI children are string-built in
Ruby and joined. An N-child element pays N dispatches plus the
case ladder plus the join.

Bind the whole pass in C: iterate the child chain once, appending
each child's serialization into one growable buffer — elements
through leptris_element_serialize_into (the fast_serialize
protocol), text nodes XML-escaped (& < > — the binding's
escape_text set), CDATA wrapped raw, comments and PIs wrapped.
One dispatch, one string mint, no Ruby per child.

Gates: inner_html parity for every child kind (elements, text
with entities, CDATA, comments, PIs, mixed), empty elements,
large children past the 4096-byte stack probe (growth path).

## Outcome (1.9.163.7)

Native.fast_inner_xml: one pass over the child chain into a
grow-only scratch — elements through leptris_element_serialize_into
(needed-1 protocol, grow+retry past capacity), text escaped with
the binding's entity set (& < > \r), CDATA raw-wrapped, comments
and PIs wrapped (PI data leading-whitespace-stripped, read_pi_data
parity). Byte-identical to the Ruby loop for every child kind and
past the 4KB growth floor (specs). Measured (load 17-31): 30-child
inner_html ~4.9µs (~160ns/child vs the loop's ~500-800ns/child
estimate).
