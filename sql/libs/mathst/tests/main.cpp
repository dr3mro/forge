// Author: 
//
// Purpose:

#include <type_traits>
#include <utility>

#include "mathst.hpp"

using Library = sql::mathst;
static_assert(std::is_default_constructible_v<Library>);
static_assert(std::is_copy_constructible_v<Library>);
static_assert(std::is_nothrow_move_constructible_v<Library>);
static_assert(std::is_copy_assignable_v<Library>);
static_assert(std::is_nothrow_move_assignable_v<Library>);
static_assert(std::has_virtual_destructor_v<Library>);

int main() {
  Library original;
  Library copy(original);
  Library moved(std::move(copy));
  copy = original;
  moved = std::move(copy);
  return 0;
}
