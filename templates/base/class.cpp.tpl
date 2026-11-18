#include "{{NAME}}.hpp"

namespace {{NAMESPACE}} {

{{NAME}}::{{NAME}}() = default;
{{NAME}}::{{NAME}}(const {{NAME}} &) = default;
{{NAME}}::{{NAME}}({{NAME}} &&) noexcept = default;
{{NAME}} &{{NAME}}::operator=(const {{NAME}} &) = default;
{{NAME}} &{{NAME}}::operator=({{NAME}} &&) noexcept = default;
{{NAME}}::~{{NAME}}() = default;

} // namespace {{NAMESPACE}}
