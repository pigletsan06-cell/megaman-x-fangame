#ifndef X4_ASSERT_H
#define X4_ASSERT_H
void __assert_fail(const char*, const char*, unsigned, const char*);
#define assert(e) ((e) ? (void)0 : __assert_fail(#e, __FILE__, __LINE__, __func__))
#endif
