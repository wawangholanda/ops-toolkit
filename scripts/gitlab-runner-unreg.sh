#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

PLAYBOOK="ansible/playbooks/gitlab-runner.yml"
ANSIBLE_PLAYBOOK="${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/ansible-playbook}"

if [[ -z "${VIRTUAL_ENV:-}" || ! -x "$ANSIBLE_PLAYBOOK" ]]; then
  echo "ERROR: Aktifkan virtual environment yang berisi Ansible."
  exit 1
fi

for cmd in ssh python mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Perintah '$cmd' tidak ditemukan."
    exit 1
  }
done

echo "=== GitLab Runner Management ==="
echo "1) List runners"
echo "2) Unregister runner"
read -r -p "Pilih [1-2]: " choice

case "$choice" in
  1) operation="list" ;;
  2) operation="unregister" ;;
  *) echo "Pilihan tidak valid."; exit 1 ;;
esac

read -r -p "IP atau hostname server Runner: " server
read -r -p "Username SSH: " ssh_user

[[ -n "$server" && -n "$ssh_user" ]] || {
  echo "ERROR: IP/hostname dan username SSH wajib diisi."
  exit 1
}

# Avoid malformed inventory from accidental YAML-special characters.
if [[ ! "$server" =~ ^[a-zA-Z0-9._:-]+$ ||
      ! "$ssh_user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: Format server atau username tidak valid."
  exit 1
fi

secret_file=""
auth_file=""
tmp_output=""
INVENTORY=""

cleanup() {
  rm -f -- "$secret_file" "$auth_file" "$tmp_output" "$INVENTORY"
  unset ssh_password sudo_password
}
trap cleanup EXIT INT TERM

# Use a private temporary inventory; never overwrite the project's inventory.
INVENTORY="$(mktemp "${TMPDIR:-/tmp}/mydevops-runner-inventory.XXXXXX.yml")"
chmod 600 "$INVENTORY"
cat > "$INVENTORY" <<INVENTORY_EOF
---
all:
  children:
    gitlab_runners:
      hosts:
        runner01:
          ansible_host: "$server"
          ansible_user: "$ssh_user"
INVENTORY_EOF

ssh_target="${ssh_user}@${server}"
ssh_password=""
sudo_password=""
ssh_auth="key"

if [[ -f "$HOME/.ssh/id_rsa" ]] &&
   ssh -i "$HOME/.ssh/id_rsa" \
       -o IdentitiesOnly=yes \
       -o BatchMode=yes \
       -o ConnectTimeout=8 \
       "$ssh_target" true >/dev/null 2>&1; then
  echo "SSH key berhasil."
  read -r -s -p "Password sudo untuk $ssh_user: " sudo_password
  echo
else
  echo "SSH key tidak berhasil; menggunakan password SSH."

  command -v sshpass >/dev/null 2>&1 || {
    echo "ERROR: sshpass belum terpasang. Pada Kali/Debian: sudo apt install sshpass"
    exit 1
  }

  read -r -s -p "Password SSH (juga digunakan untuk sudo): " ssh_password
  echo
  [[ -n "$ssh_password" ]] || {
    echo "ERROR: Password tidak boleh kosong."
    exit 1
  }

  auth_file="$(mktemp "${TMPDIR:-/tmp}/mydevops-ssh-pass.XXXXXX")"
  chmod 600 "$auth_file"
  printf '%s\n' "$ssh_password" > "$auth_file"

  if ! sshpass -f "$auth_file" ssh \
       -o PreferredAuthentications=password,keyboard-interactive \
       -o PubkeyAuthentication=no \
       -o ConnectTimeout=8 \
       "$ssh_target" true; then
    echo "ERROR: Login SSH gagal."
    exit 1
  fi

  ssh_auth="password"
  sudo_password="$ssh_password"
fi

[[ -n "$sudo_password" ]] || {
  echo "ERROR: Password sudo tidak boleh kosong."
  exit 1
}

# Secrets are stored only in a mode-0600 temporary file.
secret_file="$(mktemp "${TMPDIR:-/tmp}/mydevops-runner-manage.XXXXXX")"
chmod 600 "$secret_file"

# Pass secrets to Python through stdin, not environment variables.
printf '%s\0%s\0%s' "$ssh_password" "$sudo_password" "$operation" |
python -c '
import json, sys
ssh_password, sudo_password, operation = (
    value.decode() for value in sys.stdin.buffer.read().split(b"\0")
)
data = {
    "gitlab_runner_operation": operation,
    "ansible_become_password": sudo_password,
}
if ssh_password:
    data["ansible_password"] = ssh_password
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
' "$secret_file"

unset ssh_password sudo_password

ansible_args=()
if [[ "$ssh_auth" == "key" ]]; then
  ansible_args+=(--private-key "$HOME/.ssh/id_rsa")
else
  # Ansible uses ansible_password from the protected extra-vars file.
  ansible_args+=(--ssh-extra-args='-o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no')
fi

run_playbook() {
  "$ANSIBLE_PLAYBOOK" \
    -i "$INVENTORY" \
    "$PLAYBOOK" \
    --extra-vars "@$secret_file" \
    "${ansible_args[@]}"
}

assert_target_host_matched() {
  if grep -Eq 'skipping: no hosts matched|provided hosts list is empty|Unable to parse .* as an inventory source' "$1"; then
    echo "ERROR: Ansible tidak menemukan host target yang valid. Operasi dihentikan."
    return 1
  fi
}

tmp_output="$(mktemp "${TMPDIR:-/tmp}/mydevops-runner-output.XXXXXX")"
chmod 600 "$tmp_output"

echo
echo "Memeriksa sintaks playbook..."
"$ANSIBLE_PLAYBOOK" -i "$INVENTORY" "$PLAYBOOK" --syntax-check

echo
echo "Mengambil daftar runner dari $server ..."
if [[ "$operation" == "list" ]]; then
  run_playbook 2>&1 | tee "$tmp_output"
  assert_target_host_matched "$tmp_output"
  exit 0
fi

# Fetch the list using the read-only operation first.
python - "$secret_file" <<'PYVARS'
import json, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

data["gitlab_runner_operation"] = "list"
data.pop("gitlab_runner_target_name", None)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
PYVARS
chmod 600 "$secret_file"

# Display the runner table and retain output for target-host validation.
run_playbook 2>&1 | tee "$tmp_output"
assert_target_host_matched "$tmp_output"

echo
read -r -p "Nama runner yang mau di-unregister (kosong untuk batal): " target_name
[[ -n "$target_name" ]] || {
  echo "Dibatalkan. Tidak ada runner yang dihapus."
  exit 0
}

echo
echo "Server : $server"
echo "Runner : $target_name"
echo "PERINGATAN: unregister akan menghapus registrasi runner yang dipilih."
read -r -p 'Ketik UNREGISTER untuk mengonfirmasi: ' confirmation
[[ "$confirmation" == "UNREGISTER" ]] || {
  echo "Dibatalkan. Tidak ada runner yang dihapus."
  exit 0
}

# Replace operation in the protected temporary vars file.
python - "$secret_file" "$target_name" <<'PY'
import json, sys
path, name = sys.argv[1:3]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["gitlab_runner_operation"] = "unregister"
data["gitlab_runner_target_name"] = name
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
PY
chmod 600 "$secret_file"

"$ANSIBLE_PLAYBOOK" \
  -i "$INVENTORY" \
  "$PLAYBOOK" \
  --extra-vars "@$secret_file" \
  "${ansible_args[@]}"

echo "Selesai. Periksa hasil task Ansible di atas."
