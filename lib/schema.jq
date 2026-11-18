# Forge manifest schema validator (TOML already converted to JSON).
# Emits one string per validation error on stdout; empty output means valid.
# Invoked as: jq -r -f schema.jq

def err($m): $m;
def ident: (type == "string") and test("^[A-Za-z_][A-Za-z0-9_]*$");
def no_meta:
  . as $s
  | ["$", "`", ";", "&", "|", "<", ">", "(", ")", "{", "}", "*", "?", "[", "]", "'", "\"", "\\", "\n", "\r"]
    | all(. as $c | ($s | contains($c) | not));
def safepath:
  (type == "string") and (length > 0)
  and (startswith("/") | not)
  and ((split("/") | index("..")) == null)
  and no_meta;
def safeurl:
  (type == "string")
  and (startswith("https://") or startswith("git@") or startswith("file://"))
  and no_meta;
def allowed($s):
  if   $s == "conan" then ["source", "ref", "cmake_target", "conan_options", "cmake_package"]
  elif $s == "vcpkg" then ["source", "port", "cmake_package", "cmake_target", "features", "default_features", "version"]
  elif $s == "git"   then ["source", "url", "rev", "cmake_target"]
  elif $s == "path"  then ["source", "path", "cmake_target"]
  else [] end;

def check_target($kind; $t):
  if ($t | type) != "object" then err($kind + " entry must be a table")
  else
    (if ($t | has("name") | not) then err($kind + ": missing 'name'")
     elif ($t.name | ident | not) then err($kind + ": invalid name '" + ($t.name | tostring) + "'")
     else empty end),
    (if ($t | has("path") | not) then err($kind + ": missing 'path'")
     elif ($t.path | safepath | not) then err($kind + ": unsafe path '" + ($t.path | tostring) + "'")
     else empty end),
    (if ($t | has("links")) then
       if ($t.links | type) != "array" then err($kind + ": 'links' must be an array")
       elif ($t.links | all(type == "string") | not) then err($kind + ": 'links' must contain only strings")
       else empty end
     else empty end),
    (if ($t | has("type")) and ($kind != "lib" or (["static", "shared"] | index($t.type)) == null)
     then err($kind + ": 'type' must be static or shared and is only valid for libraries") else empty end),
    ($t | keys[] | select(. as $k | (["name", "path", "links", "type"] | index($k)) | not)
     | err($kind + ": unknown key '" + . + "'"))
  end;

