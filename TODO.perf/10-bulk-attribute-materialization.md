# 10 — Bulk attribute materialization for the binding

Status: DONE (1.9.163.5)

Element#attributes / #each_attribute / #keys / #values walk the
attribute list with one FFI call per attribute (name + value per
row). One C pass materializes the {name => value} hash and the
key/value arrays in a single walk. Gate: attribute-heavy cold
reads improve; #attributes semantics unchanged (memoized, version
invalidated).

## Outcome (1.9.163.5)

`Native.bulk_attr_faces` builds {name => Attr} + the values hash
in one C walk (Attr value objects: name/value/element ivars,
c_handle left nil); Element#attributes rides it when
auto-enabled and memo-stamps both hashes. Measured (load 12-19):
Element#attributes on a 5-attr element ~134-151ns vs Nokogiri
~1107-1165ns (~8x). The values-only shape
(`Native.bulk_attributes`) backs the legacy path.
