/* Native TypedData node prototype (#185/#147/#187 converged):
 * wrapper objects with the C pointer embedded (no FFI::Pointer per
 * node), hot reads (name/content/attribute) called directly in C
 * via dlsym on the FFI-loaded library, and children constructed in
 * bulk — one cache round-trip, zero Ruby frames, zero FFI
 * marshaling per node. */
#include <ruby.h>
#include <ruby/encoding.h>
#include <stdint.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

typedef const char *(*elem_name_fn)(void *);
typedef const char *(*text_content_fn)(void *);
typedef const char *(*attr_fn)(void *, const char *);
typedef size_t (*children_ex_fn)(void *, void **, int *, size_t);
typedef int (*node_type_fn)(void *);
typedef void *(*next_sibling_fn)(void *);
typedef void *(*parent_fn)(void *);
typedef const char *(*elem_prefix_fn)(void *);
typedef const char *(*elem_ns_fn)(void *);
typedef size_t (*xp_count_fn)(void *);
typedef size_t (*xp_nodes_ex_fn)(void *, void **, int *, size_t);
typedef int (*xp_node_kind_fn)(void *, int);
typedef const char *(*xp_node_name_fn)(void *, int);
typedef const char *(*xp_node_value_fn)(void *, int);
typedef size_t (*serialize_into_fn)(void *, char *, size_t, void *, void *);
typedef int (*ns_count_fn)(void *);
typedef void *(*attr_first_fn)(void *);
typedef void *(*attr_next_fn)(void *);
typedef const char *(*attr_name_fn)(void *);
typedef const char *(*attr_value_fn)(void *, void *);
typedef unsigned int (*node_line_fn)(void *);
typedef size_t (*node_offset_fn)(void *);
typedef const char *(*element_text_fn)(void *);
typedef void *(*doc_create_fn)(void);
typedef void *(*elem_create_fn)(void *, const char *);
typedef void *(*text_create_fn)(void *, const char *);
typedef void *(*create_child_fn)(void *, const char *);
typedef int (*append_child_fn)(void *, void *);
typedef int (*set_attr_fn)(void *, const char *, const char *);
typedef int (*set_root_fn)(void *, void *);
typedef void (*doc_free_fn)(void *);

static elem_name_fn f_elem_name;
static text_content_fn f_text_content;
static attr_fn f_attr;
static children_ex_fn f_children_ex;
static node_type_fn f_node_type;
static next_sibling_fn f_next_sibling;
static parent_fn f_parent;
static elem_prefix_fn f_elem_prefix;
static elem_ns_fn f_elem_ns;
static xp_count_fn f_xp_count;
static xp_nodes_ex_fn f_xp_nodes_ex;
static xp_node_kind_fn f_xp_node_kind;
static xp_node_name_fn f_xp_node_name;
static xp_node_value_fn f_xp_node_value;
static serialize_into_fn f_doc_serialize, f_elem_serialize;
static ns_count_fn f_elem_ns_count;
static attr_first_fn f_attr_first;
static attr_next_fn f_attr_next;
static attr_name_fn f_attr_name;
static attr_value_fn f_attr_value;
static node_line_fn f_node_line;
static node_offset_fn f_node_offset;
static element_text_fn f_element_text;
static doc_create_fn f_doc_create;
static elem_create_fn f_elem_create;
static text_create_fn f_text_create;
static create_child_fn f_create_child;
static append_child_fn f_append_child;
static append_child_fn f_prepend_child, f_insert_after, f_insert_before;
static set_attr_fn f_set_attr;
typedef int (*xp_type_fn)(void *);
typedef void (*xp_free_fn)(void *);
typedef void *(*first_child_fn)(void *);
typedef const char *(*node_str_fn)(void *);
static xp_type_fn f_xp_type;
static xp_free_fn f_xp_free;
static first_child_fn f_first_child;
static node_str_fn f_comment_content, f_cdata_content, f_pi_target,
                   f_pi_data;
typedef int (*set_str_fn)(void *, const char *);
typedef int (*node_unlink_fn)(void *);
typedef int (*traverse_cb_fn)(void *, void *);
typedef int (*traverse_fn)(void *, int, traverse_cb_fn, void *);
typedef void (*visit_cb_fn)(void *, void *, int, int);
typedef void (*visit_fn)(void *, visit_cb_fn, void *);
typedef void (*free_str_fn)(void *);
typedef const char *(*node_xpath_fn)(void *);
typedef void *(*elem_copy_fn)(void *, void *);
typedef void *(*parse_str_fn)(const char *, size_t, void *);
typedef void *(*parse_frag_fn)(const char *, size_t, void *, int *);
typedef const char *(*last_err_fn)(void);
typedef const char *(*status_str_fn)(int);
static set_str_fn f_elem_set_name, f_elem_set_text, f_text_set_content;
static node_unlink_fn f_node_unlink;
static traverse_fn f_node_traverse;
static visit_fn f_node_visit;
static free_str_fn f_free_str;
static node_xpath_fn f_node_xpath;
static elem_copy_fn f_elem_copy;
static parse_str_fn f_parse_str;
static parse_frag_fn f_parse_frag;
static last_err_fn f_last_err;
static status_str_fn f_status_str;
static set_root_fn f_set_root;
static doc_free_fn f_doc_free;

static VALUE c_native_node;
/* Ivar reads (TODO.perf/07 tail): the binding Document keeps the
 * C address and the caches in plain ivars, so the hot C faces skip
 * rb_funcall dispatch entirely. */
static ID id_iv_c_address, id_iv_native_cache, id_iv_binding_cache;
static ID id_iv_version, id_iv_readonly, id_address;
static ID id_iv_nn_content, id_iv_nn_content_ver;
static ID id_iv_nn_attrs, id_iv_nn_attrs_ver;
static ID id_child_klasses;
static VALUE c_use_after_free_error;

static VALUE native_cache_of(VALUE document);
static void resolve_binding_classes(void);
static VALUE binding_cache_of(VALUE document);
static VALUE binding_klass_for(int kind);
static VALUE c_iteration_scope;
static VALUE c_leptris_error;
static VALUE c_b_document, c_b_freed, c_ffi_pointer;
static ID id_ptr_new, id_freed_new, id_alive;
static void check_status_c(int st);

#define NT_ELEMENT 0

struct native_node {
    void *ptr;
    VALUE document;
    /* Single-slot read memos (#204 ask 1): the last attribute
     * query and the last content, stamped with the document's
     * mutation version (a Fixnum immediate — pointer compare).
     * Slot beats the hash memo on repeat reads of one name. */
    VALUE attr_key, attr_val, attr_ver;
    VALUE content_val, content_ver;
};

static void nn_mark(void *p)
{
    struct native_node *n = p;
    if (n->document != Qnil)
        rb_gc_mark(n->document);
    if (n->attr_key != Qnil)
        rb_gc_mark(n->attr_key);
    if (n->attr_val != Qnil)
        rb_gc_mark(n->attr_val);
    if (n->content_val != Qnil)
        rb_gc_mark(n->content_val);
}

static size_t nn_size(const void *p) { (void)p; return sizeof(struct native_node); }

