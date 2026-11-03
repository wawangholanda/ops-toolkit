#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

PLAYBOOK="ansible/playbooks/postgresql-refresh-dev.yml"
ANSIBLE_PLAYBOOK="${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/ansible-playbook}"
ssh_password=""
sudo_password=""
source_password=""
auth_file=""
secret_file=""
inventory_file=""

cleanup() {
  rm -f -- "${auth_file:-}" "${secret_file:-}" "${inventory_file:-}"
  unset ssh_password sudo_password source_password app_password
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

valid_identifier() {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]{0,62}$ ]]
}
valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

echo "=== Refresh Development PostgreSQL from Production ==="
echo
echo "Sumber production hanya dibaca. Tidak ada perubahan atau cutover ke RDS."
echo

read -r -p "RDS endpoint/hostname: " source_host
read -r -p "RDS port [5432]: " source_port
source_port="${source_port:-5432}"
read -r -p "Nama database production: " source_database
read -r -p "Username database RDS: " source_username
read -r -s -p "Password database RDS: " source_password
echo

read -r -p "IP/hostname server PostgreSQL development: " target_server
read -r -p "Username SSH server development: " ssh_user
read -r -p "Port PostgreSQL development [5432]: " target_port
target_port="${target_port:-5432}"
read -r -p "Nama database development [${source_database}]: " target_database
target_database="${target_database:-$source_database}"
read -r -p "Owner database development [postgres]: " target_owner
target_owner="${target_owner:-postgres}"
read -r -p "Username application Development: " app_username
read -r -s -p "Password application Development (minimal 16 karakter): " app_password
echo

[[ -n "$source_host" && -n "$source_username" && -n "$source_password" &&
   -n "$target_server" && -n "$ssh_user" && -n "$app_username" && -n "$app_password" ]] || {
  echo "ERROR: Semua field koneksi wajib diisi."
  exit 1
}
valid_identifier "$source_database" || {
  echo "ERROR: Nama database production tidak valid."
  exit 1
}
valid_identifier "$target_database" || {
  echo "ERROR: Nama database development tidak valid."
  exit 1
}
valid_identifier "$target_owner" || {
  echo "ERROR: Nama owner database tidak valid."
  exit 1
}
valid_identifier "$app_username" || {
  echo "ERROR: Username application tidak valid."
  exit 1
}
[[ "${#app_password}" -ge 16 ]] || {
  echo "ERROR: Password application minimal 16 karakter."
  exit 1
}
[[ "$app_username" != "$target_owner" ]] || {
  echo "ERROR: Application user harus berbeda dari database owner agar hak aksesnya tetap terpisah."
  exit 1
}
valid_port "$source_port" && valid_port "$target_port" || {
  echo "ERROR: Port harus berupa angka antara 1 dan 65535."
  exit 1
}
if [[ ! "$source_host" =~ ^[a-zA-Z0-9.-]+$ ||
      ! "$target_server" =~ ^[a-zA-Z0-9._:-]+$ ||
      ! "$ssh_user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: Format hostname, server, atau username tidak valid."
  exit 1
fi

echo
echo "Ringkasan:"
echo "  Source : $source_database @ $source_host:$source_port (RDS)"
echo "  Target : $target_database @ $target_server:$target_port"
echo "  Owner  : $target_owner"
echo "  App user: $app_username"
echo "  App password: akan digunakan hanya jika role belum ada; password role existing tidak diubah."
echo
echo "Catatan:"
echo "- Versi RDS akan dideteksi otomatis; PostgreSQL server/client yang sesuai akan disiapkan pada Development."
echo "- Versi PostgreSQL lain yang sudah terpasang tidak akan dihapus otomatis."
echo "- Server development harus dapat menjangkau endpoint RDS pada port $source_port."
echo "- Security Group RDS harus mengizinkan koneksi dari server development."
echo "- SSL RDS menggunakan sslmode=require."
echo "- Restore menggunakan --no-owner dan --no-acl; object akan dimiliki target owner."
echo "- Pastikan extension yang dipakai production tersedia pada server development."
echo
read -r -p "Database development sudah ada? Timpa database tersebut? Ketik REPLACE untuk mengizinkan: " overwrite_confirm
overwrite_target=false
if [[ "$overwrite_confirm" == "REPLACE" ]]; then
  overwrite_target=true
fi

echo
read -r -p "Lanjutkan proses refresh? [y/N] " confirm
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

ssh_target="$ssh_user@$target_server"
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
    echo "ERROR: sshpass belum terpasang. Debian/Ubuntu/Kali: sudo apt install sshpass"
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
  sshpass -f "$auth_file" ssh -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o ConnectTimeout=8 "$ssh_target" true || {
    echo "ERROR: Login SSH gagal."
    exit 1
  }
  sudo_password="$ssh_password"
fi

[[ -n "$sudo_password" ]] || {
  echo "ERROR: Password sudo tidak boleh kosong."
  exit 1
}

inventory_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-pg-refresh-inventory.XXXXXX.yml")"
chmod 600 "$inventory_file"
cat > "$inventory_file" <<INVENTORY_EOF
---
all:
  children:
    postgresql_refresh_targets:
      hosts:
        postgresql_dev:
          ansible_host: "$target_server"
          ansible_user: "$ssh_user"
INVENTORY_EOF

secret_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-pg-refresh-vars.XXXXXX")"
chmod 600 "$secret_file"
printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s' \
  "$ssh_password" "$sudo_password" "$source_host" "$source_port" \
  "$source_database" "$source_username" "$source_password" \
  "$target_port" "$target_database" "$target_owner" "$overwrite_target" |
python -c '
import json, sys
values = [v.decode() for v in sys.stdin.buffer.read().split(b"\0")]
(ssh_password, sudo_password, source_host, source_port, source_db,
 source_user, source_password, target_port, target_db, target_owner,
 overwrite_target, app_username, app_password) = values
data = {
    "ansible_become_password": sudo_password,
    "postgresql_refresh_source_host": source_host,
    "postgresql_refresh_source_port": int(source_port),
    "postgresql_refresh_source_database": source_db,
    "postgresql_refresh_source_username": source_user,
    "postgresql_refresh_source_password": source_password,
    "postgresql_refresh_target_port": int(target_port),
    "postgresql_refresh_target_database": target_db,
    "postgresql_refresh_target_owner": target_owner,
    "postgresql_refresh_overwrite_target": overwrite_target == "true",
    "postgresql_refresh_app_username": app_username,
    "postgresql_refresh_app_password": app_password,
}
if ssh_password:
    data["ansible_password"] = ssh_password
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
' "$secret_file"

unset ssh_password sudo_password source_password

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
echo "Menjalankan refresh. Dump sementara dibuat di server development dan dihapus setelah proses."
"$ANSIBLE_PLAYBOOK" -i "$inventory_file" "$PLAYBOOK" --extra-vars "@$secret_file" "${ansible_args[@]}"

echo
echo "Refresh selesai. Periksa hasil validasi dan lakukan masking data sensitif sebelum database dipakai developer."
