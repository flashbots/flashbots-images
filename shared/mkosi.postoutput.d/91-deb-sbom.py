#!/usr/bin/env python3
"""Convert the mkosi JSON manifest into a CycloneDX 1.6 SBOM.

Runs as an mkosi post-output script, and also standalone:

    91-deb-sbom.py [manifest]

Scope is Debian packages only — language-level and vendored dependencies are
not covered, which is why the composition is marked "incomplete". Output is
byte-deterministic for a given manifest: the timestamp comes from
SOURCE_DATE_EPOCH, defaulting to 0 because mkosi does not propagate it to
post-output scripts.

Environment overrides (relative paths resolve under $OUTPUTDIR, which
defaults to the working directory; the default output lands next to the
manifest):

  SBOM_MANIFEST         manifest to read (default: the unique *.manifest in
                        $OUTPUTDIR, following symlinks)
  SBOM_OUTPUT           output path (default: <manifest-stem>.debian-packages.cdx.json)
  SBOM_SUBJECT          artifact the SBOM describes (default: the .efi next to
                        the manifest, when present)
  SBOM_INCLUDE_HASHES   sha256 the subject into the SBOM (default: enabled;
                        set to 0/false/no/off to skip hashing — the subject
                        filename is still recorded when known)
  SBOM_DISTRO           purl distro qualifier (default: derived from the
                        manifest release, e.g. trixie -> debian-13)
  SBOM_NAMESPACE        purl namespace (default: debian)
  SBOM_LOCAL_PACKAGES   space-separated name globs of packages that do NOT
                        come from the Debian archive (default covers the
                        locally built kernel and attested-tls-proxy); they
                        get the "flashbots" purl namespace, no distro
                        qualifier, and a flashbots:package-origin property
  SBOM_IMAGE_NAME       root component name (default: $IMAGE_ID / manifest stem)
  SBOM_IMAGE_VERSION    root component version (default: $IMAGE_VERSION)
  SBOM_SOURCE_COMMIT    source commit property (default: $GITHUB_SHA)
  SBOM_DEBIAN_SNAPSHOT  debian snapshot property
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import sys
import tempfile
import urllib.parse
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from operator import itemgetter
from pathlib import Path
from typing import Any, NoReturn

SPEC_VERSION = "1.6"
TOOL_COMPONENT = {
    "type": "application",
    "name": "mkosi-manifest-to-cyclonedx",
    "version": "2",
}
# The implicit subject next to the manifest; matches Format=uki in
# shared/mkosi.conf. Other formats need an explicit SBOM_SUBJECT.
SUBJECT_SUFFIX = ".efi"
# Debian release codename -> VERSION_ID, for the syft/grype-style
# "distro=debian-13" purl qualifier. Unknown codenames fall back verbatim.
DEBIAN_VERSION_IDS = {"bullseye": "11", "bookworm": "12", "trixie": "13", "forky": "14"}
# Packages installed from outside the Debian archive (locally built kernel,
# Flashbots release debs). Overridable via SBOM_LOCAL_PACKAGES.
LOCAL_PACKAGE_GLOBS = ("linux-image-*-mkosi-*", "attested-tls-proxy")
LOCAL_NAMESPACE = "flashbots"

Package = dict[str, Any]  # one entry of the manifest's packages[] array
Component = dict[str, Any]  # one CycloneDX component


class SbomError(Exception):
    """Any input problem; converted to an error message + exit 1 in main()."""


def fail(message: str) -> NoReturn:
    raise SbomError(message)


def log(message: str) -> None:
    print(f"deb-sbom: {message}", file=sys.stderr)


def env_flag(name: str, *, default: bool) -> bool:
    value = os.environ.get(name)
    if not value:
        return default
    return value.strip().lower() not in {"0", "false", "no", "off"}


def sha256_file(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def discover_manifest(explicit: str | None, output_dir: Path) -> Path:
    if explicit:
        path = output_dir / explicit
        if not path.is_file():
            fail(f"manifest not found: {path}")
        return path

    # Deduplicate through resolve() so a latest.manifest symlink and its
    # target count as one manifest.
    manifests = sorted({path.resolve() for path in output_dir.glob("*.manifest")})
    if not manifests:
        fail(f"no *.manifest found in {output_dir}")
    if len(manifests) > 1:
        listing = "\n".join(f"  {path}" for path in manifests)
        fail(
            f"multiple manifests found in {output_dir}:\n{listing}\n"
            "set SBOM_MANIFEST to the intended manifest"
        )
    return manifests[0]


def discover_subject(
    explicit: str | None, manifest: Path, output_dir: Path
) -> Path | None:
    if explicit:
        subject = output_dir / explicit
        if not subject.is_file():
            fail(f"SBOM_SUBJECT not found: {subject}")
        return subject
    # The artifact the manifest describes sits next to it during builds;
    # standalone runs may only have the manifest.
    sibling = manifest.with_suffix(SUBJECT_SUFFIX)
    return sibling if sibling.is_file() else None


@dataclass(frozen=True)
class Settings:
    """Resolved inputs; every environment read happens in from_env()."""

    manifest: Path
    subject: Path | None
    output: Path
    namespace: str
    distro: str | None  # None -> derive from the release recorded in the manifest
    local_globs: tuple[str, ...]  # name globs of non-Debian-archive packages
    image_name: str
    image_version: str
    source_commit: str | None
    debian_snapshot: str | None
    include_hashes: bool
    epoch: int

    @classmethod
    def from_env(cls, manifest_arg: str | None) -> Settings:
        env = os.environ.get

        output_dir = Path(env("OUTPUTDIR") or Path.cwd()).resolve()
        if not output_dir.is_dir():
            fail(f"OUTPUTDIR is not a directory: {output_dir}")

        manifest = discover_manifest(manifest_arg or env("SBOM_MANIFEST"), output_dir)

        configured_output = env("SBOM_OUTPUT")
        if configured_output:
            output = output_dir / configured_output
        else:
            output = manifest.with_name(f"{manifest.stem}.debian-packages.cdx.json")

        try:
            epoch = int(env("SOURCE_DATE_EPOCH") or 0)
        except ValueError:
            fail("SOURCE_DATE_EPOCH must be an integer")

        local_packages = env("SBOM_LOCAL_PACKAGES")
        return cls(
            manifest=manifest,
            subject=discover_subject(env("SBOM_SUBJECT"), manifest, output_dir),
            output=output,
            namespace=env("SBOM_NAMESPACE", "debian"),
            distro=env("SBOM_DISTRO"),
            local_globs=(
                LOCAL_PACKAGE_GLOBS
                if local_packages is None
                else tuple(local_packages.split())
            ),
            image_name=env("SBOM_IMAGE_NAME") or env("IMAGE_ID") or manifest.stem,
            image_version=env("SBOM_IMAGE_VERSION") or env("IMAGE_VERSION") or "unknown",
            source_commit=env("SBOM_SOURCE_COMMIT") or env("GITHUB_SHA"),
            debian_snapshot=env("SBOM_DEBIAN_SNAPSHOT"),
            include_hashes=env_flag("SBOM_INCLUDE_HASHES", default=True),
            epoch=epoch,
        )


def load_manifest(path: Path) -> tuple[dict[str, Any], list[Any], str]:
    """Return (config, packages, sha256) from a single read of the manifest."""
    raw = path.read_bytes()
    try:
        document = json.loads(raw)
    except json.JSONDecodeError as error:
        fail(f"invalid JSON in {path}: {error}")
    if not isinstance(document, dict):
        fail("manifest root must be a JSON object")
    packages = document.get("packages")
    if not isinstance(packages, list):
        fail("manifest does not contain a packages array")
    # The config block is informative only; tolerate its absence.
    config = document.get("config")
    if not isinstance(config, dict):
        config = {}
    return config, packages, hashlib.sha256(raw).hexdigest()


def package_purl(
    name: str,
    version: str,
    architecture: str,
    namespace: str,
    distro: str | None,
) -> str:
    # Safe sets follow canonical purl encoding: notably '+' becomes %2B.
    encoded_namespace = urllib.parse.quote(namespace, safe=".-_")
    encoded_name = urllib.parse.quote(name, safe=".-_")
    encoded_version = urllib.parse.quote(version, safe=".-_~:")
    pairs = [("arch", architecture)]
    if distro:
        pairs.append(("distro", distro))
    qualifiers = urllib.parse.urlencode(
        pairs, quote_via=urllib.parse.quote, safe=".-_~:"
    )
    return f"pkg:deb/{encoded_namespace}/{encoded_name}@{encoded_version}?{qualifiers}"


def deb_component(
    package: Package,
    index: int,
    namespace: str,
    distro: str,
    local_globs: tuple[str, ...],
) -> Component:
    def required(key: str) -> str:
        value = package.get(key)
        if not isinstance(value, str) or not value:
            fail(f"package entry {index}: missing or invalid {key!r}")
        return value

    name = required("name")
    version = required("version")
    architecture = required("architecture")

    # Locally built / Flashbots-released debs don't exist in the Debian
    # archive; claiming namespace "debian" for them would be false origin.
    is_local = any(fnmatch.fnmatchcase(name, glob) for glob in local_globs)
    group = LOCAL_NAMESPACE if is_local else namespace

    properties = [
        {"name": "mkosi:package-type", "value": "deb"},
        {"name": "debian:architecture", "value": architecture},
    ]
    size = package.get("size")
    if isinstance(size, int):
        properties.append({"name": "mkosi:installed-size", "value": str(size)})
    if is_local:
        properties.append(
            {"name": "flashbots:package-origin", "value": "flashbots"}
        )

    purl = package_purl(
        name, version, architecture, group, None if is_local else distro
    )
    return {
        "type": "library",
        "bom-ref": purl,
        "group": group,
        "name": name,
        "version": version,
        "purl": purl,
        "properties": properties,
    }


def build_components(
    packages: list[Any],
    namespace: str,
    distro: str,
    local_globs: tuple[str, ...],
) -> list[Component]:
    components: list[Component] = []
    seen: set[str] = set()

    for index, package in enumerate(packages):
        if not isinstance(package, dict) or package.get("type") != "deb":
            continue
        component = deb_component(package, index, namespace, distro, local_globs)
        if component["purl"] in seen:
            fail(f"duplicate Debian package identity: {component['purl']}")
        seen.add(component["purl"])
        components.append(component)

    if not components:
        fail("manifest contains no packages with type=deb")
    components.sort(key=itemgetter("name", "version", "purl"))
    return components


def build_root_component(
    settings: Settings,
    release: str,
    manifest_digest: str,
    subject_digest: str | None,
    root_ref: str,
) -> Component:
    # Property order is part of the byte-determinism contract: only append.
    optional_properties = (
        ("flashbots:subject-filename", settings.subject.name if settings.subject else None),
        ("flashbots:source-commit", settings.source_commit),
        ("debian:snapshot", settings.debian_snapshot),
    )
    properties = [
        {"name": "flashbots:sbom-scope", "value": "debian-packages-only"},
        {"name": "flashbots:mkosi-manifest-sha256", "value": manifest_digest},
        {"name": "debian:release", "value": release},
        *({"name": name, "value": value} for name, value in optional_properties if value),
    ]
    component: Component = {
        "type": "operating-system",
        "bom-ref": root_ref,
        "name": settings.image_name,
        "version": settings.image_version,
        "properties": properties,
    }
    if subject_digest:
        component["hashes"] = [{"alg": "SHA-256", "content": subject_digest}]
    return component


def format_timestamp(epoch: int) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_sbom(
    root_component: Component,
    components: list[Component],
    root_ref: str,
    epoch: int,
) -> dict[str, Any]:
    # root_ref doubles as document serialNumber and root bom-ref on purpose:
    # both derive from the manifest identity, keeping output reproducible.
    return {
        "bomFormat": "CycloneDX",
        "specVersion": SPEC_VERSION,
        "serialNumber": root_ref,
        "version": 1,
        "metadata": {
            "timestamp": format_timestamp(epoch),
            "tools": {"components": [TOOL_COMPONENT]},
            "component": root_component,
        },
        "components": components,
        "compositions": [
            {
                "aggregate": "incomplete",
                "assemblies": [root_ref],
            }
        ],
    }


def write_json_atomic(path: Path, document: dict[str, Any]) -> None:
    if not path.parent.is_dir():
        fail(f"output directory does not exist: {path.parent}")
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
    ) as handle:
        # indent=2 plus the trailing newline are part of the byte-determinism
        # contract.
        json.dump(document, handle, indent=2)
        handle.write("\n")
        temporary = Path(handle.name)
    os.replace(temporary, path)


def run(settings: Settings) -> None:
    config, packages, manifest_digest = load_manifest(settings.manifest)
    release = str(
        config.get("release") or config.get("distribution") or "debian"
    ).lower()
    if settings.distro:
        distro = settings.distro.lower()
    elif release in DEBIAN_VERSION_IDS:
        # syft/grype convention for the purl qualifier, e.g. trixie -> debian-13
        distro = f"debian-{DEBIAN_VERSION_IDS[release]}"
    else:
        distro = release

    components = build_components(
        packages, settings.namespace, distro, settings.local_globs
    )
    root_ref_seed = "\0".join(
        (settings.image_name, settings.image_version, manifest_digest,
         settings.namespace, distro)
    )
    root_ref = f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, root_ref_seed)}"

    # The subject can be a multi-GB image, so hash it only after everything
    # cheap has validated.
    subject_digest = None
    if not settings.include_hashes:
        log("subject hashing disabled via SBOM_INCLUDE_HASHES")
    elif settings.subject:
        subject_digest = sha256_file(settings.subject)
    else:
        log("warning: no subject artifact found, SBOM will carry no image hash")

    root_component = build_root_component(
        settings, release, manifest_digest, subject_digest, root_ref
    )
    sbom = build_sbom(root_component, components, root_ref, settings.epoch)
    write_json_atomic(settings.output, sbom)

    log(f"manifest: {settings.manifest}")
    if settings.subject:
        log(f"subject:  {settings.subject.name}")
    log(f"wrote:    {settings.output}")
    log(f"packages: {len(components)}")


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "manifest",
        nargs="?",
        help="mkosi manifest to convert (overrides SBOM_MANIFEST)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        run(Settings.from_env(args.manifest))
    except SbomError as error:
        log(f"ERROR: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
