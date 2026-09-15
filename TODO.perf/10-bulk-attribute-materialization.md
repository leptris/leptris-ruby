# 10 — Bulk attribute materialization for the binding

Status: TODO

Element#attributes / #each_attribute / #keys / #values walk the
attribute list with one FFI call per attribute (name + value per
row). One C pass materializes the {name => value} hash and the
key/value arrays in a single walk. Gate: attribute-heavy cold
reads improve; #attributes semantics unchanged (memoized, version
invalidated).
