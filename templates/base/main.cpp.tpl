#include <iostream>
#include <string_view>
#include "forge-version.cpp"

int main(int argc, char** argv) {
  if (argc == 2 && std::string_view(argv[1]) == "--version") {
    std::cout << forge_version << '\n';
    return 0;
  }
  std::cout << "Hello from {{NAME}}!" << std::endl;
  return 0;
}
