// Author:
//
// Purpose:

#include "math.hpp"

namespace sql {

math::math() = default;
math::math(const math &) = default;
math::math(math &&) noexcept = default;
math &math::operator=(const math &) = default;
math &math::operator=(math &&) noexcept = default;
math::~math() = default;
int math::sum(int a, int b) { return a + b; }
} // namespace sql
