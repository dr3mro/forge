"""Remove canonical Forge tables and array entries while retaining other TOML."""
import copy
import json
from pathlib import Path
import re
import sys
import tomllib


def remove_entry(source, name, member, links):
    expected = copy.deepcopy(tomllib.loads(source))
    if member:
        expected["workspace"]["members"].remove(member)
    else:
        del expected["dependencies"][name]
        if not expected["dependencies"] and not re.search(r"^\s*\[dependencies\]", source, re.M):
            del expected["dependencies"]
    for kind in ("bin", "lib", "test"):
        for target in expected.get(kind, []):
            if "links" in target:
                target["links"] = [link for link in target["links"] if link not in links]

    section = ""
    result = []
    lines = iter(source.splitlines(keepends=True))
    for line in lines:
        header = re.match(r"\s*(\[\[?[^\]]+\]\]?)\s*(?:#.*)?$", line)
        if header:
            section = header[1]
        dep = f"[dependencies.{name}"
        if not member and (section == dep + "]" or section.startswith(dep + ".")):
            continue

        array = re.match(r"(\s*)(links|members)\s*=", line)
        omit = []
        if array and section in ("[[bin]]", "[[lib]]", "[[test]]") and array[2] == "links":
            omit = links
        elif array and member and section == "[workspace]" and array[2] == "members":
            omit = [member]
        if omit:
            chunk = line
            while True:
                try:
                    values = tomllib.loads(chunk)[array[2]]
                    break
                except tomllib.TOMLDecodeError:
                    chunk += next(lines)
            filtered = [value for value in values if value not in omit]
            if filtered != values:
                line = f"{array[1]}{array[2]} = {json.dumps(filtered)}\n"
            else:
                line = chunk
        result.append(line)

    edited = "".join(result)
    if tomllib.loads(edited) != expected:
        raise ValueError("unsupported TOML layout")
    return edited


if __name__ == "__main__":
    path, name, member, links = sys.argv[1:]
    try:
        print(remove_entry(Path(path).read_text(), name, member, json.loads(links)), end="")
    except (KeyError, StopIteration, ValueError) as error:
        sys.exit(str(error) or "incomplete TOML array")
