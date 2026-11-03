#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

PLAYBOOK="ansible/playbooks/postgresql.yml"
ANSIBLE_PLAYBOOK="${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/ansible-playbook}"
ssh_password=""
sudo_password=""
auth_file=""
secret_file=""
inventory_file=""

cleanup() {
  rm -f -- "${auth_file:-}" "${secret_file:-}" "${inventory_file:-}"
  unset ssh_password sudo_password
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -z "${VIRTUAL_ENV:-}" || ! -x "$ANSIBLE_PLAYBOOK" ]]; then
  echo "ERROR: Aktifkan virtual environment yang berisi Ansible."
  echo "Contoh: source .venv/bin/activate"
  exit 1
fi

for cmd in ssh python mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Perintah '$cmd' tidak ditemukan."
    exit 1
  }
done

echo "=== PostgreSQL Installation Quick Start ==="
echo
read -r -p "IP atau hostname server PostgreSQL: " server
read -r -p "Username SSH: " ssh_user

[[ -n "$server" && -n "$ssh_user" ]] || {
  echo "ERROR: IP/hostname dan username SSH wajib diisi."
  exit 1
}
if [[ ! "$server" =~ ^[a-zA-Z0-9._:-]+$ || ! "$ssh_user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: Format server atau username tidak valid."
  exit 1
fi

read -r -p "Port PostgreSQL [5432]: " postgresql_port
postgresql_port="${postgresql_port:-5432}"
[[ "$postgresql_port" =~ ^[0-9]+$ ]] || {
  echo "ERROR: Port harus berupa angka antara 1 dan 65535."
  exit 1
}
port_num=$((10#$postgresql_port))
(( port_num >= 1 && port_num <= 65535 )) || {
  echo "ERROR: Port harus berupa angka antara 1 dan 65535."
  exit 1
}

echo
echo "Pilih alamat tempat PostgreSQL akan listen:"
echo "  1) localhost  - lokal saja (default, paling aman)"
echo "  2) Private IP - IP interface server untuk jaringan internal"
echo "  3) Custom IP  - masukkan alamat IPv4 tertentu"
echo "  4) *          - semua interface (berisiko; amankan firewall)"
read -r -p "Pilihan [1]: " listen_choice
listen_choice="${listen_choice:-1}"
case "$listen_choice" in
  1) postgresql_listen_addresses="localhost" ;;
  2) read -r -p "Masukkan private IPv4 server: " postgresql_listen_addresses ;;
  3) read -r -p "Masukkan custom IPv4 address: " postgresql_listen_addresses ;;
  4)
    postgresql_listen_addresses="*"
    echo "PERINGATAN: PostgreSQL akan listen pada semua interface."
    echo "Akses remote tetap memerlukan aturan pg_hba.conf dan firewall."
    ;;
  *)
    echo "ERROR: Pilihan tidak valid."
    exit 1
    ;;
esac

if [[ "$postgresql_listen_addresses" != "localhost" && "$postgresql_listen_addresses" != "*" ]] &&
   ! python -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$postgresql_listen_addresses" 2>/dev/null; then
  echo "ERROR: IP address tidak valid."
  exit 1
fi

echo
echo "Catatan: memilih IP non-localhost hanya mengubah listen_addresses."
echo "Akses remote belum dibuka di pg_hba.conf; firewall juga harus dibatasi."
read -r -p "Lanjutkan? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || {
  echo "Dibatalkan."
  exit 0
}

ssh_key_path=""
read -r -p "Path private SSH key [~/.ssh/id_rsa]: " ssh_key_path
ssh_key_path="${ssh_key_path:-~/.ssh/id_rsa}"
if [[ "$ssh_key_path" == "~" ]]; then
  ssh_key_path="$HOME"
elif [[ "$ssh_key_path" == "~/"* ]]; then
  ssh_key_path="$HOME/${ssh_key_path#~/}"
fi

ssh_target="$ssh_user@$server"
ssh_auth="password"
if [[ -f "$ssh_key_path" && -r "$ssh_key_path" ]] &&
   ssh -i "$ssh_key_path" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 "$ssh_target" true; then
  ssh_auth="key"
  echo "SSH key berhasil."
  read -r -s -p "Password sudo untuk $ssh_user: " sudo_password
  echo
else
  echo "SSH key tidak tersedia atau gagal; menggunakan password SSH."
  command -v sshpass >/dev/null 2>&1 || {
    echo "ERROR: sshpass belum terpasang. Debian/Ubuntu: sudo apt install sshpass"
    exit 1
  }
  read -r -s -p "Password SSH (juga digunakan untuk sudo): " ssh_password
  echo
  [[ -n "$ssh_password" ]] || {
    echo "ERROR: Password SSH tidak boleh kosong."
    exit 1
  }
  auth_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-ssh.XXXXXX")"
  chmod 600 "$auth_file"
  printf '%s\n' "$ssh_password" > "$auth_file"
  if ! sshpass -f "$auth_file" ssh -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o ConnectTimeout=8 "$ssh_target" true; then
    echo "ERROR: Login SSH gagal."
    exit 1
  fi
  sudo_password="$ssh_password"
  echo "Login SSH berhasil."
fi

[[ -n "$sudo_password" ]] || {
  echo "ERROR: Password sudo tidak boleh kosong."
  exit 1
}

inventory_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-postgresql-inventory.XXXXXX.yml")"
chmod 600 "$inventory_file"
cat > "$inventory_file" <<INVENTORY_EOF
---
all:
  children:
    postgresql_servers:
      hosts:
        postgresql01:
          ansible_host: "$server"
          ansible_user: "$ssh_user"
INVENTORY_EOF

secret_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-postgresql-vars.XXXXXX")"
chmod 600 "$secret_file"
printf '%s\0%s\0%s\0%s' "$ssh_password" "$sudo_password" "$postgresql_port" "$postgresql_listen_addresses" |
python -c '
import json, sys
ssh_password, sudo_password, port, listen = (v.decode() for v in sys.stdin.buffer.read().split(b"\0"))
data = {
    "ansible_become_password": sudo_password,
    "postgresql_port": int(port),
    "postgresql_listen_addresses": listen,
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
  ansible_args+=(--private-key "$ssh_key_path")
else
  ansible_args+=(--ssh-extra-args='-o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no')
fi

echo
echo "Memeriksa sintaks playbook..."
"$ANSIBLE_PLAYBOOK" -i "$inventory_file" "$PLAYBOOK" --syntax-check
echo
echo "Memulai instalasi PostgreSQL pada $server ..."
"$ANSIBLE_PLAYBOOK" -i "$inventory_file" "$PLAYBOOK" --extra-vars "@$secret_file" "${ansible_args[@]}"
echo
echo "Selesai. PostgreSQL sudah diverifikasi oleh playbook."
