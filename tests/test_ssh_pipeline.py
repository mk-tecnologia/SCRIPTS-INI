"""Valida a etapa SSH com saída extensa e falhas reais do comando."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SSHPipelineTest(unittest.TestCase):
    def test_validation_reaches_restart_with_large_output(self):
        for name in ('setup-debian13.sh', 'setup-proxmox.sh', 'setup-pbs.sh'):
            source = (ROOT / name).read_text()
            validation = source.split('\nsshd -t\n', 1)[1].split('\nsystemctl restart ssh', 1)[0]
            for failure in (False, True):
                with self.subTest(script=name, failure=failure):
                    # Produção extensa após permitrootlogin reproduz SIGPIPE
                    # quando o consumidor antigo termina com awk exit.
                    mock = '''
sshd() {
    if [[ $1 == -t ]]; then return 0; fi
    printf 'permitrootlogin prohibit-password\n'
    local i
    for ((i=0; i<10000; i++)); do
        printf 'hostkey /etc/ssh/ssh_host_ed25519_key\n'
    done
    printf 'passwordauthentication no\nkbdinteractiveauthentication no\npubkeyauthentication yes\n'
}
die() { printf '%s\n' "$*" >&2; exit 1; }
systemctl() { printf 'restart reached\n'; }
'''
                    if failure:
                        mock += '\nsshd() { return 42; }\n'
                    program = 'set -Eeuo pipefail\n' + mock + validation + '\nsystemctl restart ssh\n'
                    result = subprocess.run(['bash', '-c', program], text=True, capture_output=True)
                    if failure:
                        self.assertEqual(result.returncode, 42)
                        self.assertNotIn('restart reached', result.stdout)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn('restart reached', result.stdout)


if __name__ == '__main__':
    unittest.main()
