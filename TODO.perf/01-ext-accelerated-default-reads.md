# 01 — Ext-accelerated default reads (no FFI marshaling on hot paths)

Status: SHIPPED (1.9.162.9) — name/content/prefix/[]-cold-path ride
the ext when the bundle is loaded. Per-read 276->84ns (3.3x,
pre-address) / attr 373->199ns. HONEST GATE FINDING: warm loops
cannot see it (memos serve after first touch) — the gate is the
COLD one-shot pass (fresh doc, one read per node): 13-25% on the
#187 shape. UTF-8 encoding via rb_utf8_str_new_cstr (suite specs
run both paths in one process: native_layer_spec sets the flag
mid-suite). COMPLETE (1.9.163.0): bulk children + bulk element_children for
binding wrappers (one C pass: class dispatch + ivars + identity
cache) — cold one-shot walk 9.2->1.2ms (7.8x, element_children +
name/[]/content). Both TODO items done.

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
