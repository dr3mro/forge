#pragma once

namespace {{NAMESPACE}} {

class {{NAME}} {
public:
  {{NAME}}();
  {{NAME}}(const {{NAME}} &);
  {{NAME}}({{NAME}} &&) noexcept;
  {{NAME}} &operator=(const {{NAME}} &);
  {{NAME}} &operator=({{NAME}} &&) noexcept;
  virtual ~{{NAME}}();

protected:
private:
};

} // namespace {{NAMESPACE}}
