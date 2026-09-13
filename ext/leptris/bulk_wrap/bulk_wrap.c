/* BulkWrap prototype (#185): construct binding Node wrappers for a
 * node's whole child list in one C pass — symbol resolution via
 * dlsym(RTLD_DEFAULT) on the library FFI already loaded (no link
 * dependency). Class dispatch, ivar assignment, identity-cache
 * check/store in C; the per-node Ruby frames (wrap/construct/
 * ensure_alive) disappear. */
#include <ruby.h>
#include <dlfcn.h>
#include <stdint.h>

typedef int (*children_ex_fn)(void *, void **, int *, int);

static children_ex_fn children_ex;

static VALUE c_element, c_text, c_result_text, c_result_attr,
             c_comment, c_cdata, c_pi, c_node, c_ffi_pointer;
static ID id_new, id_wrapper_cache;

#define KIND_ELEMENT 0
#define KIND_TEXT 1
#define KIND_COMMENT 2
#define KIND_CDATA 3
#define KIND_PI 4
#define KIND_SYNTHETIC_TEXT 8
#define KIND_ATTRIBUTE 6

static VALUE klass_for_kind(int kind)
{
    switch (kind) {
    case KIND_ELEMENT: return c_element;
    case KIND_TEXT: return c_text;
    case KIND_COMMENT: return c_comment;
    case KIND_CDATA: return c_cdata;
    case KIND_PI: return c_pi;
    default: return c_node;
    }
}

static VALUE bulk_children(VALUE self, VALUE document, VALUE parent,
                           VALUE c_ptr_addr, VALUE lib_path)
{
    void *parent_ptr = (void *)(uintptr_t)NUM2ULL(c_ptr_addr);
    void *buf[256];
    int kinds[256];
    int n, i;
    VALUE cache, out;

    (void)self;
    if (!children_ex) {
        void *handle = dlopen(StringValueCStr(lib_path), RTLD_NOW);
        if (!handle)
            rb_raise(rb_eRuntimeError, "dlopen %s: %s",
                     StringValueCStr(lib_path), dlerror());
        children_ex = (children_ex_fn)dlsym(handle,
                                            "leptris_node_children_ex");
        if (!children_ex)
            rb_raise(rb_eRuntimeError,
                     "leptris_node_children_ex not found in %s",
                     StringValueCStr(lib_path));
    }

    n = children_ex(parent_ptr, buf, kinds, 256);
    if (n <= 0)
        return rb_ary_new2(0);

    cache = rb_funcall(document, id_wrapper_cache, 0);
    out = rb_ary_new2(n);
    for (i = 0; i < n; i++) {
        uintptr_t addr = (uintptr_t)buf[i];
        VALUE key = ULL2NUM((uint64_t)addr);
        VALUE node = rb_hash_aref(cache, key);
        if (NIL_P(node)) {
            VALUE ptr = rb_funcall(c_ffi_pointer, id_new, 1, key);
            node = rb_obj_alloc(klass_for_kind(kinds[i]));
            rb_iv_set(node, "@c_ptr", ptr);
            rb_iv_set(node, "@document", document);
            rb_iv_set(node, "@parent", parent);
            rb_iv_set(node, "@node_type", INT2FIX(kinds[i]));
            rb_hash_aset(cache, key, node);
        }
        rb_ary_push(out, node);
    }
    return out;
}

void Init_bulk_wrap(void)
{
    VALUE m_leptris, m_xml, c_bulk;

    m_leptris = rb_define_module("Leptris");
    m_xml = rb_define_module_under(m_leptris, "XML");
    c_bulk = rb_define_class_under(m_xml, "BulkWrap", rb_cObject);

    c_element = rb_path2class("Leptris::XML::Element");
    c_text = rb_path2class("Leptris::XML::Text");
    c_result_text = rb_path2class("Leptris::XML::ResultText");
    c_result_attr = rb_path2class("Leptris::XML::ResultAttr");
    c_comment = rb_path2class("Leptris::XML::Comment");
    c_cdata = rb_path2class("Leptris::XML::CDATA");
    c_pi = rb_path2class("Leptris::XML::ProcessingInstruction");
    c_node = rb_path2class("Leptris::XML::Node");
    c_ffi_pointer = rb_path2class("FFI::Pointer");

    id_new = rb_intern("new");
    id_wrapper_cache = rb_intern("wrapper_cache");

    rb_define_singleton_method(c_bulk, "children",
                               bulk_children, 4);
    (void)c_result_text; (void)c_result_attr;
}
