/* Project-wide types. One pair for the whole project: one set of bound lemmas then
   works everywhere, and mixed int/size_t/unsigned stops exploding into downcast goals.
   Change the two typedefs to match your project; keep the *_MAX macros in step. */

#ifndef TYPEDEFS_H_INCLUDED
#define TYPEDEFS_H_INCLUDED

#include <limits.h>

typedef int value_type;
#define VALUE_TYPE_MAX INT_MAX
#define VALUE_TYPE_MIN INT_MIN

typedef unsigned int size_type;
#define SIZE_TYPE_MAX UINT_MAX

#endif /* TYPEDEFS_H_INCLUDED */
