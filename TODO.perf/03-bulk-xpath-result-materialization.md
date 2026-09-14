# 03 — Bulk XPath result materialization

Status: SHIPPED (1.9.163.0) — one C pass (kind dispatch incl.
synthetic text/attr value capture, node-type consult for real
Text/CDATA under XPATH text, identity cache). HONEST FINDING: the
xpath one-shot is parse-dominated; the materialization slice gains
~1.4x. >512-entry results and rare kinds fall back to the per-index
path. No warm-path change.

NodeSet#fetch materializes results per node (wrap per item +
ResultText/ResultAttr captures). The #185 profile counted
NodeSet#initialize at 2.8% and Class#new 11.7% of walk wall —
result materialization shares that class of cost. Batch via the
ext: one C pass over leptris_xpath_result_get_node(i) building
the Ruby array with kinds, capturing text values in C.

Gate: xpath-heavy specs unchanged; xpath row (28,878 ips small)
improves on the battery.
