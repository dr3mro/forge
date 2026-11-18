// Author: 
//
// Purpose:

#ifndef FORGE_math_EXPORT_H
#define FORGE_math_EXPORT_H

#if !defined(FORGE_math_SHARED)
#define FORGE_math_API
#elif defined(_WIN32)
#if defined(math_EXPORTS)
#define FORGE_math_API __declspec(dllexport)
#else
#define FORGE_math_API __declspec(dllimport)
#endif
#elif defined(__GNUC__) || defined(__clang__)
#define FORGE_math_API __attribute__((visibility("default")))
#else
#define FORGE_math_API
#endif

#endif
