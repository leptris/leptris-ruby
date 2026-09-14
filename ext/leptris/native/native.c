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
typedef int (*children_ex_fn)(void *, void **, int *, int);
typedef int (*node_type_fn)(void *);
typedef void *(*next_sibling_fn)(void *);
typedef void *(*parent_fn)(void *);
typedef const char *(*element_text_fn)(void *);

static elem_name_fn f_elem_name;
static text_content_fn f_text_content;
static attr_fn f_attr;
static children_ex_fn f_children_ex;
static node_type_fn f_node_type;
static next_sibling_fn f_next_sibling;
static parent_fn f_parent;
static element_text_fn f_element_text;

static VALUE c_native_node;
static ID id_wrapper_cache;

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
    f_element_text = (element_text_fn)lib_sym(h, "leptris_element_text");
    if (!f_elem_name || !f_text_content || !f_attr ||
        !f_children_ex || !f_node_type || !f_next_sibling || !f_parent ||
        !f_element_text)
        rb_raise(rb_eRuntimeError, "libleptris symbols missing");
}

static VALUE nn_name(VALUE self)
{
    struct native_node *n;
    const char *s;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    s = f_elem_name(n->ptr);
    return s ? rb_str_new_cstr(s) : Qnil;
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
    return s ? rb_str_new_cstr(s) : Qnil;
}

static VALUE nn_attribute(VALUE self, VALUE name)
{
    struct native_node *n;
    const char *s;
    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    s = f_attr(n->ptr, StringValueCStr(name));
    return s ? rb_str_new_cstr(s) : Qnil;
}

static VALUE nn_allocate(VALUE klass)
{
    struct native_node *n;
    return TypedData_Make_Struct(klass, struct native_node, &nn_type, n);
}

/* Bulk children: one native pass; cache check/store inline; the
 * document's wrapper_cache (a Ruby Hash keyed by address) provides
 * identity for nodes seen through other paths. */
static VALUE nn_children(VALUE self)
{
    struct native_node *n;
    void *buf[512];
    int kinds[512];
    int count, i;
    VALUE cache, out;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    count = f_children_ex(n->ptr, buf, kinds, 512);
    if (count <= 0)
        return rb_ary_new2(0);

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
    void *buf[512];
    int kinds[512];
    int count, i;
    VALUE cache, out;

    TypedData_Get_Struct(self, struct native_node, &nn_type, n);
    count = f_children_ex(n->ptr, buf, kinds, 512);
    if (count <= 0)
        return rb_ary_new2(0);

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
    VALUE m_leptris, m_xml;

    m_leptris = rb_define_module("Leptris");
    m_xml = rb_define_module_under(m_leptris, "XML");
    c_native_node = rb_define_class_under(m_xml, "NativeNode", rb_cObject);
    rb_undef_alloc_func(c_native_node);

    id_wrapper_cache = rb_intern("wrapper_cache");

    rb_define_singleton_method(c_native_node, "from", nn_from, 2);
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
}