static const rb_data_type_t nn_type = {
    "Leptris/XML/NativeNode",
    { nn_mark, RUBY_TYPED_DEFAULT_FREE, nn_size, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

#ifdef _WIN32
static void *lib_open(const char *path) { return (void *)LoadLibraryA(path); }
static void *lib_sym(void *h, const char *name)
{
    return (void *)GetProcAddress((HMODULE)h, name);
}
#else
static void *lib_open(const char *path) { return dlopen(path, RTLD_NOW); }
static void *lib_sym(void *h, const char *name) { return dlsym(h, name); }
#endif

static void resolve_symbols(const char *lib_path)
{
    void *h = lib_open(lib_path);
    if (!h)
        rb_raise(rb_eRuntimeError, "cannot load library %s", lib_path);
    f_elem_name = (elem_name_fn)lib_sym(h, "leptris_element_name");
    f_text_content = (text_content_fn)lib_sym(h, "leptris_text_node_get_content");
    f_attr = (attr_fn)lib_sym(h, "leptris_element_attribute");
    f_children_ex = (children_ex_fn)lib_sym(h, "leptris_node_children_ex");
    f_node_type = (node_type_fn)lib_sym(h, "leptris_node_get_type");
    f_next_sibling = (next_sibling_fn)lib_sym(h, "leptris_node_next_sibling");
    f_parent = (parent_fn)lib_sym(h, "leptris_node_parent");
    f_elem_prefix = (elem_prefix_fn)lib_sym(h, "leptris_element_prefix");
    f_elem_ns_count = (ns_count_fn)lib_sym(h, "leptris_element_namespace_count");
    f_elem_ns = (elem_ns_fn)lib_sym(h, "leptris_element_namespace");
    f_xp_count = (xp_count_fn)lib_sym(h, "leptris_xpath_result_count");
    f_xp_nodes_ex = (xp_nodes_ex_fn)lib_sym(h, "leptris_xpath_result_get_nodes_ex");
    f_xp_node_kind = (xp_node_kind_fn)lib_sym(h, "leptris_xpath_result_node_kind");
    f_xp_node_name = (xp_node_name_fn)lib_sym(h, "leptris_xpath_result_node_name");
    f_xp_node_value = (xp_node_value_fn)lib_sym(h, "leptris_xpath_result_node_value");
    f_doc_serialize = (serialize_into_fn)lib_sym(h, "leptris_document_serialize_into");
    f_elem_serialize = (serialize_into_fn)lib_sym(h, "leptris_element_serialize_into");
    f_attr_first = (attr_first_fn)lib_sym(h, "leptris_element_first_attribute");
    f_attr_next = (attr_next_fn)lib_sym(h, "leptris_attribute_next");
    f_attr_name = (attr_name_fn)lib_sym(h, "leptris_attribute_get_name");
    f_attr_value = (attr_value_fn)lib_sym(h, "leptris_attribute_get_value");
    f_node_line = (node_line_fn)lib_sym(h, "leptris_node_line");
    f_node_offset = (node_offset_fn)lib_sym(h, "leptris_node_byte_offset");
    f_element_text = (element_text_fn)lib_sym(h, "leptris_element_text");
    f_doc_create = (doc_create_fn)lib_sym(h, "leptris_document_create");
    f_elem_create = (elem_create_fn)lib_sym(h, "leptris_element_create");
    f_text_create = (text_create_fn)lib_sym(h, "leptris_text_node_create");
    f_create_child = (create_child_fn)lib_sym(h, "leptris_element_create_child");
    f_append_child = (append_child_fn)lib_sym(h, "leptris_element_append_child");
    f_prepend_child = (append_child_fn)lib_sym(h, "leptris_element_prepend_child");
    f_insert_after = (append_child_fn)lib_sym(h, "leptris_element_insert_after");
    f_insert_before = (append_child_fn)lib_sym(h, "leptris_element_insert_before");
    f_set_attr = (set_attr_fn)lib_sym(h, "leptris_element_set_attribute");
    f_xp_type = (xp_type_fn)lib_sym(h, "leptris_xpath_result_type");
    f_xp_free = (xp_free_fn)lib_sym(h, "leptris_xpath_result_free");
    f_first_child = (first_child_fn)lib_sym(h, "leptris_node_first_child");
    f_comment_content = (node_str_fn)lib_sym(h, "leptris_comment_node_get_content");
    f_cdata_content = (node_str_fn)lib_sym(h, "leptris_cdata_node_get_content");
    f_pi_target = (node_str_fn)lib_sym(h, "leptris_pi_node_get_target");
    f_pi_data = (node_str_fn)lib_sym(h, "leptris_pi_node_get_data");
    f_elem_set_name = (set_str_fn)lib_sym(h, "leptris_element_set_name");
    f_elem_set_text = (set_str_fn)lib_sym(h, "leptris_element_set_text");
    f_text_set_content = (set_str_fn)lib_sym(h, "leptris_text_node_set_content");
    f_node_unlink = (node_unlink_fn)lib_sym(h, "leptris_node_unlink");
    f_node_traverse = (traverse_fn)lib_sym(h, "leptris_node_traverse");
    f_node_visit = (visit_fn)lib_sym(h, "leptris_node_visit");
    f_free_str = (free_str_fn)lib_sym(h, "leptris_free_string");
    f_node_xpath = (node_xpath_fn)lib_sym(h, "leptris_node_get_xpath");
    f_elem_copy = (elem_copy_fn)lib_sym(h, "leptris_element_copy");
    f_parse_str = (parse_str_fn)lib_sym(h, "leptris_parse_string");
    f_parse_frag = (parse_frag_fn)lib_sym(h, "leptris_parse_fragment");
    f_last_err = (last_err_fn)lib_sym(h, "leptris_last_error");
    f_status_str = (status_str_fn)lib_sym(h, "leptris_status_string");
    f_set_root = (set_root_fn)lib_sym(h, "leptris_document_set_root");
    f_doc_free = (doc_free_fn)lib_sym(h, "leptris_document_free");
    if (!f_elem_name || !f_text_content || !f_attr ||
        !f_children_ex || !f_node_type || !f_next_sibling || !f_parent ||
        !f_element_text || !f_doc_create || !f_elem_create || !f_text_create ||
        !f_create_child || !f_append_child || !f_prepend_child ||
        !f_insert_after || !f_insert_before || !f_set_attr || !f_set_root ||
        !f_xp_type || !f_xp_free || !f_first_child ||
        !f_comment_content || !f_cdata_content || !f_pi_target ||
        !f_pi_data || !f_elem_set_name || !f_elem_set_text ||
        !f_text_set_content || !f_node_unlink ||
        !f_node_traverse || !f_node_visit || !f_free_str ||
        !f_node_xpath || !f_elem_copy || !f_parse_str ||
        !f_parse_frag || !f_last_err || !f_status_str ||
        !f_doc_free ||
        !f_elem_prefix || !f_xp_count || !f_xp_nodes_ex ||
        !f_xp_node_kind || !f_xp_node_name || !f_xp_node_value ||
        !f_doc_serialize || !f_elem_serialize || !f_attr_first ||
        !f_elem_ns_count || !f_elem_ns ||
        !f_attr_next || !f_attr_name || !f_attr_value ||
        !f_node_line || !f_node_offset)
        rb_raise(rb_eRuntimeError, "libleptris symbols missing");
}

static VALUE nn_name(VALUE self)
{
    struct native_node *n;
    const char *s;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    s = f_elem_name(n->ptr);
    /* Interned (shared, frozen) fstring: element names repeat
     * massively across a document — one RString per distinct name
     * per process instead of one per read (lutaml/moxml#249:
     * ~18% of consumer materialize allocations were fresh name
     * strings). Names are identifiers; nothing downstream mutates
     * them in place (renames mint new strings). */
    return s ? rb_enc_interned_str(s, strlen(s), rb_utf8_encoding()) : Qnil;
}

static VALUE nn_content(VALUE self)
{
    struct native_node *n;
    const char *s;
    VALUE doc, cached;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    /* Version-stamped content memo (the binding Document's
     * mutation version — the same invalidation discipline as
     * binding memos, ADR 0003): repeat reads are two struct
     * reads and a pointer compare. nil results never cache
     * (empty elements recompute — rare in hot walks). */
    doc = n->document;
    if (doc != Qnil && n->content_ver != Qnil &&
        n->content_ver == rb_ivar_get(doc, id_iv_version))
        return n->content_val;
    /* elements aggregate their text (leptris_element_text); text
     * nodes carry it directly. */
    s = f_node_type(n->ptr) == 0 ? f_element_text(n->ptr)
                                 : f_text_content(n->ptr);
    cached = s ? rb_utf8_str_new_cstr(s) : Qnil;
    if (doc != Qnil && cached != Qnil) {
        n->content_val = cached;
        n->content_ver = rb_ivar_get(doc, id_iv_version);
    }
    return cached;
}

static VALUE nf_fast_attribute2(VALUE self, VALUE addr, VALUE name)
{
    const char *s;
    (void)self;
    s = f_attr((void *)(uintptr_t)NUM2ULL(addr),
               RSTRING_PTR(StringValue(name)));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

/* 07 (#204 ask 1): StringValueCStr runs a memchr over the name
 * checking for embedded NULs — attribute names cannot contain
 * NULs, so StringValue + RSTRING_PTR skips the scan. */
static VALUE nn_attribute(VALUE self, VALUE name)
{
    struct native_node *n;
    VALUE doc, cache, v;
    const char *s;

    /* String-normalized once, used as both the C argument and the
     * cache key. */
    if (!RB_TYPE_P(name, T_STRING))
        name = rb_obj_as_string(name);
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    doc = n->document;
    /* Single-slot memo first: the last-queried name by VALUE
     * (callers may mint a fresh String per call) against the same
     * version. Then the hash memo for other repeat names; both
     * stamp with the document version, so any mutation through
     * either surface drops them. Absent names never cache (no
     * negative-cache staleness). */
    if (doc != Qnil && n->attr_ver == rb_ivar_get(doc, id_iv_version) &&
        n->attr_key != Qnil && rb_str_equal(n->attr_key, name))
        return n->attr_val;
    cache = Qnil;
    if (doc != Qnil) {
        cache = rb_ivar_get(self, id_iv_nn_attrs);
        if (cache != Qnil &&
            rb_ivar_get(self, id_iv_nn_attrs_ver) ==
                rb_ivar_get(doc, id_iv_version)) {
            v = rb_hash_aref(cache, name);
            if (v != Qnil) {
                n->attr_key = name;
                n->attr_val = v;
                n->attr_ver = rb_ivar_get(doc, id_iv_version);
                return v;
            }
        }
    }
    s = f_attr(n->ptr, RSTRING_PTR(name));
    v = s ? rb_utf8_str_new_cstr(s) : Qnil;
    if (doc != Qnil && v != Qnil) {
        if (cache == Qnil)
            cache = rb_hash_new();
        rb_hash_aset(cache, name, v);
        rb_ivar_set(self, id_iv_nn_attrs, cache);
        rb_ivar_set(self, id_iv_nn_attrs_ver,
                    rb_ivar_get(doc, id_iv_version));
        n->attr_key = name;
        n->attr_val = v;
        n->attr_ver = rb_ivar_get(doc, id_iv_version);
    }
    return v;
}

static VALUE nn_allocate(VALUE klass)
{
    struct native_node *n;
    return TypedData_Make_Struct(klass, struct native_node, &nn_type, n);
}

/* Klass-propagating reads (#246): a consumer subclass installed a
 * per-kind child-klass map; reads mint that class so the child
 * arrives already being the consumer's wrapper. Map-less callers
 * (the base class) keep today's base mint. */
static VALUE klass_for_kind(VALUE owner_klass, int kind)
{
    VALUE map = rb_attr_get(owner_klass, id_child_klasses);
    VALUE k;
    if (NIL_P(map))
        return c_native_node;
    k = rb_ary_entry(map, (long)kind);
    return RB_TYPE_P(k, T_CLASS) ? k : c_native_node;
}

static VALUE nn_install_child_klasses(VALUE self, VALUE map)
{
    long i, len;
    Check_Type(map, T_ARRAY);
    len = RARRAY_LEN(map);
    if (len > 5)
        rb_raise(rb_eArgError,
                 "child klasses: Array of classes/nil indexed by "
                 "node kind (element, text, comment, cdata, pi)");
    for (i = 0; i < len; i++) {
        VALUE k = rb_ary_entry(map, i);
        if (!NIL_P(k) &&
            !(RB_TYPE_P(k, T_CLASS) &&
              RTEST(rb_class_inherited_p(k, c_native_node))))
            rb_raise(rb_eTypeError,
                     "child klasses entries must be nil or a "
                     "Leptris::XML::NativeNode subclass");
    }
    rb_ivar_set(self, id_child_klasses, map);
    return self;
}

/* Bulk children: one native pass; cache check/store inline; the
 * document's wrapper_cache (a Ruby Hash keyed by address) provides
 * identity for nodes seen through other paths. */
/* Two-call children fetch (#202): children_ex copies
 * min(total, cap); a saturated fill means the list may be longer —
 * query the true count (buf NULL) and refetch grown. */
static int fetch_children_two_call(void *node, void ***buf_out,
                                   int **kinds_out)
{
    size_t cap = 512;
    void *b = ruby_xmalloc(cap * sizeof(void *));
    int *k = ruby_xmalloc((int)cap * sizeof(int));
    size_t count = f_children_ex(node, b, k, cap);
    if (count == cap) {
        size_t total = f_children_ex(node, NULL, NULL, 0);
        if (total > cap) {
            ruby_xfree(b);
            ruby_xfree(k);
            cap = total;
            b = ruby_xmalloc(cap * sizeof(void *));
            k = ruby_xmalloc((int)cap * sizeof(int));
            count = f_children_ex(node, b, k, cap);
        }
    }
    *buf_out = b;
    *kinds_out = k;
    return (int)count;
}

static VALUE nn_children(VALUE self)
{
    struct native_node *n;
    void **buf;
    int *kinds;
    int count, i;
    VALUE cache, out, owner_klass;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    count = fetch_children_two_call(n->ptr, &buf, &kinds);
    if (count <= 0) {
        ruby_xfree(buf);
        ruby_xfree(kinds);
        return rb_ary_new2(0);
    }

    cache = native_cache_of(n->document);
    out = rb_ary_new2(count);
    owner_klass = rb_obj_class(self);
    for (i = 0; i < count; i++) {
        uint64_t addr = (uint64_t)(uintptr_t)buf[i];
        VALUE key = ULL2NUM(addr);
        VALUE child = rb_hash_aref(cache, key);
        if (NIL_P(child)) {
            struct native_node *cn;
            child = nn_allocate(klass_for_kind(owner_klass, kinds[i]));
            TypedData_Get_Struct(child, struct native_node, &nn_type, cn);
            cn->ptr = buf[i];
            cn->document = n->document;
            rb_hash_aset(cache, key, child);
        }
        rb_ary_push(out, child);
    }
    ruby_xfree(buf);
    ruby_xfree(kinds);
    return out;
}

static VALUE nn_type_sym(VALUE self)
{
    struct native_node *n;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    switch (f_node_type(n->ptr)) {
    case 0: return ID2SYM(rb_intern("element"));
    case 1: return ID2SYM(rb_intern("text"));
    case 2: return ID2SYM(rb_intern("comment"));
    case 3: return ID2SYM(rb_intern("cdata"));
    case 4: return ID2SYM(rb_intern("pi"));
    default: return ID2SYM(rb_intern("node"));
    }
}

/* Bulk children filtered to elements — the walk shape consumers
 * actually iterate (#185's element_children parity). */
static VALUE nn_element_children(VALUE self)
{
    struct native_node *n;
    void **buf;
    int *kinds;
    int count, i;
    VALUE cache, out, child_klass;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    count = fetch_children_two_call(n->ptr, &buf, &kinds);
    if (count <= 0) {
        ruby_xfree(buf);
        ruby_xfree(kinds);
        return rb_ary_new2(0);
    }

    cache = native_cache_of(n->document);
    out = rb_ary_new();
    child_klass = klass_for_kind(rb_obj_class(self), NT_ELEMENT);
    for (i = 0; i < count; i++) {
        if (kinds[i] != NT_ELEMENT)
            continue;
        VALUE key = ULL2NUM((uint64_t)(uintptr_t)buf[i]);
        VALUE child = rb_hash_aref(cache, key);
        if (NIL_P(child)) {
            struct native_node *cn;
            child = nn_allocate(child_klass);
            TypedData_Get_Struct(child, struct native_node, &nn_type, cn);
            cn->ptr = buf[i];
            cn->document = n->document;
            rb_hash_aset(cache, key, child);
        }
        rb_ary_push(out, child);
    }
    ruby_xfree(buf);
    ruby_xfree(kinds);
    return out;
}

static VALUE wrap_cached(VALUE owner_klass, struct native_node *owner,
                         void *ptr)
{
    VALUE cache, key, node;
    struct native_node *n;

    cache = native_cache_of(owner->document);
    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    node = rb_hash_aref(cache, key);
    if (!NIL_P(node))
        return node;
    node = nn_allocate(klass_for_kind(owner_klass, f_node_type(ptr)));
    TypedData_Get_Struct(node, struct native_node, &nn_type, n);
    n->ptr = ptr;
    n->document = owner->document;
    rb_hash_aset(cache, key, node);
    return node;
}

static VALUE nn_next_sibling(VALUE self)
{
    struct native_node *n;
    void *sib;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    sib = f_next_sibling(n->ptr);
    return sib ? wrap_cached(rb_obj_class(self), n, sib) : Qnil;
}

static VALUE nn_parent(VALUE self)
{
    struct native_node *n;
    void *par;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    par = f_parent(n->ptr);
    return par ? wrap_cached(rb_obj_class(self), n, par) : Qnil;
}

/* Wrap a freshly-created C node as a NativeNode and register it
 * in the document's identity cache. */
static VALUE wrap_new(VALUE document, void *ptr)
{
    struct native_node *n;
    VALUE node, cache, key;

    node = nn_allocate(c_native_node);
    TypedData_Get_Struct(node, struct native_node, &nn_type, n);
    n->ptr = ptr;
    n->document = document;
    cache = native_cache_of(document);
    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    rb_hash_aset(cache, key, node);
    return node;
}

/* Document address from the binding Document's @c_address ivar
 * (nil once freed) — one ivar read, no method dispatch. */
static void *doc_ptr_of(VALUE document)
{
    VALUE addr = rb_ivar_get(document, id_iv_c_address);
    if (NIL_P(addr))
        rb_raise(rb_eRuntimeError, "document has been freed");
    return (void *)(uintptr_t)NUM2ULL(addr);
}

/* Per-document identity caches. Both are lazily allocated on the
 * Ruby side (@x ||= {}), so replicate that here: ivar read, create
 * and store when unset. */
static VALUE native_cache_of(VALUE document)
{
    VALUE cache = rb_ivar_get(document, id_iv_native_cache);
    if (NIL_P(cache)) {
        cache = rb_hash_new();
        rb_ivar_set(document, id_iv_native_cache, cache);
    }
    return cache;
}

static VALUE binding_cache_of(VALUE document)
{
    VALUE cache = rb_ivar_get(document, id_iv_binding_cache);
    if (NIL_P(cache)) {
        cache = rb_hash_new();
        rb_ivar_set(document, id_iv_binding_cache, cache);
    }
    return cache;
}


/* TODO.perf/08 (#204 ask 2): native mutations must advance the
 * binding Document's mutation version so binding memos invalidate
 * exactly as they do through the FFI write path — and respect the
 * readonly gate. Two ivar reads per mutation (the version is
 * always a Fixnum, readonly is Qfalse/Qtrue). */
static VALUE c_readonly_error;

static void document_advance_version(VALUE document)
{
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — native mutation attempted");
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
}

static VALUE nf_ns_lift_needed(VALUE self, VALUE addr)
{
    void *node = (void *)(uintptr_t)NUM2ULL(addr);
    const char *uri;
    (void)self;
    /* Exact semantics in two C calls: an element with NO resolved
     * namespace and NO own declarations cannot lose anything in a
     * move — bare name, no prefix binding, no default-ns
     * dependency, nothing to prune. Everything else takes the full
     * lift path (carries in-scope declarations, prunes redundant
     * own ones). */
    if (f_elem_ns_count(node) > 0)
        return Qtrue;
    uri = f_elem_ns(node);
    return (uri && *uri) ? Qtrue : Qfalse;
}

/* ---- C-bound append (TODO.perf/08-09, #204 ask 3) --------------
 * One dispatch for the common programmatic-build adoption: the
 * readonly + liveness gates, the provable no-op namespace-lift
 * predicate, the version bump, and the engine append. Returns
 * the engine status int; Qnil means the child DOES need the
 * namespace lift — the caller falls back to the Ruby path. */
static VALUE nf_append_binding_child(VALUE self, VALUE document,
                                     VALUE parent_addr, VALUE child_addr)
{
    void *parent, *child;
    const char *uri;
    int st;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    parent = (void *)(uintptr_t)NUM2ULL(parent_addr);
    child = (void *)(uintptr_t)NUM2ULL(child_addr);
    /* Same provable no-op as Element.skip_adoption_lift?: an
     * element with no resolved namespace and no own declarations
     * cannot lose anything in a move; non-elements can never need
     * a lift. */
    if (f_node_type(child) == NT_ELEMENT) {
        if (f_elem_ns_count(child) > 0)
            return Qnil;
        uri = f_elem_ns(child);
        if (uri && *uri)
            return Qnil;
    }
    /* Bump before the call, mirroring ensure_writable!: a failed
     * mutation merely discards memos. */
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    st = f_append_child(parent, child);
    check_status_c(st);
    return Qtrue;
}

/* C-bound set_attribute (TODO.perf/11, #204 gap row 0.25x): the
 * gates, the version bump (which drops the version-stamped
 * attribute memos on both surfaces), and the engine write in one
 * dispatch. */
static VALUE nf_set_binding_attribute(VALUE self, VALUE document,
                                      VALUE addr, VALUE name, VALUE value)
{
    void *node;
    int st;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    node = (void *)(uintptr_t)NUM2ULL(addr);
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    /* Attribute names cannot contain NULs (StringValueCStr's
     * memchr is a wasted scan); VALUES keep the scan so an
     * embedded-NUL value raises rather than truncates. */
    st = f_set_attr(node, RSTRING_PTR(StringValue(name)),
                    StringValueCStr(value));
    check_status_c(st);
    return Qtrue;
}

/* C-bound value mutations (TODO.perf/23): the same gates + bump
 * + engine write shape as set_binding_attribute. */
static VALUE nf_set_binding_name(VALUE self, VALUE document,
                                 VALUE addr, VALUE name)
{
    void *node;
    int st;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    node = (void *)(uintptr_t)NUM2ULL(addr);
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    st = f_elem_set_name(node, StringValueCStr(name));
    check_status_c(st);
    return Qtrue;
}

/* Element text or text-node content — kind-dispatched in C. */
static VALUE nf_set_binding_text(VALUE self, VALUE document,
                                 VALUE addr, VALUE content)
{
    void *node;
    int st;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    node = (void *)(uintptr_t)NUM2ULL(addr);
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    st = f_node_type(node) == NT_ELEMENT
             ? f_elem_set_text(node, StringValueCStr(content))
             : f_text_set_content(node, StringValueCStr(content));
    check_status_c(st);
    return Qtrue;
}

static VALUE nf_unlink_binding_node(VALUE self, VALUE document,
                                    VALUE addr)
{
    void *node;
    int st;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    node = (void *)(uintptr_t)NUM2ULL(addr);
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    st = f_node_unlink(node);
    check_status_c(st);
    return Qtrue;
}

/* C-bound root= (TODO.perf/33): gates + bump + engine set_root
 * in one dispatch. The caller keeps the lift decision and the
 * @root memo seed (wrap gives the right document association). */
static VALUE nf_set_binding_root(VALUE self, VALUE document,
                                 VALUE addr)
{
    void *node;
    int st;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    node = (void *)(uintptr_t)NUM2ULL(addr);
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    st = f_set_root(doc_ptr_of(document), node);
    check_status_c(st);
    return Qtrue;
}

/* ---- C-yield traversal (TODO.perf/27) ----------------------------
 * Same contracts as the Ruby FFI::Function versions without the
 * per-call closure: traverse is post-order with abort-at-self
 * (the receiver is the LAST node of its subtree in post-order,
 * so stopping at self bounds the walk exactly) and
 * stash-abort-raise exception discipline; visit passes (node,
 * entering, depth). Walk state lives on the caller's C stack —
 * nested traversals are independent. */
struct trav_state {
    VALUE document;
    VALUE err;
    void *self_ptr;
    int for_visit;
};

static VALUE trav_yield_one(VALUE arg)
{
    return rb_yield(arg);
}

static int trav_cb(void *node_ptr, void *user)
{
    struct trav_state *st = user;
    VALUE cache, key, node;
    int kind, state;

    if (st->err != Qnil)
        return 1;
    kind = f_node_type(node_ptr);
    cache = binding_cache_of(st->document);
    key = ULL2NUM((uint64_t)(uintptr_t)node_ptr);
    node = rb_hash_aref(cache, key);
    if (NIL_P(node)) {
        node = rb_obj_alloc(binding_klass_for(kind));
        rb_iv_set(node, "@c_address", key);
        rb_iv_set(node, "@document", st->document);
        rb_iv_set(node, "@parent", Qnil);
        if (rb_obj_class(st->document) == c_iteration_scope) {
            rb_iv_set(node, "@structure_memoizable", Qfalse);
            rb_iv_set(node, "@native_fast", Qfalse);
            rb_iv_set(node, "@pub_document", Qnil);
        } else {
            rb_iv_set(node, "@structure_memoizable", Qtrue);
            rb_iv_set(node, "@native_fast", Qtrue);
            rb_iv_set(node, "@pub_document", st->document);
        }
        rb_iv_set(node, "@addr_reads_fast", Qtrue);
        rb_iv_set(node, "@node_type", INT2FIX(kind));
        rb_hash_aset(cache, key, node);
    }
    rb_protect(trav_yield_one, node, &state);
    if (state) {
        st->err = rb_errinfo();
        return 1; /* abort the walk */
    }
    return node_ptr == st->self_ptr ? 1 : 0; /* abort-at-self */
}

static VALUE nf_traverse_binding(VALUE self, VALUE document,
                                 VALUE addr)
{
    struct trav_state st;

    (void)self;
    resolve_binding_classes();
    st.document = document;
    st.err = Qnil;
    st.self_ptr = (void *)(uintptr_t)NUM2ULL(addr);
    st.for_visit = 0;
    f_node_traverse(st.self_ptr, 1 /* TRAVERSE_POST_ORDER */,
                    trav_cb, &st);
    if (st.err != Qnil)
        rb_exc_raise(st.err);
    return Qnil;
}

struct visit_yield_args {
    VALUE node, entering, depth;
};

static VALUE trav_yield_args(VALUE arg)
{
    struct visit_yield_args *a = (struct visit_yield_args *)arg;
    return rb_yield_values(3, a->node, a->entering, a->depth);
}

/* Engine visit callback order is (user, node, entering, depth) —
 * the Ruby closure's |_, node_ptr, entering, depth| mirrors it. */
static void visit_cb(void *user, void *node_ptr, int entering,
                     int depth)
{
    /* visit's engine signature cannot abort; exceptions are
     * stashed and every later node is skipped — the raise
     * happens after the walk, same observable outcome. */
    struct trav_state *st = user;
    struct visit_yield_args va;
    VALUE cache, key, node;
    int kind, state;

    if (st->err != Qnil)
        return;
    kind = f_node_type(node_ptr);
    cache = binding_cache_of(st->document);
    key = ULL2NUM((uint64_t)(uintptr_t)node_ptr);
    node = rb_hash_aref(cache, key);
    if (NIL_P(node)) {
        node = rb_obj_alloc(binding_klass_for(kind));
        rb_iv_set(node, "@c_address", key);
        rb_iv_set(node, "@document", st->document);
        rb_iv_set(node, "@parent", Qnil);
        if (rb_obj_class(st->document) == c_iteration_scope) {
            rb_iv_set(node, "@structure_memoizable", Qfalse);
            rb_iv_set(node, "@native_fast", Qfalse);
            rb_iv_set(node, "@pub_document", Qnil);
        } else {
            rb_iv_set(node, "@structure_memoizable", Qtrue);
            rb_iv_set(node, "@native_fast", Qtrue);
            rb_iv_set(node, "@pub_document", st->document);
        }
        rb_iv_set(node, "@addr_reads_fast", Qtrue);
        rb_iv_set(node, "@node_type", INT2FIX(kind));
        rb_hash_aset(cache, key, node);
    }
    va.node = node;
    va.entering = entering ? Qtrue : Qfalse;
    va.depth = INT2NUM(depth);
    rb_protect(trav_yield_args, (VALUE)&va, &state);
    if (state)
        st->err = rb_errinfo();
}

static VALUE nf_visit_binding(VALUE self, VALUE document, VALUE addr)
{
    struct trav_state st;

    (void)self;
    resolve_binding_classes();
    st.document = document;
    st.err = Qnil;
    st.self_ptr = (void *)(uintptr_t)NUM2ULL(addr);
    st.for_visit = 1;
    f_node_visit(st.self_ptr, visit_cb, &st);
    if (st.err != Qnil)
        rb_exc_raise(st.err);
    return Qnil;
}

/* ---- Address-based fills (TODO.perf/28) -------------------------
 * Pure reads of node-local data — no cache, no version — the
 * same shapes the inner_html pass uses. */
static VALUE nf_fast_text_content(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_text_content((void *)(uintptr_t)NUM2ULL(addr));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nf_fast_comment_content(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_comment_content((void *)(uintptr_t)NUM2ULL(addr));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nf_fast_cdata_content(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_cdata_content((void *)(uintptr_t)NUM2ULL(addr));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nf_fast_pi_target(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_pi_target((void *)(uintptr_t)NUM2ULL(addr));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nf_fast_pi_data(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_pi_data((void *)(uintptr_t)NUM2ULL(addr));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

/* Shared construction for address-walk faces (TODO.perf/30):
 * cache lookup + kind-dispatched binding wrapper. */
static VALUE wrap_addr_node(VALUE document, void *ptr)
{
    VALUE cache, key, node;
    int kind;

    kind = f_node_type(ptr);
    cache = binding_cache_of(document);
    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    node = rb_hash_aref(cache, key);
    if (NIL_P(node)) {
        node = rb_obj_alloc(binding_klass_for(kind));
        rb_iv_set(node, "@c_address", key);
        rb_iv_set(node, "@document", document);
        rb_iv_set(node, "@parent", Qnil);
        if (rb_obj_class(document) == c_iteration_scope) {
            rb_iv_set(node, "@structure_memoizable", Qfalse);
            rb_iv_set(node, "@native_fast", Qfalse);
            rb_iv_set(node, "@pub_document", Qnil);
        } else {
            rb_iv_set(node, "@structure_memoizable", Qtrue);
            rb_iv_set(node, "@native_fast", Qtrue);
            rb_iv_set(node, "@pub_document", document);
        }
        rb_iv_set(node, "@addr_reads_fast", Qtrue);
        rb_iv_set(node, "@node_type", INT2FIX(kind));
        rb_hash_aset(cache, key, node);
    }
    return node;
}

/* First element child in one C walk (text-heavy parents paid two
 * FFI calls per skipped sibling). */
static VALUE nf_first_element_child(VALUE self, VALUE document,
                                    VALUE addr)
{
    void *p;

    (void)self;
    resolve_binding_classes();
    for (p = f_first_child((void *)(uintptr_t)NUM2ULL(addr));
         p != NULL; p = f_next_sibling(p)) {
        if (f_node_type(p) == NT_ELEMENT)
            return wrap_addr_node(document, p);
    }
    return Qnil;
}

/* Last element child in one C walk (the batch fetch materialized
 * every child to keep one). */
static VALUE nf_last_element_child(VALUE self, VALUE document,
                                   VALUE addr)
{
    void *p, *last = NULL;

    (void)self;
    resolve_binding_classes();
    for (p = f_first_child((void *)(uintptr_t)NUM2ULL(addr));
         p != NULL; p = f_next_sibling(p)) {
        if (f_node_type(p) == NT_ELEMENT)
            last = p;
    }
    return last ? wrap_addr_node(document, last) : Qnil;
}

/* Owned string: copy + free through the engine's seam (the
 * read_owned_string protocol). */
static VALUE nf_fast_path(VALUE self, VALUE addr)
{
    const char *s;
    VALUE out;
    (void)self;
    s = f_node_xpath((void *)(uintptr_t)NUM2ULL(addr));
    if (!s)
        return Qnil;
    out = rb_utf8_str_new_cstr(s);
    f_free_str((void *)s);
    return out;
}

/* C-bound insert family (TODO.perf/14): prepend / insert-after /
 * insert-before share append's gates + predicate + bump shape.
 * mode: 1 prepend, 2 after, 3 before (anchor = receiver). */
static VALUE nf_insert_binding_child(VALUE self, VALUE document,
                                     VALUE anchor_addr, VALUE child_addr,
                                     VALUE mode)
{
    void *anchor, *child;
    const char *uri;
    int st, m;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    anchor = (void *)(uintptr_t)NUM2ULL(anchor_addr);
    child = (void *)(uintptr_t)NUM2ULL(child_addr);
    m = FIX2INT(mode);
    if (f_node_type(child) == NT_ELEMENT) {
        if (f_elem_ns_count(child) > 0)
            return Qnil;
        uri = f_elem_ns(child);
        if (uri && *uri)
            return Qnil;
    }
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    switch (m) {
    case 1:  st = f_prepend_child(anchor, child); break;
    case 2:  st = f_insert_after(anchor, child);  break;
    case 3:  st = f_insert_before(anchor, child); break;
    default:
        rb_raise(rb_eArgError, "invalid insert mode %d", m);
        return Qnil;
    }
    check_status_c(st);
    return Qtrue;
}

/* Builder factories (#149): create in C, wrap as NativeNode — no
 * FFI::Pointer, no Ruby wrap_fresh path. */
static VALUE nn_create_element(VALUE klass, VALUE document, VALUE name)
{
    void *ptr;
    (void)klass;
    ptr = f_elem_create(doc_ptr_of(document), StringValueCStr(name));
    if (!ptr)
        rb_raise(rb_eRuntimeError, "leptris_element_create failed");
    return wrap_new(document, ptr);
}

static VALUE nn_create_text(VALUE klass, VALUE document, VALUE content)
{
    void *ptr;
    (void)klass;
    ptr = f_text_create(doc_ptr_of(document), StringValueCStr(content));
    if (!ptr)
        rb_raise(rb_eRuntimeError, "leptris_text_node_create failed");
    return wrap_new(document, ptr);
}

static VALUE nn_create_child(VALUE self, VALUE name)
{
    struct native_node *n;
    void *ptr;
    VALUE out;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    document_advance_version(n->document);
    ptr = f_create_child(n->ptr, StringValueCStr(name));
    if (!ptr)
        rb_raise(rb_eRuntimeError, "leptris_element_create_child failed");
    out = wrap_new(n->document, ptr);
    return out;
}

static VALUE nn_append_child(VALUE self, VALUE child)
{
    struct native_node *n, *c;
    int rc;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    TypedData_Get_Struct(child, struct native_node, &nn_type, c);
    document_advance_version(n->document);
    rc = f_append_child(n->ptr, c->ptr);
    if (rc != 0)
        rb_raise(rb_eRuntimeError, "leptris_element_append_child failed (%d)", rc);
    return child;
}

static VALUE nn_set_root(VALUE klass, VALUE document, VALUE element)
{
    struct native_node *n;
    int rc;
    (void)klass;
    TypedData_Get_Struct(element, struct native_node, &nn_type, n);
    document_advance_version(document);
    rc = f_set_root(doc_ptr_of(document), n->ptr);
    if (rc != 0)
        rb_raise(rb_eRuntimeError, "leptris_document_set_root failed (%d)", rc);
    return element;
}

/* NativeNode surface completion (TODO.perf/05): bulk attribute
 * hash (name => value, one C walk, no per-attr Ruby frames) and
 * the position readers. */
static VALUE nn_attributes(VALUE self)
{
    struct native_node *n;
    VALUE hash;
    void *attr;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    hash = rb_hash_new();
    attr = f_attr_first(n->ptr);
    while (attr) {
        const char *name = f_attr_name(attr);
        const char *value = f_attr_value(n->ptr, attr);
        rb_hash_aset(hash,
                     name ? rb_utf8_str_new_cstr(name) : Qnil,
                     value ? rb_utf8_str_new_cstr(value) : Qnil);
        attr = f_attr_next(attr);
    }
    return hash;
}

static VALUE nn_line(VALUE self)
{
    struct native_node *n;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    return UINT2NUM(f_node_line(n->ptr));
}

static VALUE nn_byte_offset(VALUE self)
{
    struct native_node *n;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    return ULL2NUM((uint64_t)f_node_offset(n->ptr));
}

/* The owning binding Document (moxml #213: adapters route
 * native.document exactly like Node#document). */
static VALUE nn_document(VALUE self)
{
    struct native_node *n;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    return n->document;
}

static VALUE nn_address(VALUE self)
{
    struct native_node *n;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    return ULL2NUM((uint64_t)(uintptr_t)n->ptr);
}

/* ---- Bulk children for BINDING wrappers (TODO.perf/01 tail) ----
 * One C pass: children_ex + binding-class dispatch + ivar set +
 * identity-cache check/store. Returns a Ruby Array of Element/
 * Text/... wrappers — Node#children swaps this in when the ext
 * is loaded. Class constants and FFI::Pointer resolve once at
 * Init; the per-node Ruby frames (wrap/construct/memo/alive)
 * disappear. */
static VALUE c_b_element = Qundef, c_b_text, c_b_comment, c_b_cdata,
             c_b_pi, c_b_entity_ref, c_b_node, c_b_result_text,
             c_b_result_attr,
             c_b_attr, c_ffi_pointer, c_b_document, c_b_freed;
static VALUE c_iteration_scope;
static ID id_ptr_new;

/* Binding classes resolve LAZILY: Init_native can run before the
 * binding's autoload entries load (require "leptris" flow) —
 * rb_path2class at Init time raises for undefined constants. */
static void resolve_binding_classes(void)
{
    if (c_b_element != Qundef)
        return;
    c_b_element = rb_path2class("Leptris::XML::Element");
    c_b_text = rb_path2class("Leptris::XML::Text");
    c_b_comment = rb_path2class("Leptris::XML::Comment");
    c_b_cdata = rb_path2class("Leptris::XML::CDATA");
    c_b_pi = rb_path2class("Leptris::XML::ProcessingInstruction");
    c_b_entity_ref = rb_path2class("Leptris::XML::EntityReference");
    c_b_node = rb_path2class("Leptris::XML::Node");
    c_b_result_text = rb_path2class("Leptris::XML::ResultText");
    c_b_result_attr = rb_path2class("Leptris::XML::ResultAttr");
    c_ffi_pointer = rb_path2class("FFI::Pointer");
    c_b_attr = rb_path2class("Leptris::XML::Attr");
    c_b_document = rb_path2class("Leptris::XML::Document");
    c_b_freed = rb_path2class("Leptris::XML::Document::Freed");
    c_iteration_scope = rb_path2class("Leptris::XML::IterationScope");
    c_leptris_error = rb_path2class("Leptris::XML::Error");
    id_ptr_new = rb_intern("new");
    rb_gc_register_mark_object(c_b_element);
    rb_gc_register_mark_object(c_b_text);
    rb_gc_register_mark_object(c_b_comment);
    rb_gc_register_mark_object(c_b_cdata);
    rb_gc_register_mark_object(c_b_pi);
    rb_gc_register_mark_object(c_b_entity_ref);
    rb_gc_register_mark_object(c_b_node);
    rb_gc_register_mark_object(c_b_result_text);
    rb_gc_register_mark_object(c_b_result_attr);
    rb_gc_register_mark_object(c_ffi_pointer);
    rb_gc_register_mark_object(c_b_attr);
    rb_gc_register_mark_object(c_b_document);
    rb_gc_register_mark_object(c_b_freed);
    rb_gc_register_mark_object(c_iteration_scope);
    rb_gc_register_mark_object(c_leptris_error);
}

static VALUE binding_klass_for(int kind)
{
    switch (kind) {
    case 0: return c_b_element;
    case 1: return c_b_text;
    case 2: return c_b_comment;
    case 3: return c_b_cdata;
    case 4: return c_b_pi;
    case 10: return c_b_entity_ref; /* #212 / upstream #1094 */
    default: return c_b_node;
    }
}

static VALUE bulk_children_impl(VALUE document, VALUE parent_addr,
                                int elements_only)
{
    void **buf;
    int *kinds;
    int count, i;
    VALUE cache, out;

    count = fetch_children_two_call((void *)(uintptr_t)NUM2ULL(parent_addr),
                                    &buf, &kinds);
    if (count <= 0) {
        ruby_xfree(buf);
        ruby_xfree(kinds);
        return rb_ary_new2(0);
    }

    cache = binding_cache_of(document);
    out = rb_ary_new2(elements_only ? 8 : count);
    for (i = 0; i < count; i++) {
        VALUE key, node;
        if (elements_only && kinds[i] != 0)
            continue;
        key = ULL2NUM((uint64_t)(uintptr_t)buf[i]);
        node = rb_hash_aref(cache, key);
        if (NIL_P(node)) {
            node = rb_obj_alloc(binding_klass_for(kinds[i]));
            rb_iv_set(node, "@c_address", key);
            rb_iv_set(node, "@document", document);
            rb_iv_set(node, "@parent", Qnil);
            /* TODO.perf/25: scope-aware stamps — the IterationScope
             * flows through here as "document" for iterparse
             * elements; those stay memo-exempt and FFI-mutating,
             * but address-based reads are cache-free and safe. */
            if (rb_obj_class(document) == c_iteration_scope) {
                rb_iv_set(node, "@structure_memoizable", Qfalse);
                rb_iv_set(node, "@native_fast", Qfalse);
                rb_iv_set(node, "@pub_document", Qnil);
            } else {
                rb_iv_set(node, "@structure_memoizable", Qtrue);
                rb_iv_set(node, "@native_fast", Qtrue);
                rb_iv_set(node, "@pub_document", document);
            }
            rb_iv_set(node, "@addr_reads_fast", Qtrue);
            rb_iv_set(node, "@node_type", INT2FIX(kinds[i]));
            rb_hash_aset(cache, key, node);
        }
        rb_ary_push(out, node);
    }
    ruby_xfree(buf);
    ruby_xfree(kinds);
    return out;
}

static VALUE nf_bulk_children(VALUE self, VALUE document, VALUE parent_addr)
{
    (void)self;
    resolve_binding_classes();
    return bulk_children_impl(document, parent_addr, 0);
}

static VALUE nf_bulk_element_children(VALUE self, VALUE document,
                                      VALUE parent_addr)
{
    (void)self;
    resolve_binding_classes();
    return bulk_children_impl(document, parent_addr, 1);
}

/* ---- Bulk XPath result materialization (TODO.perf/03) ----------
 * One C pass over leptris_xpath_result_get_nodes_ex: binding-class
 * dispatch (XPATH_NODE space: 0 element, 1 attribute, 2 text,
 * 3 other), value capture for synthetic text/attribute items
 * while the result handle is alive, identity-cache check/store
 * for elements. Returns the Ruby Array. */
static VALUE m_native_sentinel; /* module object = fallback marker */
static VALUE materialize_xp_entry(VALUE document, VALUE cache,
                                  void *result, void *ptr, int kind,
                                  int idx);
static VALUE binding_klass_for(int kind);
static VALUE c_iteration_scope;

static VALUE bulk_xpath_array(VALUE document, void *result);

static VALUE nf_bulk_xpath(VALUE self, VALUE document, VALUE result_ptr_val)
{
    (void)self;
    return bulk_xpath_array(document,
                            (void *)(uintptr_t)NUM2ULL(result_ptr_val));
}

/* TODO.perf/22: materialize AND free — the eager xpath path owns
 * the handle lifecycle in C; no Ruby AutoPointer, no finalizer. */
static VALUE nf_materialize_xpath(VALUE self, VALUE document,
                                  VALUE result_ptr_val)
{
    void *result = (void *)(uintptr_t)NUM2ULL(result_ptr_val);
    VALUE out;
    long i, n;

    (void)self;
    out = bulk_xpath_array(document, result);
    n = RARRAY_LEN(out);
    for (i = 0; i < n; i++) {
        if (rb_ary_entry(out, i) == m_native_sentinel) {
            /* Exotic kinds need the Ruby fallback per entry — the
             * caller keeps the handle and goes the lazy path. */
            return Qnil;
        }
    }
    f_xp_free(result);
    return out;
}

static VALUE bulk_xpath_array(VALUE document, void *result)
{
    void **buf;
    int *kinds;
    int count, i;
    VALUE cache, out;

    resolve_binding_classes();
    size_t scount = f_xp_count(result);
    if (scount == 0)
        return rb_ary_new2(0);

    buf = ruby_xmalloc(scount * sizeof(void *));
    kinds = ruby_xmalloc(scount * sizeof(int));
    scount = f_xp_nodes_ex(result, buf, kinds, scount);
    count = (int)scount;
    if (count <= 0) {
        ruby_xfree(buf);
        ruby_xfree(kinds);
        return rb_ary_new2(0);
    }
    cache = binding_cache_of(document);
    out = rb_ary_new2(count);
    for (i = 0; i < count; i++) {
        if (buf[i] == NULL)
            continue;
        rb_ary_push(out, materialize_xp_entry(document, cache, result,
                                              buf[i], kinds[i], i));
    }
    ruby_xfree(buf);
    ruby_xfree(kinds);
    return out;
}

/* Materializes ONE result entry as a binding wrapper (or the
 * module sentinel for the rare kinds the bulk path defers to
 * Ruby). Shared by the bulk materializer (TODO.perf/03) and the
 * at_xpath single-result seam (TODO.perf/16). */
static VALUE materialize_xp_entry(VALUE document, VALUE cache,
                                  void *result, void *ptr, int kind,
                                  int idx)
{
    VALUE node, key;
    const char *s;

    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    switch (kind) {
    case 0: /* element */
        node = rb_hash_aref(cache, key);
        if (NIL_P(node)) {
            node = rb_obj_alloc(c_b_element);
            rb_iv_set(node, "@c_address", key);
            rb_iv_set(node, "@document", document);
            rb_iv_set(node, "@parent", Qnil);
            rb_iv_set(node, "@structure_memoizable", Qtrue);
            rb_iv_set(node, "@native_fast", Qtrue);
                rb_iv_set(node, "@pub_document", document);
            rb_iv_set(node, "@node_type", INT2FIX(0));
            rb_hash_aset(cache, key, node);
        }
        return node;
    case 1: /* synthetic attribute */
        {
            const char *name = f_xp_node_name(result, idx);
            const char *value = f_xp_node_value(result, idx);
            node = rb_obj_alloc(c_b_result_attr);
            rb_iv_set(node, "@c_address", key);
            rb_iv_set(node, "@document", document);
            rb_iv_set(node, "@attr_name",
                      name ? rb_utf8_str_new_cstr(name) : Qnil);
            rb_iv_set(node, "@attr_value",
                      value ? rb_utf8_str_new_cstr(value) : Qnil);
        }
        return node;
    case 2: /* text-kind: synthetic sequence carrier, or a real
             * Text/CDATA node (XPath reports both as TEXT) —
             * dispatch on the node's own type like Node.wrap. */
        {
            int nt = f_node_type(ptr);
            if (nt == 8) { /* NODE_SYNTHETIC_TEXT */
                s = f_xp_node_value(result, idx);
                node = rb_obj_alloc(c_b_result_text);
                rb_iv_set(node, "@c_address", key);
                rb_iv_set(node, "@document", document);
                rb_iv_set(node, "@value",
                          s ? rb_utf8_str_new_cstr(s) : Qnil);
                return node;
            }
            node = rb_hash_aref(cache, key);
            if (NIL_P(node)) {
                node = rb_obj_alloc(binding_klass_for(nt));
                rb_iv_set(node, "@c_address", key);
                rb_iv_set(node, "@document", document);
                rb_iv_set(node, "@parent", Qnil);
                rb_iv_set(node, "@structure_memoizable", Qtrue);
                rb_iv_set(node, "@native_fast", Qtrue);
                rb_iv_set(node, "@pub_document", document);
                rb_iv_set(node, "@node_type", INT2FIX(nt));
                rb_hash_aset(cache, key, node);
            }
        }
        return node;
    default: /* other: rare — signal Ruby fallback for this entry */
        return m_native_sentinel;
    }
}

/* ---- at_xpath single-result seam (TODO.perf/16) ----------------
 * One dispatch for the hottest query shape: type check, entry-0
 * materialization through the bulk machinery, result free.
 * Non-nodeset results return Qundef — the caller keeps the exact
 * Ruby scalar path (and owns the free there). */
static VALUE nf_at_xpath_first(VALUE self, VALUE document,
                               VALUE result_ptr_val)
{
    void *result = (void *)(uintptr_t)NUM2ULL(result_ptr_val);
    void *buf;
    int kind;
    size_t scount;
    VALUE node;

    (void)self;
    resolve_binding_classes();
    if (f_xp_type(result) != 0) /* XPATH_NODESET */
        return m_native_sentinel; /* caller keeps the scalar path */
    scount = f_xp_count(result);
    if (scount == 0) {
        f_xp_free(result);
        return Qnil;
    }
    buf = NULL;
    scount = f_xp_nodes_ex(result, &buf, &kind, 1);
    if (scount == 0 || buf == NULL) {
        f_xp_free(result);
        return Qnil;
    }
    node = materialize_xp_entry(document, binding_cache_of(document),
                                result, buf, kind, 0);
    f_xp_free(result);
    return node;
}

/* ---- Bulk attribute materialization (TODO.perf/10) ---------------
 * Element#attributes / #keys / #values walk the attribute list
 * one FFI call per row (name + value). One C pass builds the
 * {name => value} hash for the binding. */
static VALUE nf_bulk_attributes(VALUE self, VALUE addr)
{
    void *node = (void *)(uintptr_t)NUM2ULL(addr);
    VALUE hash = rb_hash_new();
    void *attr = f_attr_first(node);

    (void)self;
    while (attr) {
        const char *name = f_attr_name(attr);
        const char *value = f_attr_value(node, attr);
        rb_hash_aset(hash,
                     name ? rb_utf8_str_new_cstr(name) : Qnil,
                     value ? rb_utf8_str_new_cstr(value) : Qnil);
        attr = f_attr_next(attr);
    }
    return hash;
}

/* ---- Binding create via C (TODO.perf/09): one call creates the
 * node AND constructs the binding wrapper (class dispatch, ivars,
 * identity-cache store) — no FFI marshaling, no wrap_fresh path. */
static VALUE nf_create_binding_element(VALUE self, VALUE document,
                                       VALUE name)
{
    void *doc = doc_ptr_of(document);
    void *ptr = f_elem_create(doc, RSTRING_PTR(StringValue(name)));
    VALUE node, cache, key;

    (void)self;
    resolve_binding_classes();
    if (!ptr)
        return Qnil; /* caller raises with the error channel */
    node = rb_obj_alloc(c_b_element);
    rb_iv_set(node, "@c_address",
              ULL2NUM((uint64_t)(uintptr_t)ptr));
    rb_iv_set(node, "@document", document);
    rb_iv_set(node, "@parent", Qnil);
    rb_iv_set(node, "@structure_memoizable", Qtrue);
    rb_iv_set(node, "@native_fast", Qtrue);
                rb_iv_set(node, "@pub_document", document);
    rb_iv_set(node, "@node_type", INT2FIX(0));
    cache = binding_cache_of(document);
    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    rb_hash_aset(cache, key, node);
    return node;
}

static VALUE nf_create_binding_text(VALUE self, VALUE document,
                                    VALUE content)
{
    void *doc = doc_ptr_of(document);
    void *ptr = f_text_create(doc, RSTRING_PTR(StringValue(content)));
    VALUE node, cache, key;

    (void)self;
    resolve_binding_classes();
    if (!ptr)
        return Qnil;
    node = rb_obj_alloc(c_b_text);
    rb_iv_set(node, "@c_address",
              ULL2NUM((uint64_t)(uintptr_t)ptr));
    rb_iv_set(node, "@document", document);
    rb_iv_set(node, "@parent", Qnil);
    rb_iv_set(node, "@structure_memoizable", Qtrue);
    rb_iv_set(node, "@native_fast", Qtrue);
                rb_iv_set(node, "@pub_document", document);
    rb_iv_set(node, "@node_type", INT2FIX(1));
    cache = binding_cache_of(document);
    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    rb_hash_aset(cache, key, node);
    return node;
}

/* ---- Bulk attribute FACES (TODO.perf/10): {name => Attr} with
 * the values hash beside it — the exact shapes Element#attributes
 * memoizes, built in one walk. Attr is a value object
 * (name/value/element ivars; c_handle optional). */

static ID id_iv_name, id_iv_value, id_iv_element;

static VALUE nf_bulk_attr_faces(VALUE self, VALUE addr, VALUE element)
{
    void *node = (void *)(uintptr_t)NUM2ULL(addr);
    VALUE faces = rb_hash_new();
    VALUE values = rb_hash_new();
    void *attr = f_attr_first(node);

    (void)self;
    resolve_binding_classes();
    while (attr) {
        const char *name = f_attr_name(attr);
        const char *value = f_attr_value(node, attr);
        VALUE k = name ? rb_utf8_str_new_cstr(name) : Qnil;
        VALUE v = value ? rb_utf8_str_new_cstr(value) : Qnil;
        VALUE a = rb_obj_alloc(c_b_attr);
        rb_iv_set(a, "@name", k);
        rb_iv_set(a, "@value", v);
        rb_iv_set(a, "@element", element);
        rb_hash_aset(faces, k, a);
        rb_hash_aset(values, k, v);
        attr = f_attr_next(attr);
    }
    return rb_assoc_new(faces, values);
}

/* ---- Ext-bound serialization (TODO.perf/04) ---------------------
 * The whole sized-buffer cycle in C: build SerializeOptions on
 * the stack, call (buf, cap, NULL status, opts), grow if needed,
 * return a UTF-8 String. No FFI marshaling, no Ruby buffer
 * management per to_xml call. */
struct serialize_opts {
    int indent;
    int xml_declaration;
    const char *encoding;
};

/* Grow-only scratch for large serializations. Safe under the GVL:
 * synchronous C calls hold it, so no two Ruby threads run this
 * concurrently. */
static char *ser_buf;
static size_t ser_cap;

static VALUE fast_serialize(serialize_into_fn fn, void *node,
                            int indent, int xml_declaration,
                            VALUE encoding)
{
    struct serialize_opts opts;
    char stack_buf[4096];
    size_t needed;

    char *probe;
    size_t probe_cap;

    opts.indent = indent;
    opts.xml_declaration = xml_declaration;
    /* The Ruby string's bytes stay valid across the synchronous
     * engine call (TODO.perf/36). */
    opts.encoding = NIL_P(encoding)
                        ? NULL
                        : StringValueCStr(encoding);
    /* Probe the largest buffer we own: a big scratch from a prior
     * call usually fits (single serialization); cold calls start
     * on the stack buffer. */
    if (ser_cap > sizeof(stack_buf)) {
        probe = ser_buf;
        probe_cap = ser_cap;
    } else {
        probe = stack_buf;
        probe_cap = sizeof(stack_buf);
    }
    needed = fn(node, probe, probe_cap, NULL, &opts);
    if (needed == 0)
        return rb_utf8_str_new_cstr("");
    if (needed <= probe_cap)
        return rb_utf8_str_new(probe, needed - 1);
    if (needed > ser_cap) {
        ser_buf = ruby_xrealloc(ser_buf, needed);
        ser_cap = needed;
    }
    needed = fn(node, ser_buf, ser_cap, NULL, &opts);
    return needed > 0 ? rb_utf8_str_new(ser_buf, needed - 1)
                      : rb_utf8_str_new_cstr("");
}

static VALUE nf_fast_document_xml(VALUE self, VALUE addr,
                                  VALUE indent, VALUE decl,
                                  VALUE encoding)
{
    (void)self;
    return fast_serialize(f_doc_serialize,
                          (void *)(uintptr_t)NUM2ULL(addr),
                          NUM2INT(indent), RTEST(decl) ? 1 : 0,
                          encoding);
}

static VALUE nf_fast_element_xml(VALUE self, VALUE addr,
                                 VALUE indent, VALUE decl,
                                 VALUE encoding)
{
    (void)self;
    return fast_serialize(f_elem_serialize,
                          (void *)(uintptr_t)NUM2ULL(addr),
                          NUM2INT(indent), RTEST(decl) ? 1 : 0,
                          encoding);
}

/* ---- Bulk hydration walker (TODO.perf/38, #230) -----------------
 * Pre-order walk that materializes one Hash per element node
 * (kind, name, prefix, uri, attrs as Array<[name,value]>, text,
 * depth, line) and yields it to a Ruby Proc (walk_subtree) or
 * collects it into an Array (snapshot). No per-node Node wrapper
 * construction — the consumer iterates rows and builds their
 * typed objects directly. */
/* Node kinds (mirror types.h). Documented in descriptor comment. */
#define WS_NODE_ELEMENT 0
#define WS_NODE_TEXT 1
#define WS_NODE_COMMENT 2
#define WS_NODE_CDATA 3
#define WS_NODE_PI 4
#define WS_NODE_DOCTYPE 5

static VALUE build_element_row(VALUE doc, void *elem, int depth)
{
    VALUE row = rb_hash_new();
    rb_hash_aset(row, ID2SYM(rb_intern("kind")),
                 rb_utf8_str_new_cstr("element"));
    const char *name = f_elem_name(elem);
    rb_hash_aset(row, ID2SYM(rb_intern("name")),
                 name ? rb_utf8_str_new_cstr(name) : Qnil);
    rb_hash_aset(row, ID2SYM(rb_intern("prefix")),
                 f_elem_prefix(elem) ? rb_utf8_str_new_cstr(f_elem_prefix(elem)) : Qnil);
    rb_hash_aset(row, ID2SYM(rb_intern("uri")),
                 f_elem_ns(elem) ? rb_utf8_str_new_cstr(f_elem_ns(elem)) : Qnil);
    /* attrs: name/value pairs as Array<[name, value]>. */
    VALUE attrs = rb_ary_new();
    void *a = f_attr_first(elem);
    while (a) {
        VALUE pair = rb_ary_new_capa(2);
        const char *an = f_attr_name(a);
        const char *av = f_attr_value(elem, a);
        rb_ary_push(pair, an ? rb_utf8_str_new_cstr(an) : Qnil);
        rb_ary_push(pair, av ? rb_utf8_str_new_cstr(av) : Qnil);
        rb_ary_push(attrs, pair);
        a = f_attr_next(a);
    }
    rb_hash_aset(row, ID2SYM(rb_intern("attrs")), attrs);
    /* text: first text-child content (moxml-style common case). */
    void *c = f_first_child(elem);
    VALUE text = Qnil;
    while (c) {
        if (f_node_type(c) == WS_NODE_TEXT) {
            const char *t = f_text_content(c);
            text = t ? rb_utf8_str_new_cstr(t) : Qnil;
            break;
        }
        c = f_next_sibling(c);
    }
    rb_hash_aset(row, ID2SYM(rb_intern("text")), text);
    rb_hash_aset(row, ID2SYM(rb_intern("depth")), INT2NUM(depth));
    return row;
}

static VALUE build_text_row(int kind, int depth, const char *t)
{
    VALUE row = rb_hash_new();
    rb_hash_aset(row, ID2SYM(rb_intern("kind")),
                 rb_utf8_str_new_cstr(kind == WS_NODE_TEXT ? "text"
                                    : kind == WS_NODE_COMMENT ? "comment"
                                    : kind == WS_NODE_CDATA ? "cdata" : "other"));
    rb_hash_aset(row, ID2SYM(rb_intern("text")),
                 t ? rb_utf8_str_new_cstr(t) : Qnil);
    rb_hash_aset(row, ID2SYM(rb_intern("depth")), INT2NUM(depth));
    return row;
}

static void yield_or_collect_row(VALUE out_or_block, VALUE row, int collect)
{
    if (collect) {
        rb_ary_push(out_or_block, row);
    } else {
        rb_funcall(out_or_block, rb_intern("call"), 1, row);
    }
}

static void walk_subtree_impl(VALUE doc, void *node, int depth, VALUE out_or_block, int collect)
{
    int kind = f_node_type(node);
    if (kind == WS_NODE_ELEMENT) {
        void *c;
        yield_or_collect_row(out_or_block, build_element_row(doc, node, depth), collect);
        c = f_first_child(node);
        while (c) {
            walk_subtree_impl(doc, c, depth + 1, out_or_block, collect);
            c = f_next_sibling(c);
        }
    } else if (kind == WS_NODE_DOCTYPE || kind == 9 /* DOCUMENT */) {
        void *dc = f_first_child(node);
        while (dc) {
            walk_subtree_impl(doc, dc, depth, out_or_block, collect);
            dc = f_next_sibling(dc);
        }
    } else if (kind == WS_NODE_TEXT || kind == WS_NODE_COMMENT ||
               kind == WS_NODE_CDATA || kind == WS_NODE_PI) {
        const char *t = NULL;
        if (kind == WS_NODE_TEXT)
            t = f_text_content(node);
        else if (kind == WS_NODE_COMMENT)
            t = f_comment_content(node);
        else if (kind == WS_NODE_CDATA)
            t = f_cdata_content(node);
        else if (kind == WS_NODE_PI)
            t = f_pi_data(node);
        yield_or_collect_row(out_or_block, build_text_row(kind, depth, t), collect);
    }
}

static VALUE nf_snapshot_subtree(VALUE self, VALUE document, VALUE addr)
{
    VALUE out = rb_ary_new();
    walk_subtree_impl(document, (void *)(uintptr_t)NUM2ULL(addr), 0, out, 1);
    return out;
}

/* ---- Lean plan rows (lutaml/moxml#249 plan layer) ----------------
 * Elements only, one 4-tuple per element: [name, attrs_flat, text,
 * depth] — no Hash per row, no text/comment rows, attr and element
 * NAMES interned (shared frozen fstrings: names repeat across the
 * document, so repeat reads allocate zero). Pre-order, depth 0 at
 * the addressed node. */
static void walk_rows_impl(void *node, int depth, VALUE out)
{
    if (f_node_type(node) == WS_NODE_ELEMENT) {
        VALUE row = rb_ary_new_capa(4);
        VALUE attrs;
        const char *name = f_elem_name(node);
        const char *an;
        const char *av;
        void *a;
        void *c;

        rb_ary_store(row, 0, name ? rb_enc_interned_str(name, strlen(name),
                                                     rb_utf8_encoding())
                                  : Qnil);
        attrs = rb_ary_new();
        for (a = f_attr_first(node); a; a = f_attr_next(a)) {
            an = f_attr_name(a);
            av = f_attr_value(node, a);
            rb_ary_push(attrs, an ? rb_enc_interned_str(an, strlen(an),
                                                         rb_utf8_encoding())
                                  : Qnil);
            rb_ary_push(attrs, av ? rb_utf8_str_new_cstr(av) : Qnil);
        }
        rb_ary_store(row, 1, attrs);
        for (c = f_first_child(node); c; c = f_next_sibling(c)) {
            if (f_node_type(c) == WS_NODE_TEXT) {
                const char *t = f_text_content(c);
                rb_ary_store(row, 2, t ? rb_utf8_str_new_cstr(t) : Qnil);
                break;
            }
        }
        rb_ary_store(row, 3, INT2NUM(depth));
        rb_ary_push(out, row);

        for (c = f_first_child(node); c; c = f_next_sibling(c)) {
            walk_rows_impl(c, depth + 1, out);
        }
    } else if (f_node_type(node) == WS_NODE_DOCTYPE || f_node_type(node) == 9) {
        void *dc = f_first_child(node);
        while (dc) {
            walk_rows_impl(dc, depth, out);
            dc = f_next_sibling(dc);
        }
    }
}

static VALUE nf_snapshot_rows(VALUE self, VALUE document, VALUE addr)
{
    (void)self;
    (void)document;
    VALUE out = rb_ary_new();
    walk_rows_impl((void *)(uintptr_t)NUM2ULL(addr), 0, out);
    return out;
}

/* ---- inner_html in one C pass (TODO.perf/18) --------------------
 * Serializes the receiver's children into one growable buffer:
 * elements via leptris_element_serialize_into (the same opts the
 * Ruby loop passed), text XML-escaped with the binding's entity
 * set (& < > \r), CDATA/comments/PIs wrapped raw — byte-identical
 * to Element#inner_html's per-child loop. */
static char *inner_buf;
static size_t inner_cap;

static void inner_ensure(size_t need)
{
    if (need > inner_cap) {
        inner_cap = need < 64 ? 64 : need;
        inner_buf = ruby_xrealloc(inner_buf, inner_cap);
    }
}

static size_t inner_append_raw(const char *s, size_t len, size_t at)
{
    inner_ensure(at + len + 1);
    if (len)
        memcpy(inner_buf + at, s, len);
    return at + len;
}

static size_t inner_append_escaped(const char *s, size_t at)
{
    for (; s && *s; s++) {
        const char *repl;
        size_t rl;
        switch (*s) {
        case '&':  repl = "&amp;";  rl = 5; break;
        case '<':  repl = "&lt;";   rl = 4; break;
        case '>':  repl = "&gt;";   rl = 4; break;
        case '\r': repl = "&#xD;"; rl = 5; break;
        default:   repl = NULL;     rl = 0; break;
        }
        if (repl) {
            at = inner_append_raw(repl, rl, at);
        } else {
            inner_ensure(at + 2);
            inner_buf[at++] = *s;
        }
    }
    return at;
}

static VALUE nf_fast_inner_xml(VALUE self, VALUE addr)
{
    void *node = (void *)(uintptr_t)NUM2ULL(addr);
    void *child;
    struct serialize_opts opts;
    size_t at = 0, needed;

    (void)self;
    opts.indent = 0;
    opts.xml_declaration = 1; /* matches element_xml_default */
    opts.encoding = NULL;
    inner_ensure(4096);
    for (child = f_first_child(node); child != NULL;
         child = f_next_sibling(child)) {
        switch (f_node_type(child)) {
        case 0: /* element */
            needed = f_elem_serialize(child, inner_buf + at,
                                      inner_cap - at, NULL, &opts);
            if (needed > 0) {
                if (needed > inner_cap - at) {
                    inner_ensure(at + needed);
                    needed = f_elem_serialize(child, inner_buf + at,
                                              inner_cap - at, NULL, &opts);
                }
                at += needed - 1; /* size includes the NUL */
            }
            break;
        case 1: /* text */
            at = inner_append_escaped(f_text_content(child), at);
            break;
        case 2: /* comment */
            at = inner_append_raw("<!--", 4, at);
            at = inner_append_escaped(f_comment_content(child), at);
            at = inner_append_raw("-->", 3, at);
            break;
        case 3: { /* CDATA */
            const char *c = f_cdata_content(child);
            at = inner_append_raw("<![CDATA[", 9, at);
            at = inner_append_raw(c, c ? strlen(c) : 0, at);
            at = inner_append_raw("]]>", 3, at);
            break;
        }
        case 4: { /* PI — the binding strips leading whitespace from
                   * the data before joining (read_pi_data parity). */
            const char *data = f_pi_data(child);
            while (data && (*data == ' ' || *data == '\t' ||
                            *data == '\r' || *data == '\n'))
                data++;
            at = inner_append_raw("<?", 2, at);
            at = inner_append_escaped(f_pi_target(child), at);
            if (data && *data) {
                at = inner_append_raw(" ", 1, at);
                at = inner_append_escaped(data, at);
            }
            at = inner_append_raw("?>", 2, at);
            break;
        }
        default:
            break;
        }
    }
    return rb_utf8_str_new(inner_buf, at);
}

/* ---- Adoption-lift predicate (TODO.perf/09, #204 ask 3) ---------
 * The #178/#208 namespace lift + pruning runs on EVERY attach and
 * costs several FFI round-trips even when provably a no-op. This
 * predicate answers in ONE dispatch: false when the node carries
 * no namespace declarations AND its name has no prefix — the
 * common programmatic-build shape (bare names, no namespaces). */
/* ---- Document lifetime in C (TODO.perf/12) ----------------------
 * A TypedData handle holding the C document pointer, referenced
 * only by the binding Document's @doc_handle ivar — its lifetime
 * IS the document's. dfree releases the C document directly: no
 * Ruby finalizer, no FFI dispatch from finalizer context.
 * Document#free releases the pointer first, so dfree no-ops —
 * the same double-free protocol the Freed struct enforces on the
 * Ruby-finalizer path (which stays for LEPTRIS_NO_NATIVE). */
struct doc_handle {
    void *doc;
};

static void dh_free(void *p)
{
    struct doc_handle *h = p;
    if (h->doc) {
        f_doc_free(h->doc);
        h->doc = NULL;
    }
}

static size_t dh_size(const void *p)
{
    (void)p;
    return sizeof(struct doc_handle);
}

static const rb_data_type_t dh_type = {
    "Leptris/XML/DocHandle",
    { 0, dh_free, dh_size, },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE c_doc_handle;
static ID id_iv_doc_handle, id_freed_new, id_alive;

/* Node#dup in one dispatch (TODO.perf/30): engine create +
 * lifetime handle + document wrapper + element_copy + the copy
 * wrapped-and-rooted (memo-seeded). The namespace lift stays a
 * Ruby decision (skip_adoption_lift? — the copy_of seam's
 * semantics, #696/#721/#812). */
static VALUE nf_copy_binding_element(VALUE self, VALUE document,
                                     VALUE addr)
{
    void *doc, *copy;
    VALUE new_doc, doc_addr, handle, freed, root;
    struct doc_handle *h;

    (void)self;
    resolve_binding_classes();
    doc = f_doc_create();
    if (!doc)
        return Qnil;
    doc_addr = ULL2NUM((uint64_t)(uintptr_t)doc);
    new_doc = rb_obj_alloc(c_b_document);
    rb_iv_set(new_doc, "@c_address", doc_addr);
    freed = rb_funcall(c_b_freed, id_freed_new, 1, ID2SYM(id_alive));
    rb_iv_set(new_doc, "@freed", freed);
    rb_iv_set(new_doc, "@readonly", Qfalse);
    rb_iv_set(new_doc, "@version", INT2FIX(0));
    handle = TypedData_Make_Struct(c_doc_handle, struct doc_handle,
                                   &dh_type, h);
    h->doc = doc;
    rb_ivar_set(new_doc, id_iv_doc_handle, handle);

    copy = f_elem_copy((void *)(uintptr_t)NUM2ULL(addr), doc);
    if (!copy) {
        h->doc = NULL; /* the handle releases the empty doc */
        return Qnil;
    }
    root = wrap_addr_node(new_doc, copy);
    rb_ivar_set(new_doc, rb_intern("@root"), root);
    rb_ivar_set(new_doc, rb_intern("@root_version"), INT2FIX(0));
    return new_doc;
}

/* Shared document-wrapper construction from a C document
 * pointer: ivar-seeded wrapper + lifetime handle. Returns the
 * wrapper. (TODO.perf/35 — the create face inlines the same
 * steps.) */
static VALUE build_binding_document(void *doc)
{
    VALUE new_doc, doc_addr, handle, freed;
    struct doc_handle *h;

    doc_addr = ULL2NUM((uint64_t)(uintptr_t)doc);
    new_doc = rb_obj_alloc(c_b_document);
    rb_iv_set(new_doc, "@c_ptr",
              rb_funcall(c_ffi_pointer, id_ptr_new, 1, doc_addr));
    rb_iv_set(new_doc, "@c_address", doc_addr);
    freed = rb_funcall(c_b_freed, id_freed_new, 1, ID2SYM(id_alive));
    rb_iv_set(new_doc, "@freed", freed);
    rb_iv_set(new_doc, "@readonly", Qfalse);
    rb_iv_set(new_doc, "@version", INT2FIX(0));
    handle = TypedData_Make_Struct(c_doc_handle, struct doc_handle,
                                   &dh_type, h);
    h->doc = doc;
    rb_ivar_set(new_doc, id_iv_doc_handle, handle);
    return new_doc;
}

/* check_status in C (TODO.perf/36): the exact status_message
 * format — "base" or "base (detail)" — so the mutation faces
 * raise instead of returning codes for a Ruby dispatch. */
static void check_status_c(int st)
{
    const char *base, *detail;

    if (st == 0)
        return;
    base = f_status_str(st);
    detail = f_last_err();
    if (detail && *detail)
        rb_raise(c_leptris_error, "%s (%s)",
                 base ? base : "?", detail);
    rb_raise(c_leptris_error, "%s", base ? base : "?");
}

/* Document.parse default path in one dispatch (TODO.perf/35):
 * leptris_parse_string + wrapper + handle. Qnil = parse failure
 * (the caller raises with the same message shape). */
static VALUE nf_parse_binding_document(VALUE self, VALUE xml)
{
    void *doc;

    (void)self;
    resolve_binding_classes();
    doc = f_parse_str(RSTRING_PTR(StringValue(xml)),
                      (size_t)RSTRING_LEN(StringValue(xml)), NULL);
    return doc ? build_binding_document(doc) : Qnil;
}

/* Fragment lane (TODO.perf/34): parse the markup against the
 * document; returns the fragment's ADDRESS, or Qfalse when the
 * parse fails (status is not surfaced — the caller re-runs the
 * FFI path for the exact error). */
static VALUE nf_parse_fragment_addr(VALUE self, VALUE document,
                                    VALUE xml)
{
    void *frag;
    int status;

    (void)self;
    resolve_binding_classes();
    frag = f_parse_frag(RSTRING_PTR(StringValue(xml)),
                        (size_t)RSTRING_LEN(StringValue(xml)),
                        doc_ptr_of(document), &status);
    return frag ? ULL2NUM((uint64_t)(uintptr_t)frag) : Qfalse;
}

/* One-shot markup append (TODO.perf/34): parse the markup, walk
 * the fragment's children, append each to the parent — one
 * readonly gate + version bump for the whole batch. Returns the
 * appended count; -1 = parse failure; status codes surface as
 * negatives (-1000 - st) for the caller's check_status path. */
static VALUE nf_append_markup(VALUE self, VALUE document,
                              VALUE parent_addr, VALUE xml)
{
    void *frag, *parent, *child, *next_child;
    int status, count = 0;

    (void)self;
    resolve_binding_classes();
    if (NIL_P(rb_ivar_get(document, id_iv_c_address)))
        rb_raise(c_use_after_free_error,
                 "owning document has been freed");
    if (rb_ivar_get(document, id_iv_readonly) == Qtrue)
        rb_raise(c_readonly_error,
                 "document is readonly — mutation attempted");
    frag = f_parse_frag(RSTRING_PTR(StringValue(xml)),
                        (size_t)RSTRING_LEN(StringValue(xml)),
                        doc_ptr_of(document), &status);
    if (!frag)
        return INT2FIX(-1);
    parent = (void *)(uintptr_t)NUM2ULL(parent_addr);
    rb_ivar_set(document, id_iv_version,
                LONG2FIX(FIX2LONG(rb_ivar_get(document, id_iv_version)) + 1));
    /* Appending DETACHES the child from the fragment — capture
     * the next sibling before each move or the walk corrupts. */
    for (child = f_first_child(frag); child != NULL; child = next_child) {
        next_child = f_next_sibling(child);
        status = f_append_child(parent, child);
        if (status != 0)
            check_status_c(status);
        count++;
    }
    return INT2FIX(count);
}

static VALUE nf_doc_handle_attach(VALUE self, VALUE document)
{
    struct doc_handle *h;
    VALUE handle;

    (void)self;
    handle = TypedData_Make_Struct(c_doc_handle, struct doc_handle,
                                   &dh_type, h);
    h->doc = doc_ptr_of(document);
    rb_ivar_set(document, id_iv_doc_handle, handle);
    return handle;
}

/* Document#free already released the C memory through the FFI
 * seam; detach so the GC-pass dfree no-ops. */
static VALUE nf_doc_handle_release(VALUE self, VALUE document)
{
    VALUE handle = rb_ivar_get(document, id_iv_doc_handle);
    (void)self;
    if (handle != Qnil) {
        struct doc_handle *h;
        TypedData_Get_Struct(handle, struct doc_handle, &dh_type, h);
        h->doc = NULL;
    }
    return Qnil;
}

/* The full Document.create in one dispatch: engine create,
 * binding wrapper (ivar-seeded, bypassing initialize), and the
 * lifetime handle. Returns Qnil when the engine refuses. */
static VALUE nf_create_binding_document(VALUE self)
{
    void *doc;
    VALUE document, addr, handle, freed;
    struct doc_handle *h;

    (void)self;
    resolve_binding_classes();
    doc = f_doc_create();
    if (!doc)
        return Qnil;
    addr = ULL2NUM((uint64_t)(uintptr_t)doc);
    document = rb_obj_alloc(c_b_document);
    rb_iv_set(document, "@c_ptr",
              rb_funcall(c_ffi_pointer, id_ptr_new, 1, addr));
    rb_iv_set(document, "@c_address", addr);
    freed = rb_funcall(c_b_freed, id_freed_new, 1, ID2SYM(id_alive));
    rb_iv_set(document, "@freed", freed);
    rb_iv_set(document, "@readonly", Qfalse);
    rb_iv_set(document, "@version", INT2FIX(0));
    handle = TypedData_Make_Struct(c_doc_handle, struct doc_handle,
                                   &dh_type, h);
    h->doc = doc;
    rb_ivar_set(document, id_iv_doc_handle, handle);
    return document;
}

/* ---- Address-based fast readers (TODO.perf/01) -----------------
 * The DEFAULT binding classes call these when the bundle is
 * loaded: one C-API dispatch + rb_utf8_str_new_cstr — no FFI
 * marshaling. Addresses come from FFI::Pointer#address (a Ruby
 * ivar read on the ffi gem's Pointer). */
static VALUE nf_name(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_elem_name((void *)(uintptr_t)NUM2ULL(addr));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nf_element_text(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_element_text((void *)(uintptr_t)NUM2ULL(addr));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nf_attribute(VALUE self, VALUE addr, VALUE name)
{
    const char *s;
    (void)self;
    s = f_attr((void *)(uintptr_t)NUM2ULL(addr), StringValueCStr(name));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nf_prefix(VALUE self, VALUE addr)
{
    const char *s;
    (void)self;
    s = f_elem_prefix((void *)(uintptr_t)NUM2ULL(addr));
    return (s && *s) ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nn_from(VALUE klass, VALUE document, VALUE element)
{
    /* Element address comes through the binding's #c_ptr address;
     * registered in the shared identity cache so parent/sibling
     * round-trips return the same object. */
    struct native_node *n;
    VALUE node = nn_allocate(klass);
    void *ptr = (void *)(uintptr_t)NUM2ULL(
        rb_funcall(element, id_address, 0));
    TypedData_Get_Struct(node, struct native_node, &nn_type, n);
    n->ptr = ptr;
    n->document = document;
    rb_hash_aset(native_cache_of(document),
                 ULL2NUM((uint64_t)(uintptr_t)ptr), node);
    return node;
}

/* Ruby-side bootstrap: resolve the libleptris symbols once, from
 * the path the FFI layer loaded. */
static VALUE leptris_native_resolve_rb(VALUE self, VALUE lib_path)
{
    (void)self;
    resolve_symbols(StringValueCStr(lib_path));
    return Qnil;
}

void Init_native(void)
{
    VALUE m_leptris, m_xml, m_native;

    m_leptris = rb_define_module("Leptris");
    m_xml = rb_define_module_under(m_leptris, "XML");
    c_native_node = rb_define_class_under(m_xml, "NativeNode", rb_cObject);
    rb_undef_alloc_func(c_native_node);

    id_iv_name = rb_intern("@name");
    id_iv_value = rb_intern("@value");
    id_iv_element = rb_intern("@element");
    id_iv_c_address = rb_intern("@c_address");
    id_iv_native_cache = rb_intern("@native_cache");
    id_iv_binding_cache = rb_intern("@wrapper_cache");
    id_iv_version = rb_intern("@version");
    id_iv_readonly = rb_intern("@readonly");
    id_address = rb_intern("address");
    id_iv_nn_content = rb_intern("@nn_content");
    id_iv_nn_content_ver = rb_intern("@nn_content_ver");
    id_iv_nn_attrs = rb_intern("@nn_attrs");
    id_iv_nn_attrs_ver = rb_intern("@nn_attrs_ver");
    id_child_klasses = rb_intern("@nn_child_klasses");
    id_iv_doc_handle = rb_intern("@doc_handle");
    id_freed_new = rb_intern("new");
    id_alive = rb_intern("alive");
    c_readonly_error = rb_path2class("Leptris::XML::ReadOnlyError");
    c_use_after_free_error =
        rb_path2class("Leptris::XML::UseAfterFreeError");
    rb_gc_register_mark_object(c_readonly_error);
    rb_gc_register_mark_object(c_use_after_free_error);

    rb_define_singleton_method(c_native_node, "from", nn_from, 2);
    rb_define_singleton_method(c_native_node, "install_child_klasses",
                               nn_install_child_klasses, 1);
    rb_define_singleton_method(c_native_node, "create_element", nn_create_element, 2);
    rb_define_singleton_method(c_native_node, "create_text", nn_create_text, 2);
    rb_define_singleton_method(c_native_node, "set_root", nn_set_root, 2);
    rb_define_method(c_native_node, "create_child", nn_create_child, 1);
    rb_define_method(c_native_node, "append_child", nn_append_child, 1);
    rb_define_method(c_native_node, "add_child", nn_append_child, 1);
    rb_define_method(c_native_node, "address", nn_address, 0);
    rb_define_method(c_native_node, "document", nn_document, 0);
    rb_define_method(c_native_node, "attributes", nn_attributes, 0);
    rb_define_method(c_native_node, "line", nn_line, 0);
    rb_define_method(c_native_node, "byte_offset", nn_byte_offset, 0);
    rb_define_method(c_native_node, "name", nn_name, 0);
    rb_define_method(c_native_node, "content", nn_content, 0);
    rb_define_method(c_native_node, "attribute", nn_attribute, 1);
    rb_define_alias(c_native_node, "[]", "attribute");
    /* Unshadowed aliases for consumers whose contract modules shadow
     * attribute/content: a plain call resolves to these at normal
     * method-cache cost instead of UnboundMethod#bind_call. */
    rb_define_alias(c_native_node, "attr_read", "attribute");
    rb_define_alias(c_native_node, "text_read", "content");
    rb_define_method(c_native_node, "children", nn_children, 0);
    rb_define_method(c_native_node, "element_children", nn_element_children, 0);
    rb_define_method(c_native_node, "next_sibling", nn_next_sibling, 0);
    rb_define_method(c_native_node, "parent", nn_parent, 0);
    rb_define_method(c_native_node, "node_type", nn_type_sym, 0);
    rb_define_singleton_method(c_native_node, "resolve!",
                               leptris_native_resolve_rb, 1);

    m_native = rb_define_module_under(m_xml, "Native");
    m_native_sentinel = m_native;
    rb_define_module_function(m_native, "fast_name", nf_name, 1);
    rb_define_module_function(m_native, "fast_element_text", nf_element_text, 1);
    rb_define_module_function(m_native, "fast_attribute", nf_attribute, 2);
    rb_define_module_function(m_native, "fast_prefix", nf_prefix, 1);
    rb_define_module_function(m_native, "fast_attribute2", nf_fast_attribute2, 2);
    rb_define_module_function(m_native, "ns_lift_needed?", nf_ns_lift_needed, 1);
    rb_define_module_function(m_native, "append_binding_child",
                              nf_append_binding_child, 3);
    rb_define_module_function(m_native, "set_binding_attribute",
                              nf_set_binding_attribute, 4);
    rb_define_module_function(m_native, "insert_binding_child",
                              nf_insert_binding_child, 4);
    rb_define_module_function(m_native, "at_xpath_first",
                              nf_at_xpath_first, 2);
    rb_define_module_function(m_native, "materialize_xpath",
                              nf_materialize_xpath, 2);
    rb_define_module_function(m_native, "set_binding_name",
                              nf_set_binding_name, 3);
    rb_define_module_function(m_native, "set_binding_text",
                              nf_set_binding_text, 3);
    rb_define_module_function(m_native, "unlink_binding_node",
                              nf_unlink_binding_node, 2);
    rb_define_module_function(m_native, "traverse_binding",
                              nf_traverse_binding, 2);
    rb_define_module_function(m_native, "visit_binding",
                              nf_visit_binding, 2);
    rb_define_module_function(m_native, "fast_text_content",
                              nf_fast_text_content, 1);
    rb_define_module_function(m_native, "fast_comment_content",
                              nf_fast_comment_content, 1);
    rb_define_module_function(m_native, "fast_cdata_content",
                              nf_fast_cdata_content, 1);
    rb_define_module_function(m_native, "fast_pi_target",
                              nf_fast_pi_target, 1);
    rb_define_module_function(m_native, "fast_pi_data",
                              nf_fast_pi_data, 1);
    rb_define_module_function(m_native, "fast_path",
                              nf_fast_path, 1);
    rb_define_module_function(m_native, "first_element_child",
                              nf_first_element_child, 2);
    rb_define_module_function(m_native, "last_element_child",
                              nf_last_element_child, 2);
    rb_define_module_function(m_native, "copy_binding_element",
                              nf_copy_binding_element, 2);
    rb_define_module_function(m_native, "set_binding_root",
                              nf_set_binding_root, 2);
    rb_define_module_function(m_native, "parse_binding_document",
                              nf_parse_binding_document, 1);
    rb_define_module_function(m_native, "parse_fragment_addr",
                              nf_parse_fragment_addr, 2);
    rb_define_module_function(m_native, "append_markup",
                              nf_append_markup, 3);
    rb_define_module_function(m_native, "fast_inner_xml",
                              nf_fast_inner_xml, 1);
    rb_define_module_function(m_native, "snapshot_subtree",
                              nf_snapshot_subtree, 2);
    rb_define_module_function(m_native, "snapshot_rows",
                              nf_snapshot_rows, 2);
    rb_define_module_function(m_native, "doc_handle_attach",
                              nf_doc_handle_attach, 1);
    rb_define_module_function(m_native, "doc_handle_release",
                              nf_doc_handle_release, 1);
    rb_define_module_function(m_native, "create_binding_document",
                              nf_create_binding_document, 0);
    c_doc_handle = rb_define_class_under(m_xml, "DocHandle", rb_cObject);
    rb_undef_alloc_func(c_doc_handle);
    rb_define_module_function(m_native, "bulk_attributes", nf_bulk_attributes, 1);
    rb_define_module_function(m_native, "bulk_attr_faces",
                              nf_bulk_attr_faces, 2);
    rb_define_module_function(m_native, "create_binding_element",
                              nf_create_binding_element, 2);
    rb_define_module_function(m_native, "create_binding_text",
                              nf_create_binding_text, 2);
    rb_define_module_function(m_native, "bulk_children", nf_bulk_children, 2);
    rb_define_module_function(m_native, "bulk_element_children",
                              nf_bulk_element_children, 2);
    rb_define_module_function(m_native, "bulk_xpath", nf_bulk_xpath, 2);
    rb_define_module_function(m_native, "fast_document_xml",
                              nf_fast_document_xml, 4);
    rb_define_module_function(m_native, "fast_element_xml",
                              nf_fast_element_xml, 4);
}

#ifdef _WIN32
/* MRI derives a C extension's init symbol from the require
 * feature's basename cut at the first dot. The Windows per-minor
 * DLLs are therefore named dot-free (native_3_3.so etc.), and
 * each needs its exact init name exported. All are defined here
 * unconditionally: a DLL only ever loads under the Ruby minor it
 * was built against (PE binds its build Ruby's runtime DLL). */
void Init_native_3_3(void) { Init_native(); }
void Init_native_3_4(void) { Init_native(); }
void Init_native_4_0(void) { Init_native(); }
#endif
