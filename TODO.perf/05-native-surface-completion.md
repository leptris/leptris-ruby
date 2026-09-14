# 05 — Complete the NativeNode read surface

Status: SHIPPED (1.9.163.2) — #attributes (one C walk, string
values — deliberately the flat [] shape, not the binding's
Attr-valued hash), #line, #byte_offset with binding parity. Also:
binding classes in the ext resolve LAZILY (Init may run before
autoload loads Element — the standalone native_layer require
crashed before; fixed) and native_layer requires ffi first.
Remaining cold: writes stay FFI by design; attribute_nodes/
namespaces deferred until a consumer asks.

Missing on NativeNode vs Element: #attributes (bulk attr hash),
#attribute_nodes, #namespaces / #prefix, #line / #byte_offset,
#inner_html / #to_xml (delegate to binding serialization), write
faces beyond add_child (set_attribute, set_text, remove). Reads
first; writes stay FFI (cold) unless measured otherwise.

Gate: native_layer specs mirror the binding feature specs;
descriptor_walk parity where applicable.
