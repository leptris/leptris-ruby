/* Native TypedData node prototype (#185/#147/#187 converged):
 * wrapper objects with the C pointer embedded (no FFI::Pointer per
 * node), hot reads (name/content/attribute) called directly in C
 * via dlsym on the FFI-loaded library, and children constructed in
 * bulk — one cache round-trip, zero Ruby frames, zero FFI
 * marshaling per node. */
#include <ruby.h>
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
typedef size_t (*xp_count_fn)(void *);
typedef size_t (*xp_nodes_ex_fn)(void *, void **, int *, size_t);
typedef int (*xp_node_kind_fn)(void *, int);
typedef const char *(*xp_node_name_fn)(void *, int);
typedef const char *(*xp_node_value_fn)(void *, int);
typedef size_t (*serialize_into_fn)(void *, char *, size_t, void *, void *);
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
static xp_count_fn f_xp_count;
static xp_nodes_ex_fn f_xp_nodes_ex;
static xp_node_kind_fn f_xp_node_kind;
static xp_node_name_fn f_xp_node_name;
static xp_node_value_fn f_xp_node_value;
static serialize_into_fn f_doc_serialize, f_elem_serialize;
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
static set_root_fn f_set_root;
static doc_free_fn f_doc_free;

static VALUE c_native_node;
static ID id_wrapper_cache;   /* native_cache: NativeNode identity */
static ID id_binding_cache;   /* wrapper_cache: binding Node identity */

#define NT_ELEMENT 0

struct native_node {
    void *ptr;
    VALUE document;
};

