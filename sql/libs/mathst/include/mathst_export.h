// Author: 
//
// Purpose:

#ifndef FORGE_mathst_EXPORT_H
#define FORGE_mathst_EXPORT_H

#if !defined(FORGE_mathst_SHARED)
#define FORGE_mathst_API
#elif defined(_WIN32)
#if defined(mathst_EXPORTS)
#define FORGE_mathst_API __declspec(dllexport)
#else
#define FORGE_mathst_API __declspec(dllimport)
#endif
#elif defined(__GNUC__) || defined(__clang__)
#define FORGE_mathst_API __attribute__((visibility("default")))
#else
#define FORGE_mathst_API
#endif

#endif
