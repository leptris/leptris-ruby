# 03 — Bulk XPath result materialization

Status: TODO

NodeSet#fetch materializes results per node (wrap per item +
ResultText/ResultAttr captures). The #185 profile counted
NodeSet#initialize at 2.8% and Class#new 11.7% of walk wall —
result materialization shares that class of cost. Batch via the
ext: one C pass over leptris_xpath_result_get_node(i) building
the Ruby array with kinds, capturing text values in C.

Gate: xpath-heavy specs unchanged; xpath row (28,878 ips small)
improves on the battery.
