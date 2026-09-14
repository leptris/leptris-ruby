/* Native TypedData node prototype (#185/#147/#187 converged):
 * wrapper objects with the C pointer embedded (no FFI::Pointer per
 * node), hot reads (name/content/attribute) called directly in C
 * via dlsym on the FFI-loaded library, and children constructed in
 * bulk — one cache round-trip, zero Ruby frames, zero FFI
 * marshaling per node. */
#include <ruby.h>
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

typedef const char *(*elem_name_fn)(void *);
typedef const char *(*text_content_fn)(void *);
typedef const char *(*attr_fn)(void *, const char *);
typedef int (*children_ex_fn)(void *, void **, int *, int);
typedef int (*node_type_fn)(void *);

static elem_name_fn f_elem_name;
static text_content_fn f_text_content;
static attr_fn f_attr;
static children_ex_fn f_children_ex;
static node_type_fn f_node_type;

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

static void resolve_symbols(const char *lib_path)
{
    void *h = dlopen(lib_path, RTLD_NOW);
    if (!h)
        rb_raise(rb_eRuntimeError, "dlopen %s: %s", lib_path, dlerror());
    f_elem_name = (elem_name_fn)dlsym(h, "leptris_element_name");
    f_text_content = (text_content_fn)dlsym(h, "leptris_text_node_get_content");
    f_attr = (attr_fn)dlsym(h, "leptris_element_attribute");
    f_children_ex = (children_ex_fn)dlsym(h, "leptris_node_children_ex");
    f_node_type = (node_type_fn)dlsym(h, "leptris_node_get_type");
    if (!f_elem_name || !f_text_content || !f_attr ||
        !f_children_ex || !f_node_type)
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
    s = f_text_content(n->ptr);
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

static VALUE nn_from(VALUE klass, VALUE document, VALUE element)
{
    /* Element address comes through the binding's #c_ptr address */
    struct native_node *n;
    VALUE node = nn_allocate(klass);
    TypedData_Get_Struct(node, struct native_node, &nn_type, n);
    n->ptr = (void *)(uintptr_t)NUM2ULL(rb_funcall(element, rb_intern("address"), 0));
    n->document = document;
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
    rb_define_singleton_method(c_native_node, "resolve!",
                               leptris_native_resolve_rb, 1);
}
