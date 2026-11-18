"""Prepare dependency inputs, provision dependencies, and build on native runners."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tomllib

INPUTS = Path("target/forge-ci-inputs")
CACHE = Path("target/forge-ci-deps").resolve()
ARTIFACTS = Path("target/forge-ci-artifacts")
WINDOWS = os.name == "nt"
GENERATOR = "Visual Studio 17 2022" if WINDOWS else "Ninja"
VCPKG_RELEASE = "2026.10.16"


def run(*args, cwd=None):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)


def projects(root, seen):
    root = root.resolve()
    if root in seen:
        raise ValueError(f"repeated workspace member: {root}")
    seen.add(root)
    with (root / "Forge.toml").open("rb") as stream:
        manifest = tomllib.load(stream)
    yield root, manifest
    for member in manifest.get("workspace", {}).get("members", []):
        child = (root / member).resolve()
        if child == root or not child.is_relative_to(root):
            raise ValueError(f"invalid workspace member: {member}")
        yield from projects(child, seen)


def write_json(name, value):
    (INPUTS / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def prepare():
    INPUTS.mkdir(parents=True, exist_ok=True)
    workspace = list(projects(Path.cwd(), set()))
    root_manifest = workspace[0][1]
    baseline = root_manifest.get("build", {}).get("vcpkg_baseline")
    git, ports = {}, {}
    conan = {}
    for _, manifest in workspace:
        for name, dep in manifest.get("dependencies", {}).items():
            source = dep["source"]
            if source == "git":
                if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) or not re.fullmatch(r"[a-fA-F0-9]{40}", dep["rev"]):
                    raise ValueError(f"invalid Git dependency name or revision: {name}")
                key = name.upper()
                ref = [dep["url"], dep["rev"]]
                if key in git and git[key] != ref:
                    raise ValueError(f"conflicting Git dependencies for {name}")
                git[key] = ref
            elif source == "conan":
                ref, options = dep["ref"], dep.get("conan_options", {})
                if ref in conan and conan[ref] != options:
                    raise ValueError(f"conflicting Conan options for {ref}")
                conan[ref] = options
            elif source == "vcpkg":
                port = dep["port"]
                settings = {
                    "name": port, "features": sorted(set(dep.get("features", []))),
                    "default-features": dep.get("default_features", True),
                }
                if "version" in dep:
                    if not baseline:
                        raise ValueError("vcpkg version overrides require build.vcpkg_baseline")
                    settings["version"] = dep["version"]
                if port in ports and ports[port] != settings:
                    raise ValueError(f"conflicting vcpkg settings for {port}")
                ports[port] = settings
    if baseline and not re.fullmatch(r"[a-fA-F0-9]{40}", baseline):
        raise ValueError("build.vcpkg_baseline must be a full Git SHA")
    write_json("plan.json", {"git": git, "conan": bool(conan), "vcpkg": bool(ports),
                             "vcpkg_ref": baseline or VCPKG_RELEASE})
    for filename in ("conanfile.txt", "conan.lock", "vcpkg.json"):
        (INPUTS / filename).unlink(missing_ok=True)
    if conan:
        for filename in ("conanfile.txt", "conan.lock"):
            if not Path(filename).is_file():
                raise ValueError(f"missing {filename}; run forge sync --apply and forge deps lock")
            shutil.copyfile(filename, INPUTS / filename)
        validate_recipe(conan)
    if ports:
        manifest = {"dependencies": [], "overrides": []}
        if baseline:
            manifest["builtin-baseline"] = baseline
        for port, settings in sorted(ports.items()):
            version = settings.pop("version", None)
            if version:
                manifest["overrides"].append({"name": port, "version": version})
            manifest["dependencies"].append(settings if settings["features"] or
                                            not settings["default-features"] else port)
        if not manifest["overrides"]:
            del manifest["overrides"]
        write_json("vcpkg.json", manifest)


def validate_recipe(conan):
    sections = {}
    section = set()
    for line in (INPUTS / "conanfile.txt").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = sections.setdefault(line[1:-1], set())
        elif line and not line.startswith("#"):
            section.add(line)
    requires = set(conan)
    options = {f"{ref.split('/', 1)[0]}/*:{key}={value}"
               for ref, values in conan.items() for key, value in values.items()}
    if requires != sections.get("requires", set()) or not options <= sections.get("options", set()):
        raise ValueError("conanfile.txt is out of sync with Forge.toml; run forge sync --apply and forge deps lock")


def clone(url, ref, directory):
    if not (directory / ".git").is_dir():
        run("git", "clone", "--no-checkout", "--", url, directory)
    elif subprocess.run(["git", "-C", str(directory), "cat-file", "-e", f"{ref}^{{commit}}"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        run("git", "-C", directory, "fetch", "--", url, ref)
    run("git", "-C", directory, "checkout", "--detach", ref)


def install_dependencies(plan, config):
    CACHE.mkdir(parents=True, exist_ok=True)
    for key, (url, ref) in plan["git"].items():
        clone(url, ref, CACHE / "git" / key)
    if plan["conan"]:
        os.environ["CONAN_HOME"] = str(CACHE / "conan-home")
        run("conan", "profile", "detect", "--force")
        run("conan", "install", INPUTS / "conanfile.txt",
            "--lockfile", INPUTS / "conan.lock", "--output-folder", CACHE / "conan",
            "-s", f"build_type={config}", "--build=missing",
            "-c", f"tools.cmake.cmaketoolchain:generator={GENERATOR}")
    if plan["vcpkg"]:
        vcpkg = CACHE / "vcpkg"
        clone("https://github.com/microsoft/vcpkg.git", plan["vcpkg_ref"], vcpkg)
        os.environ["VCPKG_ROOT"] = str(vcpkg)
        if WINDOWS:
            run("cmd", "/c", "bootstrap-vcpkg.bat", "-disableMetrics", cwd=vcpkg)
        else:
            run("sh", "bootstrap-vcpkg.sh", "-disableMetrics", cwd=vcpkg)
        exe = vcpkg / ("vcpkg.exe" if WINDOWS else "vcpkg")
        run(exe, "install", f"--x-manifest-root={INPUTS.resolve()}",
            f"--x-install-root={CACHE / 'vcpkg-installed'}")


def build(plan, config):
    directory = (Path("target/forge-ci-build") / config).resolve()
    query = directory / ".cmake/api/v1/query"
    query.mkdir(parents=True, exist_ok=True)
    (query / "codemodel-v2").touch()
    args = ["-G", GENERATOR, f"-DCMAKE_BUILD_TYPE={config}",
            f"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY={directory / 'bin'}",
            f"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY={directory / 'lib'}",
            f"-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY={directory / 'lib'}"]
    if not WINDOWS:
        origin = "@loader_path" if sys.platform == "darwin" else "$ORIGIN"
        args.append(f"-DCMAKE_BUILD_RPATH={origin}/../lib")
    toolchain = CACHE / "conan/conan_toolchain.cmake" if plan["conan"] else None
    if plan["vcpkg"]:
        vcpkg = CACHE / "vcpkg"
        os.environ["VCPKG_ROOT"] = str(vcpkg)
        args += [f"-DCMAKE_TOOLCHAIN_FILE={vcpkg / 'scripts/buildsystems/vcpkg.cmake'}",
                 f"-DVCPKG_MANIFEST_DIR={INPUTS.resolve()}",
                 f"-DVCPKG_INSTALLED_DIR={CACHE / 'vcpkg-installed'}",
                 "-DVCPKG_MANIFEST_INSTALL=OFF"]
        if toolchain:
            args.append(f"-DVCPKG_CHAINLOAD_TOOLCHAIN_FILE={toolchain}")
    elif toolchain:
        args.append(f"-DCMAKE_TOOLCHAIN_FILE={toolchain}")
    for key in plan["git"]:
        args.append(f"-DFETCHCONTENT_SOURCE_DIR_{key}={CACHE / 'git' / key}")
    run("cmake", "-S", ".", "-B", directory, *args)
    run("cmake", "--build", directory, "--config", config, "--parallel")
    run("ctest", "--test-dir", directory, "-C", config, "--output-on-failure")
    package(directory, config)


def package(directory, config):
    reply = directory / ".cmake/api/v1/reply"
    index = json.loads(max(reply.glob("index-*.json")).read_text(encoding="utf-8"))
    model = json.loads((reply / index["reply"]["codemodel-v2"]["jsonFile"]).read_text(encoding="utf-8"))
    configuration = next(item for item in model["configurations"] if item["name"] == config)
    workspace = list(projects(Path.cwd(), set()))
    targets = {item["name"] for _, manifest in workspace for kind in ("lib", "bin")
               for item in manifest.get(kind, [])}
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    with tarfile.open(ARTIFACTS / f"project-{config}.tar.gz", "w:gz", dereference=True) as archive:
        for entry in configuration["targets"]:
            if entry["name"] not in targets:
                continue
            target = json.loads((reply / entry["jsonFile"]).read_text(encoding="utf-8"))
            found = set()
            for artifact in target.get("artifacts", []):
                path = directory / artifact["path"]
                folder = "bin" if target["type"] == "EXECUTABLE" or path.suffix == ".dll" else "lib"
                archive.add(path, arcname=f"{folder}/{path.name}")
                found.add(path)
            if WINDOWS and target["type"] == "SHARED_LIBRARY":
                import_lib = directory / "lib" / config / f"{entry['name']}.lib"
                if import_lib.is_file() and import_lib not in found:
                    archive.add(import_lib, arcname=f"lib/{import_lib.name}")
        for root, manifest in workspace:
            if manifest.get("lib") and (root / "include").is_dir():
                archive.add(root / "include", arcname=f"{manifest['package']['name']}/include")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("prepare", "deps", "build"))
    parser.add_argument("--config", default="Debug", choices=("Debug", "Release"))
    args = parser.parse_args()
    if args.phase == "prepare":
        prepare()
        return
    plan = json.loads((INPUTS / "plan.json").read_text(encoding="utf-8"))
    if args.phase == "deps":
        install_dependencies(plan, args.config)
    else:
        build(plan, args.config)


if __name__ == "__main__":
    main()
