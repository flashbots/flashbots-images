#!/usr/bin/env python3

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
IMAGES_DIR = REPO_ROOT / "images"
SNAPSHOT_CONFIG = Path("shared/debian-snapshot.conf")
EXPECTED_SNAPSHOT = "20260430T025253Z"
PINNED_IMAGES = {
    "flashbox-l1.conf",
    "flashbox-l2.conf",
    "l2-op-rbuilder-bproxy.conf",
    "l2-op-rbuilder.conf",
    "l2-simulator.conf",
}


def directives(path: Path, section_name: str, key_name: str) -> list[str]:
    section = None
    values = []

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section != section_name or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == key_name:
            values.append(value.strip())

    return values


class DebianSnapshotConfigTest(unittest.TestCase):
    def test_shared_config_keeps_expected_snapshot(self) -> None:
        values = directives(
            REPO_ROOT / SNAPSHOT_CONFIG, "Distribution", "Snapshot"
        )
        self.assertEqual(values, [EXPECTED_SNAPSHOT])

    def test_exactly_production_images_include_shared_snapshot(self) -> None:
        including_images = {
            path.name
            for path in IMAGES_DIR.glob("*.conf")
            if str(SNAPSHOT_CONFIG) in directives(path, "Include", "Include")
        }
        self.assertEqual(including_images, PINNED_IMAGES)

    def test_images_do_not_override_shared_snapshot(self) -> None:
        for path in IMAGES_DIR.glob("*.conf"):
            with self.subTest(image=path.name):
                self.assertEqual(
                    directives(path, "Distribution", "Snapshot"),
                    [],
                    f"{path.name} must not override the shared snapshot",
                )

    def test_tdx_dummy_remains_unpinned(self) -> None:
        path = IMAGES_DIR / "tdx-dummy.conf"
        self.assertNotIn(
            str(SNAPSHOT_CONFIG), directives(path, "Include", "Include")
        )
        self.assertEqual(directives(path, "Distribution", "Snapshot"), [])


if __name__ == "__main__":
    unittest.main()
