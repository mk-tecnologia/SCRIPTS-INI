"""Regressões do filtro deb822 usado pelos assistentes, sem alterar /etc/apt."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class EnterpriseSourcesTest(unittest.TestCase):
    def test_repositories_and_repeated_runs(self):
        for script in ("setup-proxmox.sh", "setup-pbs.sh"):
            source = (ROOT / script).read_text()
            function = source.split("disable_enterprise_repository() {", 1)[1]
            program = function.split("awk '", 1)[1].split("' \"$file\"", 1)[0]

            def transform(value):
                return subprocess.run(
                    ["awk", program], input=value, text=True,
                    check=True, capture_output=True,
                ).stdout

            for path in ("debian/pve", "debian/pbs", "debian/ceph-squid"):
                active = (
                    f"Types: deb\nURIs: https://enterprise.proxmox.com/{path}\n"
                    "Suites: trixie\nComponents: enterprise\n"
                )
                commented = "\n".join("# " + line for line in active.splitlines()) + "\n"
                public = (
                    "Types: deb\nURIs: http://deb.debian.org/debian\n"
                    "Suites: trixie\nComponents: main\n"
                )
                cases = [
                    (active, active + "Enabled: no\n"),
                    (active + "Enabled: yes\n", active + "Enabled: no\n"),
                    (active + "Enabled: false\n", active + "Enabled: no\n"),
                    (active + "Enabled: no\n", active + "Enabled: no\n"),
                    (commented, commented),
                    (commented + "Enabled: false\n", commented + "# Enabled: false\n"),
                    (public, public),
                    (commented + public, commented + public),
                    (active + "\n" + public, active + "Enabled: no\n\n" + public),
                    (active.replace("URIs: ", "URIs:\n "),
                     active.replace("URIs: ", "URIs:\n ") + "Enabled: no\n"),
                ]
                for original, expected in cases:
                    with self.subTest(script=script, path=path, original=original):
                        result = transform(original)
                        self.assertEqual(result, expected.rstrip("\n") + "\n\n")
                        self.assertEqual(transform(result), result)


if __name__ == "__main__":
    unittest.main()
