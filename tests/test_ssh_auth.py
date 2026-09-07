"""Valida precedência das diretivas com o parser real do OpenSSH."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SSHD = shutil.which('sshd') or '/usr/sbin/sshd'


@unittest.skipUnless(pathlib.Path(SSHD).is_file(), 'sshd indisponível')
class SSHAuthenticationTest(unittest.TestCase):
    def test_global_password_disabled_before_includes(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pathlib.Path(tmp)
            key = directory / 'host_key'
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True)
            included = directory / 'vendor.conf'
            included.write_text('PasswordAuthentication yes\nKbdInteractiveAuthentication yes\nPubkeyAuthentication no\n')
            for script in ('setup-debian13.sh', 'setup-proxmox.sh', 'setup-pbs.sh'):
                source = (ROOT / script).read_text().split('SSHD_CONFIG_TEMP=$(mktemp', 1)[1]
                program = source.split("awk '\n", 1)[1].split("' /etc/ssh/sshd_config", 1)[0]

                def transform(value):
                    return subprocess.run(['awk', program], input=value, text=True,
                                          capture_output=True, check=True).stdout

                for previous in ('', 'PasswordAuthentication yes\nChallengeResponseAuthentication yes\nPubkeyAuthentication no\n'):
                    with self.subTest(script=script, previous=previous):
                        original = f'HostKey {key}\nInclude {included}\n' + previous
                        original += 'Match User restricted\n    X11Forwarding no\n'
                        result = transform(original)
                        self.assertEqual(transform(result), result)
                        config = directory / 'sshd_config'
                        config.write_text(result)
                        for context in ([], ['-C', 'user=restricted,host=localhost,addr=127.0.0.1']):
                            output = subprocess.run([SSHD, '-T', '-f', str(config), *context],
                                                    text=True, capture_output=True, check=True).stdout
                            for expected in ('passwordauthentication no', 'kbdinteractiveauthentication no',
                                             'pubkeyauthentication yes'):
                                self.assertIn(expected, output.splitlines())
                            values = dict(line.split(' ', 1) for line in output.splitlines())
                            self.assertIn(values['permitrootlogin'], ('without-password', 'prohibit-password'))


if __name__ == '__main__':
    unittest.main()
