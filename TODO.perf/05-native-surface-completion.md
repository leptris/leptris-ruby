# 05 — Complete the NativeNode read surface

Status: TODO

Missing on NativeNode vs Element: #attributes (bulk attr hash),
#attribute_nodes, #namespaces / #prefix, #line / #byte_offset,
#inner_html / #to_xml (delegate to binding serialization), write
faces beyond add_child (set_attribute, set_text, remove). Reads
first; writes stay FFI (cold) unless measured otherwise.

Gate: native_layer specs mirror the binding feature specs;
descriptor_walk parity where applicable.
