// Author:
//
// Purpose:

#pragma once

#include "math_export.h"

namespace sql {

class FORGE_math_API math {
public:
  math();
  math(const math &);
  math(math &&) noexcept;
  math &operator=(const math &);
  math &operator=(math &&) noexcept;
  virtual ~math();
  int sum(int a, int b);

protected:
private:
};

} // namespace sql