def check_dep($n; $d):
  if ($d | type) != "object" then err($n + ": dependency must be a table")
  else
    (if ($d | has("source") | not) then err($n + ": missing 'source'")
     elif ((["conan", "vcpkg", "git", "path"] | index($d.source)) == null)
       then err($n + ": invalid source '" + ($d.source | tostring) + "'")
     else empty end),
    (if ($d.source == "conan") then
       (if ($d | has("ref") | not) then err($n + ": conan dependency missing 'ref'")
        elif ($d.ref | type) != "string" then err($n + ": 'ref' must be a string")
        else empty end),
       (if ($d | has("cmake_target") | not) then err($n + ": missing 'cmake_target'")
        elif ($d.cmake_target | type) != "string" then err($n + ": 'cmake_target' must be a string")
        else empty end)
     elif ($d.source == "vcpkg") then
       (if ($d.port | type) != "string" then err($n + ": missing vcpkg port")
        elif ($d.port | test("^[a-z0-9]+(-[a-z0-9]+)*$") | not) then err($n + ": invalid vcpkg port")
        else empty end),
       (if ($d | has("features")) and
           ($d.features | (type == "array" and all(type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$"))) | not)
        then err($n + ": features must be an array of vcpkg feature names") else empty end),
       (if ($d | has("default_features")) and ($d.default_features | type) != "boolean"
        then err($n + ": default_features must be a boolean") else empty end),
       (if ($d | has("version")) and ($d.version | (type == "string" and length > 0) | not)
        then err($n + ": vcpkg version must be a nonempty string") else empty end),
       (if ($d.cmake_package | type) != "string" then err($n + ": missing CMake package")
        else empty end)
     elif ($d.source == "git") then
       (if ($d | has("url") | not) then err($n + ": git dependency missing 'url'")
        elif ($d.url | safeurl | not)
          then err($n + ": git 'url' must be an https://, git@ or file:// URL without shell metacharacters")
        else empty end),
       (if ($d | has("rev") | not) then err($n + ": git dependency missing 'rev'")
        elif ((($d.rev | type) == "string")
              and ($d.rev | test("^[0-9a-fA-F]{40}$"))) | not
          then err($n + ": git 'rev' must be a full 40-char SHA")
        else empty end),
       (if ($d | has("cmake_target") | not) then err($n + ": missing 'cmake_target'")
        else empty end)
     elif ($d.source == "path") then
       (if ($d | has("path") | not) then err($n + ": path dependency missing 'path'")
        elif ($d.path | safepath | not) then err($n + ": unsafe path for dependency")
        else empty end),
       (if ($d | has("cmake_target") | not) then err($n + ": missing 'cmake_target'")
        else empty end)
     else empty end),
    (if ($d | has("cmake_package")) then
       if ($d.cmake_package | type) != "string" then err($n + ": invalid CMake package")
       elif ($d.cmake_package | test("^[A-Za-z0-9_][A-Za-z0-9_.+-]*$") | not) then err($n + ": invalid CMake package")
       elif ($d.cmake_target | type) != "string" then err($n + ": missing CMake target")
       elif ($d.cmake_target | test("^[A-Za-z0-9_][A-Za-z0-9_.+-]*(::[A-Za-z0-9_][A-Za-z0-9_.+-]*)*$") | not)
         then err($n + ": invalid CMake target")
       else empty end
     else empty end),
    (if ($d | has("conan_options")) then
       if ($d.conan_options | type) != "object" then err($n + ": 'conan_options' must be a table")
       else empty end
     else empty end),
    ($d | keys[] | select(. as $k | (allowed($d.source) | index($k)) | not)
     | err($n + ": unknown key '" + . + "'"))
  end;

[
  (if type != "object" then err("manifest root must be a table") else empty end),

  (if (type == "object" and (.schema != 1 and .schema != 2))
     then err("'schema' must be 1 or 2") else empty end),

  (if type == "object" then
     (keys[] | select(. as $k |
        (["schema", "package", "build", "bin", "lib", "test", "dependencies", "workspace", "cmake"] | index($k)) | not)
      | err("unknown top-level key '" + . + "'"))
   else empty end),

  (if has("cmake") then
     if (.cmake | type) != "object" then err("[cmake] must be a table")
     else
       (.cmake | keys[] | select(. != "variables") | err("cmake: unknown key '" + . + "'")),
       (if (.cmake | has("variables")) then
          if (.cmake.variables | type) != "object" then err("[cmake.variables] must be a table")
          else .cmake.variables | to_entries[]
            | if (.key | ident | not) then err("cmake.variables: invalid name '" + .key + "'")
              elif (.value | type | IN("string", "number", "boolean") | not)
                then err("cmake.variables: '" + .key + "' must be a string, number or boolean")
              else empty end
          end
        else empty end)
     end
   else empty end),

  (if has("workspace") then
     (if .schema != 2 then err("[workspace] requires schema = 2") else empty end),
     (if (.workspace | type) != "object" then err("[workspace] must be a table")
      else
        (if (.workspace | has("members") | not) then err("workspace: missing 'members'")
         elif (.workspace.members | type) != "array" then err("workspace: 'members' must be an array")
         else (.workspace.members[] | safepath | not
               | if . then err("workspace: unsafe member path") else empty end)
         end),
        (.workspace | keys[] | select(. != "members")
         | err("workspace: unknown key '" + . + "'"))
      end)
   else empty end),

  (if (has("package") | not) then err("missing [package] table")
   elif (.package | type) != "object" then err("[package] must be a table")
   else
     (if (.package | has("name") | not) then err("package: missing 'name'")
      elif (.package.name | ident | not) then err("package: invalid name")
      else empty end),
     (if (.package | has("version") | not) then err("package: missing 'version'")
      elif (.package.version | type) != "string" then err("package: 'version' must be a string")
      else empty end),
     (if (.package | has("cppstd") | not) then err("package: missing 'cppstd'")
      elif ((.package.cppstd | type) != "string"
            or ((.package.cppstd | test("^(17|20|23)$")) | not))
        then err("package: 'cppstd' must be 17, 20 or 23")
      else empty end),
     (if (.package | has("description")) and (.package.description | type) != "string"
      then err("package: 'description' must be a string") else empty end),
     (if (.package | has("author"))
      then if (.package.author | type) != "string" then err("package: 'author' must be a string") else empty end
      else empty end),
     (.package | keys[] | select(. as $k | (["name", "version", "cppstd", "description", "author"] | index($k)) | not)
      | err("package: unknown key '" + . + "'"))
   end),

  (if has("build") then
     (if (.build | type) != "object" then err("[build] must be a table")
      else
        (if (.build | has("generator")) and ((.build.generator | type) != "string")
          then err("build: 'generator' must be a string") else empty end),
        (if (.build | has("default_profile")) and ((.build.default_profile | type) != "string")
          then err("build: 'default_profile' must be a string") else empty end),
        (if (.build | has("vcpkg_baseline")) and
            (.build.vcpkg_baseline | (type == "string" and test("^[a-fA-F0-9]{40}$")) | not)
         then err("build: vcpkg_baseline must be a full Git SHA") else empty end),
        (.build | keys[] | select(. as $k | (["generator", "default_profile", "vcpkg_baseline"] | index($k)) | not)
         | err("build: unknown key '" + . + "'"))
      end)
   else empty end),

  (["bin", "lib", "test"][] as $kind
   | if has($kind) then
       (if (.[$kind] | type) != "array" then err($kind + " must be an array of tables")
        else (.[$kind][] | check_target($kind; .)) end)
     else empty end),

  (if has("dependencies") then
     (if (.dependencies | type) != "object" then err("[dependencies] must be a table")
      else
        (.dependencies | to_entries[] | .key as $n |
          (if ($n | ident | not) then err("dependency name invalid: " + $n) else empty end),
          check_dep($n; .value))
      end)
   else empty end)
] | .[]
