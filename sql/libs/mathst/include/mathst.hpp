// Author: 
//
// Purpose:

#pragma once

#include "mathst_export.h"

namespace sql {

class FORGE_mathst_API mathst {
 public:
  mathst();
  mathst(const mathst&);
  mathst(mathst&&) noexcept;
  mathst& operator=(const mathst&);
  mathst& operator=(mathst&&) noexcept;
  virtual ~mathst();

 protected:

 private:
};

}  // namespace sql
