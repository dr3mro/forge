#ifndef FORGE_{{NAME}}_EXPORT_H
#define FORGE_{{NAME}}_EXPORT_H

#if !defined(FORGE_{{NAME}}_SHARED)
#define FORGE_{{NAME}}_API
#elif defined(_WIN32)
#if defined({{NAME}}_EXPORTS)
#define FORGE_{{NAME}}_API __declspec(dllexport)
#else
#define FORGE_{{NAME}}_API __declspec(dllimport)
#endif
#elif defined(__GNUC__) || defined(__clang__)
#define FORGE_{{NAME}}_API __attribute__((visibility("default")))
#else
#define FORGE_{{NAME}}_API
#endif

#endif
