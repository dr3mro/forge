#pragma once

#include "{{NAME}}_export.h"

namespace {{NAMESPACE}} {

class FORGE_{{NAME}}_API {{NAME}} {
 public:
  {{NAME}}();
  {{NAME}}(const {{NAME}}&);
  {{NAME}}({{NAME}}&&) noexcept;
  {{NAME}}& operator=(const {{NAME}}&);
  {{NAME}}& operator=({{NAME}}&&) noexcept;
  virtual ~{{NAME}}();

 protected:

 private:
};

}  // namespace {{NAMESPACE}}
