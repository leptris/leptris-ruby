# 01 — Ext-accelerated default reads (no FFI marshaling on hot paths)

Status: TODO

The default binding's hot reads each pay FFI per-call marshaling
(:string returns allocate through FFI, args marshal through the
boundary — ~200-500ns vs ~50ns for a direct ext call). The native
bundle already dlsyms every reader; add address-based C functions
the DEFAULT binding classes call when the bundle is loaded:

- Element#name / #content / #[]
- Node#children / #element_children (bulk: one C pass allocating
  binding wrappers — the bulk_wrap shape, 1.27-1.30x measured)
- Element#expanded_name (three out-params today)

Gate: suite green with AND without the bundle; drift-record rows
(attr reads 1.88x, text 6.18x) must improve; cold-walk gate must
not regress (cold-walk-regression-gate memory).
