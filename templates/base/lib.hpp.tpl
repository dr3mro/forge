#pragma once

namespace {{NAMESPACE}} {

class {{NAME}}_library {
 public:
  {{NAME}}_library() = default;
  {{NAME}}_library(const {{NAME}}_library&) = default;
  {{NAME}}_library({{NAME}}_library&&) noexcept = default;
  {{NAME}}_library& operator=(const {{NAME}}_library&) = default;
  {{NAME}}_library& operator=({{NAME}}_library&&) noexcept = default;
  virtual ~{{NAME}}_library() = default;

  static int add(int a, int b) { return a + b; }

 protected:

 private:
};

}  // namespace {{NAMESPACE}}

namespace {{NAME}} {
int add(int a, int b);
}  // namespace {{NAME}}
