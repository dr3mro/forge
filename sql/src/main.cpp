// Author:
//
// Purpose:

#include "forge-version.cpp"
#include <iostream>
#include <sqlite3.h>
#include <string_view>

#include "math.h"

int main(int argc, char **argv) {
  if (argc == 2 && std::string_view(argv[1]) == "--version") {
    std::cout << forge_version << '\n';
    return 0;
  }

  sql::math::sum(5, 2);
  sqlite3 *db;
  char *errMsg = nullptr;

  // 1. Open (or create) the database file
  if (sqlite3_open("example.db", &db) != SQLITE_OK) {
    std::cerr << "Can't open database: " << sqlite3_errmsg(db) << "\n";
    return 1;
  }

  // 2. Execute simple SQL (Create table & insert data)
  const char *sql =
      "CREATE TABLE IF NOT EXISTS Users (ID INT PRIMARY KEY, Name TEXT);"
      "INSERT INTO Users (ID, Name) VALUES (1, 'Alice');";

  if (sqlite3_exec(db, sql, nullptr, nullptr, &errMsg) != SQLITE_OK) {
    std::cerr << "SQL error: " << errMsg << "\n";
    sqlite3_free(errMsg);
  }

  // 3. Query data using a prepared statement
  sqlite3_stmt *stmt;
  const char *query = "SELECT ID, Name FROM Users;";
  if (sqlite3_prepare_v2(db, query, -1, &stmt, nullptr) == SQLITE_OK) {
    while (sqlite3_step(stmt) == SQLITE_ROW) {
      int id = sqlite3_column_int(stmt, 0);
      const unsigned char *name = sqlite3_column_text(stmt, 1);
      std::cout << "ID: " << id << ", Name: " << name << "\n";
    }
    sqlite3_finalize(stmt); // Destroy prepared statement
  }

  // 4. Close the database connection
  sqlite3_close(db);
  return 0;
}