static void nn_mark(void *p)
{
    struct native_node *n = p;
    if (n->document != Qnil)
        rb_gc_mark(n->document);
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
    f_set_root = (set_root_fn)lib_sym(h, "leptris_document_set_root");
    f_doc_free = (doc_free_fn)lib_sym(h, "leptris_document_free");
    if (!f_elem_name || !f_text_content || !f_attr ||
        !f_children_ex || !f_node_type || !f_next_sibling || !f_parent ||
        !f_element_text || !f_doc_create || !f_elem_create || !f_text_create ||
        !f_create_child || !f_append_child || !f_set_root || !f_doc_free ||
        !f_elem_prefix || !f_xp_count || !f_xp_nodes_ex ||
        !f_xp_node_kind || !f_xp_node_name || !f_xp_node_value ||
        !f_doc_serialize || !f_elem_serialize || !f_attr_first ||
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
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nn_content(VALUE self)
{
    struct native_node *n;
    const char *s;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    /* elements aggregate their text (leptris_element_text); text
     * nodes carry it directly. */
    s = f_node_type(n->ptr) == 0 ? f_element_text(n->ptr)
                                 : f_text_content(n->ptr);
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nn_attribute(VALUE self, VALUE name)
{
    struct native_node *n;
    const char *s;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    s = f_attr(n->ptr, StringValueCStr(name));
    return s ? rb_utf8_str_new_cstr(s) : Qnil;
}

static VALUE nn_allocate(VALUE klass)
{
    struct native_node *n;
    return TypedData_Make_Struct(klass, struct native_node, &nn_type, n);
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
    VALUE cache, out;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    count = fetch_children_two_call(n->ptr, &buf, &kinds);
    if (count <= 0) {
        ruby_xfree(buf);
        ruby_xfree(kinds);
        return rb_ary_new2(0);
    }

    cache = rb_funcall(n->document, id_wrapper_cache, 0);
    out = rb_ary_new2(count);
    for (i = 0; i < count; i++) {
        uint64_t addr = (uint64_t)(uintptr_t)buf[i];
        VALUE key = ULL2NUM(addr);
        VALUE child = rb_hash_aref(cache, key);
        if (NIL_P(child)) {
            struct native_node *cn;
            child = nn_allocate(c_native_node);
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
    VALUE cache, out;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    count = fetch_children_two_call(n->ptr, &buf, &kinds);
    if (count <= 0) {
        ruby_xfree(buf);
        ruby_xfree(kinds);
        return rb_ary_new2(0);
    }

    cache = rb_funcall(n->document, id_wrapper_cache, 0);
    out = rb_ary_new();
    for (i = 0; i < count; i++) {
        if (kinds[i] != NT_ELEMENT)
            continue;
        VALUE key = ULL2NUM((uint64_t)(uintptr_t)buf[i]);
        VALUE child = rb_hash_aref(cache, key);
        if (NIL_P(child)) {
            struct native_node *cn;
            child = nn_allocate(c_native_node);
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

static VALUE wrap_cached(struct native_node *owner, void *ptr)
{
    VALUE cache, key, node;
    struct native_node *n;

    cache = rb_funcall(owner->document, id_wrapper_cache, 0);
    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    node = rb_hash_aref(cache, key);
    if (!NIL_P(node))
        return node;
    node = nn_allocate(c_native_node);
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
    return sib ? wrap_cached(n, sib) : Qnil;
}

static VALUE nn_parent(VALUE self)
{
    struct native_node *n;
    void *par;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    par = f_parent(n->ptr);
    return par ? wrap_cached(n, par) : Qnil;
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
    cache = rb_funcall(document, id_wrapper_cache, 0);
    key = ULL2NUM((uint64_t)(uintptr_t)ptr);
    rb_hash_aset(cache, key, node);
    return node;
}

/* Document address from the binding Document's #c_ptr. */
static void *doc_ptr_of(VALUE document)
{
    VALUE c_ptr = rb_funcall(document, rb_intern("c_ptr"), 0);
    if (NIL_P(c_ptr))
        rb_raise(rb_eRuntimeError, "document has been freed");
    return (void *)(uintptr_t)NUM2ULL(rb_funcall(c_ptr, rb_intern("address"), 0));
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
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    ptr = f_create_child(n->ptr, StringValueCStr(name));
    if (!ptr)
        rb_raise(rb_eRuntimeError, "leptris_element_create_child failed");
    return wrap_new(n->document, ptr);
}

static VALUE nn_append_child(VALUE self, VALUE child)
{
    struct native_node *n, *c;
    int rc;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    TypedData_Get_Struct(child, struct native_node, &nn_type, c);
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
             c_b_pi, c_b_node, c_b_result_text, c_b_result_attr,
             c_ffi_pointer;
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
    c_b_node = rb_path2class("Leptris::XML::Node");
    c_b_result_text = rb_path2class("Leptris::XML::ResultText");
    c_b_result_attr = rb_path2class("Leptris::XML::ResultAttr");
    c_ffi_pointer = rb_path2class("FFI::Pointer");
    id_ptr_new = rb_intern("new");
    rb_gc_register_mark_object(c_b_element);
    rb_gc_register_mark_object(c_b_text);
    rb_gc_register_mark_object(c_b_comment);
    rb_gc_register_mark_object(c_b_cdata);
    rb_gc_register_mark_object(c_b_pi);
    rb_gc_register_mark_object(c_b_node);
    rb_gc_register_mark_object(c_b_result_text);
    rb_gc_register_mark_object(c_b_result_attr);
    rb_gc_register_mark_object(c_ffi_pointer);
}

static VALUE binding_klass_for(int kind)
{
    switch (kind) {
    case 0: return c_b_element;
    case 1: return c_b_text;
    case 2: return c_b_comment;
    case 3: return c_b_cdata;
    case 4: return c_b_pi;
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

    cache = rb_funcall(document, id_binding_cache, 0);
    out = rb_ary_new2(elements_only ? 8 : count);
    for (i = 0; i < count; i++) {
        VALUE key, node;
        if (elements_only && kinds[i] != 0)
            continue;
        key = ULL2NUM((uint64_t)(uintptr_t)buf[i]);
        node = rb_hash_aref(cache, key);
        if (NIL_P(node)) {
            VALUE ptr = rb_funcall(c_ffi_pointer, id_ptr_new, 1, key);
            node = rb_obj_alloc(binding_klass_for(kinds[i]));
            rb_iv_set(node, "@c_ptr", ptr);
            rb_iv_set(node, "@document", document);
            rb_iv_set(node, "@parent", Qnil);
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

static VALUE nf_bulk_xpath(VALUE self, VALUE document, VALUE result_ptr_val)
{
    void *result = (void *)(uintptr_t)NUM2ULL(result_ptr_val);
    void **buf;
    int *kinds;
    int count, i;
    VALUE cache, out;

    (void)self;
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
    cache = rb_funcall(document, id_binding_cache, 0);
    out = rb_ary_new2(count);
    for (i = 0; i < count; i++) {
        VALUE node, key;
        const char *s;
        if (buf[i] == NULL)
            continue;
        key = ULL2NUM((uint64_t)(uintptr_t)buf[i]);
        switch (kinds[i]) {
        case 0: /* element */
            node = rb_hash_aref(cache, key);
            if (NIL_P(node)) {
                VALUE ptr = rb_funcall(c_ffi_pointer, id_ptr_new, 1, key);
                node = rb_obj_alloc(c_b_element);
                rb_iv_set(node, "@c_ptr", ptr);
                rb_iv_set(node, "@document", document);
                rb_iv_set(node, "@parent", Qnil);
                rb_iv_set(node, "@node_type", INT2FIX(0));
                rb_hash_aset(cache, key, node);
            }
            break;
        case 1: /* synthetic attribute */
            {
                const char *name = f_xp_node_name(result, i);
                const char *value = f_xp_node_value(result, i);
                VALUE ptr = rb_funcall(c_ffi_pointer, id_ptr_new, 1, key);
                node = rb_obj_alloc(c_b_result_attr);
                rb_iv_set(node, "@c_ptr", ptr);
                rb_iv_set(node, "@document", document);
                rb_iv_set(node, "@attr_name",
                          name ? rb_utf8_str_new_cstr(name) : Qnil);
                rb_iv_set(node, "@attr_value",
                          value ? rb_utf8_str_new_cstr(value) : Qnil);
            }
            break;
        case 2: /* text-kind: synthetic sequence carrier, or a real
                 * Text/CDATA node (XPath reports both as TEXT) —
                 * dispatch on the node's own type like Node.wrap. */
            {
                int nt = f_node_type(buf[i]);
                if (nt == 8) { /* NODE_SYNTHETIC_TEXT */
                    s = f_xp_node_value(result, i);
                    node = rb_obj_alloc(c_b_result_text);
                    rb_iv_set(node, "@c_ptr",
                              rb_funcall(c_ffi_pointer, id_ptr_new, 1, key));
                    rb_iv_set(node, "@document", document);
                    rb_iv_set(node, "@value",
                              s ? rb_utf8_str_new_cstr(s) : Qnil);
                } else {
                    VALUE ptr = rb_funcall(c_ffi_pointer, id_ptr_new, 1, key);
                    node = rb_hash_aref(cache, key);
                    if (NIL_P(node)) {
                        node = rb_obj_alloc(binding_klass_for(nt));
                        rb_iv_set(node, "@c_ptr", ptr);
                        rb_iv_set(node, "@document", document);
                        rb_iv_set(node, "@parent", Qnil);
                        rb_iv_set(node, "@node_type", INT2FIX(nt));
                        rb_hash_aset(cache, key, node);
                    }
                }
            }
            break;
        default: /* other: rare — signal Ruby fallback for this index */
            rb_ary_push(out, m_native_sentinel);
            continue;
        }
        rb_ary_push(out, node);
    }
    ruby_xfree(buf);
    ruby_xfree(kinds);
    return out;
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
                            int indent, int xml_declaration)
{
    struct serialize_opts opts;
    char stack_buf[4096];
    size_t needed;

    char *probe;
    size_t probe_cap;

    opts.indent = indent;
    opts.xml_declaration = xml_declaration;
    opts.encoding = NULL;
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
                                  VALUE indent, VALUE decl)
{
    (void)self;
    return fast_serialize(f_doc_serialize,
                          (void *)(uintptr_t)NUM2ULL(addr),
                          NUM2INT(indent), RTEST(decl) ? 1 : 0);
}

static VALUE nf_fast_element_xml(VALUE self, VALUE addr,
                                 VALUE indent, VALUE decl)
{
    (void)self;
    return fast_serialize(f_elem_serialize,
                          (void *)(uintptr_t)NUM2ULL(addr),
                          NUM2INT(indent), RTEST(decl) ? 1 : 0);
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
        rb_funcall(element, rb_intern("address"), 0));
    TypedData_Get_Struct(node, struct native_node, &nn_type, n);
    n->ptr = ptr;
    n->document = document;
    rb_hash_aset(rb_funcall(document, id_wrapper_cache, 0),
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

    id_wrapper_cache = rb_intern("native_cache");
    id_binding_cache = rb_intern("wrapper_cache");

    rb_define_singleton_method(c_native_node, "from", nn_from, 2);
    rb_define_singleton_method(c_native_node, "create_element", nn_create_element, 2);
    rb_define_singleton_method(c_native_node, "create_text", nn_create_text, 2);
    rb_define_singleton_method(c_native_node, "set_root", nn_set_root, 2);
    rb_define_method(c_native_node, "create_child", nn_create_child, 1);
    rb_define_method(c_native_node, "append_child", nn_append_child, 1);
    rb_define_method(c_native_node, "add_child", nn_append_child, 1);
    rb_define_method(c_native_node, "address", nn_address, 0);
    rb_define_method(c_native_node, "attributes", nn_attributes, 0);
    rb_define_method(c_native_node, "line", nn_line, 0);
    rb_define_method(c_native_node, "byte_offset", nn_byte_offset, 0);
    rb_define_method(c_native_node, "name", nn_name, 0);
    rb_define_method(c_native_node, "content", nn_content, 0);
    rb_define_method(c_native_node, "attribute", nn_attribute, 1);
    rb_define_alias(c_native_node, "[]", "attribute");
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
    rb_define_module_function(m_native, "bulk_children", nf_bulk_children, 2);
    rb_define_module_function(m_native, "bulk_element_children",
                              nf_bulk_element_children, 2);
    rb_define_module_function(m_native, "bulk_xpath", nf_bulk_xpath, 2);
    rb_define_module_function(m_native, "fast_document_xml",
                              nf_fast_document_xml, 3);
    rb_define_module_function(m_native, "fast_element_xml",
                              nf_fast_element_xml, 3);
}
