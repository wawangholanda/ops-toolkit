#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

PLAYBOOK="ansible/playbooks/redis.yml"
ANSIBLE_PLAYBOOK="${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/ansible-playbook}"
ssh_password=""
sudo_password=""
redis_password=""
auth_file=""
secret_file=""
inventory_file=""

cleanup() {
  rm -f -- "${auth_file:-}" "${secret_file:-}" "${inventory_file:-}"
  unset ssh_password sudo_password redis_password
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

echo "=== Redis Installation Quick Start ==="
echo

read -r -p "IP atau hostname server Redis: " server
read -r -p "Username SSH: " ssh_user

[[ -n "$server" && -n "$ssh_user" ]] || {
  echo "ERROR: IP/hostname dan username SSH wajib diisi."
  exit 1
}

if [[ ! "$server" =~ ^[a-zA-Z0-9._:-]+$ ||
      ! "$ssh_user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: Format server atau username tidak valid."
  exit 1
fi

read -r -p "Port Redis [6379]: " redis_port
redis_port="${redis_port:-6379}"
[[ "$redis_port" =~ ^[0-9]+$ ]] || {
  echo "ERROR: Port harus berupa angka antara 1 dan 65535."
  exit 1
}
redis_port_num=$((10#$redis_port))
(( redis_port_num >= 1 && redis_port_num <= 65535 )) || {
    echo "ERROR: Port harus berupa angka antara 1 dan 65535."
    exit 1
  }

echo
echo "Pilih IP address tempat Redis akan listen:"
echo "  1) 127.0.0.1  - localhost saja (default, paling aman)"
echo "  2) Private IP  - IP interface server untuk jaringan internal"
echo "  3) Custom IP   - masukkan alamat IPv4 tertentu"
echo "  4) 0.0.0.0    - semua interface (berisiko; amankan firewall)"
read -r -p "Pilihan [1]: " bind_choice
bind_choice="${bind_choice:-1}"

case "$bind_choice" in
  1) redis_bind_address="127.0.0.1" ;;
  2) read -r -p "Masukkan private IP server: " redis_bind_address ;;
  3) read -r -p "Masukkan custom IPv4 address: " redis_bind_address ;;
  4)
    redis_bind_address="0.0.0.0"
    echo "PERINGATAN: Redis akan listen pada semua interface."
    echo "Pastikan firewall hanya mengizinkan sumber yang tepercaya."
    ;;
  *)
    echo "ERROR: Pilihan tidak valid."
    exit 1
    ;;
esac

if [[ "$redis_bind_address" != "0.0.0.0" ]] &&
   ! python -c 'import ipaddress,sys; ipaddress.IPv4Address(sys.argv[1])' "$redis_bind_address" 2>/dev/null; then
  echo "ERROR: IP address tidak valid."
  exit 1
fi

echo "Password bersifat opsional. Untuk akses remote, gunakan autentikasi"
echo "dan firewall; jangan mengekspos Redis langsung ke Internet."
read -r -s -p "Password Redis (kosong = tanpa password): " redis_password
echo

echo
echo "Target       : $ssh_user@$server"
echo "Redis port   : $redis_port"
echo "Bind address : $redis_bind_address"
echo "Authentication: $([[ -n "$redis_password" ]] && echo enabled || echo disabled)"
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
   ssh -i "$ssh_key_path" \
     -o IdentitiesOnly=yes \
     -o BatchMode=yes \
     -o ConnectTimeout=8 \
     "$ssh_target" true; then
  ssh_auth="key"
  echo "SSH key berhasil."
  read -r -s -p "Password sudo untuk $ssh_user: " sudo_password
  echo
else
  echo "SSH key tidak tersedia atau gagal; menggunakan password SSH."
  command -v sshpass >/dev/null 2>&1 || {
    echo "ERROR: sshpass belum terpasang."
    echo "Debian/Ubuntu/Kali: sudo apt install sshpass"
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

  if ! sshpass -f "$auth_file" ssh \
      -o PreferredAuthentications=password,keyboard-interactive \
      -o PubkeyAuthentication=no \
      -o ConnectTimeout=8 \
      "$ssh_target" true; then
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

inventory_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-redis-inventory.XXXXXX.yml")"
chmod 600 "$inventory_file"
cat > "$inventory_file" <<INVENTORY_EOF
---
all:
  children:
    redis_servers:
      hosts:
        redis01:
          ansible_host: "$server"
          ansible_user: "$ssh_user"
INVENTORY_EOF

secret_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-redis-vars.XXXXXX")"
chmod 600 "$secret_file"

# Pass secrets to Python over stdin, not as command-line arguments or env vars.
printf '%s\0%s\0%s\0%s\0%s' \
  "$ssh_password" "$sudo_password" "$redis_password" "$redis_port" "$redis_bind_address" |
python -c '
import json, sys
ssh_password, sudo_password, redis_password, redis_port, redis_bind_address = (
    value.decode() for value in sys.stdin.buffer.read().split(b"\0")
)
data = {
    "ansible_become_password": sudo_password,
    "redis_port": int(redis_port),
    "redis_bind_address": redis_bind_address,
    "redis_password": redis_password,
}
if ssh_password:
    data["ansible_password"] = ssh_password
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
' "$secret_file"

unset ssh_password sudo_password redis_password

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
echo "Memulai instalasi Redis pada $server ..."
"$ANSIBLE_PLAYBOOK" \
  -i "$inventory_file" \
  "$PLAYBOOK" \
  --extra-vars "@$secret_file" \
  "${ansible_args[@]}"

echo
echo "Selesai. Redis sudah diverifikasi oleh playbook."
