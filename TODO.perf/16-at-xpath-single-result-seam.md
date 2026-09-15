# 16 — C-bound at_xpath single-result seam

Status: DONE (1.9.163.7)

at_xpath is the hottest query shape (adapters picking one node),
and its result path is five FFI calls per hit: result_type,
get_node(0), node_kind(0), Node.wrap (pointer + construct), and
result_free — plus the Ruby case dispatch between them. The bulk
machinery from TODO.perf/03 already knows how to materialize a
result entry as a binding wrapper in C (identity cache, kind
dispatch, attribute/text value capture).

Add Native.at_xpath_first(document, result_ptr): one C dispatch
checks the result type; nodesets materialize entry 0 through the
bulk machinery (get_nodes_ex with capacity 1 carries pointer +
kind in one call), free the result handle, and return the binding
node (or Qnil on empty); non-nodeset results return Qundef so the
existing Ruby scalar path keeps its exact semantics. Searchable's
wrap_xpath_first_result routes through the face when native is
enabled.

Gates: at_xpath parity for elements, attributes (ResultAttr name/
value capture), text-kind results, empty results, and scalars;
the result handle always freed exactly once.

## Outcome (1.9.163.7)

Native.at_xpath_first(document, result_ptr): one dispatch — type
check, entry-0 materialization through the extracted
materialize_xp_entry (shared with the TODO.perf/03 bulk loop:
identity cache, kind dispatch, attribute/text value capture),
result free. Non-nodeset results return the Native module object
(Qundef must never cross into Ruby) and keep the exact Ruby
scalar path. Measured: repeat at_xpath 3.7µs baseline -> 1.9µs
(TODO.perf/15) -> ~1.3µs with the seam (2.8x total, load 8-30;
the same-run Nokogiri comparison on this box is anomalous and not
reported). Specs pin element identity, attribute capture, text
kinds, nil misses, scalars, and xpath().first agreement.
