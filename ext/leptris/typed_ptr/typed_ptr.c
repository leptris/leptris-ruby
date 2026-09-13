/* TypedPtr — the typed-wrapper variant's node handle
 * (TODO.restructure/21, issue #147 option B).
 *
 * Embeds the C node address and the owning document VALUE in one
 * RVALUE instead of a dedicated 88 B FFI::Pointer per node — the
 * mark function holds the document alive, #to_ptr marshals into
 * FFI :pointer parameters (a transient FFI::Pointer per call: no
 * per-node retained pointer).
 */
#include <ruby.h>
#include <stdint.h>

struct typed_ptr {
    uintptr_t addr;
    VALUE document;
};

static void tp_mark(void *p)
{
    struct typed_ptr *s = (struct typed_ptr *)p;
    if (s->document != Qnil)
        rb_gc_mark(s->document);
}

static size_t tp_size(const void *p)
{
    (void)p;
    return sizeof(struct typed_ptr);
}

static const rb_data_type_t tp_type = {
    "Leptris/XML/TypedPtr",
    { tp_mark, RUBY_TYPED_DEFAULT_FREE, tp_size, },
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE tp_create(VALUE self, VALUE address, VALUE document)
{
    struct typed_ptr *s;
    VALUE obj;

    if (!rb_obj_is_kind_of(document, rb_cObject))
        rb_raise(rb_eTypeError, "document must be an Object or nil");

    obj = TypedData_Make_Struct(self, struct typed_ptr, &tp_type, s);
    s->addr = (uintptr_t)NUM2ULL(address);
    s->document = document;
    return obj;
}

static VALUE tp_address(VALUE self)
{
    struct typed_ptr *s;

    TypedData_Get_Struct(self, struct typed_ptr, &tp_type, s);
    return ULL2NUM((uint64_t)s->addr);
}

static VALUE tp_document(VALUE self)
{
    struct typed_ptr *s;

    TypedData_Get_Struct(self, struct typed_ptr, &tp_type, s);
    return s->document;
}

/* FFI marshals :pointer parameters through #to_ptr; a fresh
 * FFI::Pointer per call stays transient (never retained on the
 * node), keeping the held-documents win. */
static VALUE tp_to_ptr(VALUE self)
{
    VALUE klass, addr;

    klass = rb_path2class("FFI::Pointer");
    addr = tp_address(self);
    return rb_funcall(klass, rb_intern("new"), 1, addr);
}

static VALUE tp_eq(VALUE self, VALUE other)
{
    struct typed_ptr *a, *b;

    if (!rb_obj_is_kind_of(other, CLASS_OF(self)))
        return Qfalse;
    TypedData_Get_Struct(self, struct typed_ptr, &tp_type, a);
    TypedData_Get_Struct(other, struct typed_ptr, &tp_type, b);
    return a->addr == b->addr ? Qtrue : Qfalse;
}

static VALUE tp_null_p(VALUE self)
{
    struct typed_ptr *s;

    TypedData_Get_Struct(self, struct typed_ptr, &tp_type, s);
    return s->addr == 0 ? Qtrue : Qfalse;
}

static VALUE tp_inspect(VALUE self)
{
    struct typed_ptr *s;

    TypedData_Get_Struct(self, struct typed_ptr, &tp_type, s);
    return rb_sprintf("#<%" PRIsVALUE " address=0x%llx>",
                      rb_obj_class(self),
                      (unsigned long long)s->addr);
}

void Init_typed_ptr(void)
{
    VALUE m_leptris, m_xml, c_typed;

    m_leptris = rb_define_module("Leptris");
    m_xml = rb_define_module_under(m_leptris, "XML");
    c_typed = rb_define_class_under(m_xml, "TypedPtr", rb_cObject);
    rb_undef_alloc_func(c_typed); /* created only through .create */

    rb_define_singleton_method(c_typed, "create", tp_create, 2);
    rb_define_method(c_typed, "address", tp_address, 0);
    rb_define_method(c_typed, "document", tp_document, 0);
    rb_define_method(c_typed, "to_ptr", tp_to_ptr, 0);
    rb_define_method(c_typed, "==", tp_eq, 1);
    rb_define_method(c_typed, "null?", tp_null_p, 0);
    rb_define_method(c_typed, "inspect", tp_inspect, 0);
}
