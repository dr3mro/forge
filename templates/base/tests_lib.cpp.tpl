#include <cassert>
#include <type_traits>
#include <utility>

#include "{{NAME}}.hpp"

using Library = {{NAMESPACE}}::{{NAME}}_library;
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
  assert(Library::add(2, 3) == 5);
  assert({{NAME}}::add(2, 3) == 5);
  return 0;
}
