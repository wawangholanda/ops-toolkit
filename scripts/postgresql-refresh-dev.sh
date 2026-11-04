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
defaults_file=""
config_parent="${XDG_CONFIG_HOME:-$HOME/.config}/ops-toolkit"
config_dir="$config_parent/postgresql-refresh-dev"
config_file="$config_dir/config.json"

cleanup() {
  rm -f -- "${auth_file:-}" "${secret_file:-}" "${inventory_file:-}" "${defaults_file:-}"
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

case "${1:-}" in
  "")
    ;;
  --reset-config)
    if [[ -L "$config_parent" || -L "$config_dir" ]]; then
      echo "ERROR: Config directory adalah symbolic link; tidak dihapus."
      exit 1
    fi
    if [[ -L "$config_file" ]]; then
      echo "ERROR: Config path adalah symbolic link; tidak dihapus."
      exit 1
    fi
    rm -f -- "$config_file"
    echo "Konfigurasi tersimpan direset. Nilai berikutnya akan diminta ulang."
    ;;
  --help|-h)
    echo "Usage: bash scripts/postgresql-refresh-dev.sh [--reset-config]"
    echo "  --reset-config  Hapus konfigurasi non-rahasia yang tersimpan, lalu mulai dari awal."
    exit 0
    ;;
  *)
    echo "ERROR: Argumen tidak dikenal: $1"
    echo "Usage: bash scripts/postgresql-refresh-dev.sh [--reset-config]"
    exit 1
    ;;
esac

if [[ -L "$config_parent" || -L "$config_dir" ]]; then
  echo "ERROR: Config directory tidak boleh berupa symbolic link."
  exit 1
fi
mkdir -p -- "$config_dir"
if [[ -L "$config_parent" || -L "$config_dir" ]]; then
  echo "ERROR: Config directory tidak boleh berupa symbolic link."
  exit 1
fi
chmod 700 "$config_dir"
if [[ -L "$config_file" ]]; then
  echo "ERROR: Config file tidak boleh berupa symbolic link."
  exit 1
fi

defaults_file="$(mktemp "${TMPDIR:-/tmp}/ops-toolkit-pg-refresh-defaults.XXXXXX")"
chmod 600 "$defaults_file"
if ! python - "$config_file" > "$defaults_file" <<'PY'
import json
import os
import sys

path = sys.argv[1]
keys = [
    "source_host", "source_port", "source_database", "source_username",
    "target_server", "ssh_user", "target_port", "target_database",
    "target_owner", "app_username", "listen_address", "app_client_cidr",
    "ssh_key_path",
]
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as handle:
            loaded = json.load(handle)
        if not isinstance(loaded, dict) or loaded.get("schema_version") != 1:
            raise ValueError("unsupported configuration format")
        data = loaded
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: Konfigurasi tersimpan tidak valid: {exc}", file=sys.stderr)
        print("Periksa file atau jalankan dengan --reset-config.", file=sys.stderr)
        raise SystemExit(1)

for key in keys:
    value = data.get(key, "")
    if not isinstance(value, str) or "\0" in value:
        print(f"ERROR: Nilai konfigurasi '{key}' tidak valid.", file=sys.stderr)
        raise SystemExit(1)
    sys.stdout.buffer.write(value.encode("utf-8") + b"\0")
PY
then
  exit 1
fi
chmod 600 "$config_file" 2>/dev/null || true
mapfile -d '' -t saved_config < "$defaults_file"

source_host_default="${saved_config[0]:-}"
source_port_default="${saved_config[1]:-5432}"
source_database_default="${saved_config[2]:-}"
source_username_default="${saved_config[3]:-}"
target_server_default="${saved_config[4]:-}"
ssh_user_default="${saved_config[5]:-}"
target_port_default="${saved_config[6]:-5432}"
target_database_default="${saved_config[7]:-}"
target_owner_default="${saved_config[8]:-postgres}"
app_username_default="${saved_config[9]:-}"
listen_address_default="${saved_config[10]:-localhost}"
app_client_cidr_default="${saved_config[11]:-}"
ssh_key_path_default="${saved_config[12]:-~/.ssh/id_rsa}"

prompt_with_default() {
  local variable_name="$1"
  local prompt="$2"
  local default_value="$3"
  local answer
  read -r -p "$prompt [$default_value]: " answer
  printf -v "$variable_name" '%s' "${answer:-$default_value}"
}

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

prompt_with_default source_host "RDS endpoint/hostname" "$source_host_default"
prompt_with_default source_port "RDS port" "$source_port_default"
prompt_with_default source_database "Nama database production" "$source_database_default"
prompt_with_default source_username "Username database RDS" "$source_username_default"
read -r -s -p "Password database RDS (tidak disimpan): " source_password
echo

prompt_with_default target_server "IP/hostname server PostgreSQL development" "$target_server_default"
prompt_with_default ssh_user "Username SSH server development" "$ssh_user_default"
prompt_with_default target_port "Port PostgreSQL development" "$target_port_default"
prompt_with_default target_database "Nama database development" "${target_database_default:-$source_database}"
prompt_with_default target_owner "Owner database development" "$target_owner_default"
prompt_with_default app_username "Username application Development" "$app_username_default"
read -r -s -p "Password application Development (tidak disimpan; dipakai hanya jika role belum ada; minimal 16 karakter): " app_password
echo
prompt_with_default listen_address "PostgreSQL listen address (localhost untuk akses lokal)" "$listen_address_default"
read -r -p "CIDR sumber aplikasi [${app_client_cidr_default:-kosong}] (ketik 'none' untuk akses lokal saja): " app_client_cidr_input
if [[ "$app_client_cidr_input" == "none" ]]; then
  app_client_cidr=""
else
  app_client_cidr="${app_client_cidr_input:-$app_client_cidr_default}"
fi

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
if [[ -n "$app_client_cidr" ]]; then
  python - "$app_client_cidr" "$listen_address" <<'PY'
import ipaddress
import sys
try:
    network = ipaddress.ip_network(sys.argv[1], strict=False)
    address = ipaddress.ip_address(sys.argv[2])
    if network.version != 4 or address.version != 4:
        raise ValueError("IPv4 only")
    if address.is_loopback or address.is_unspecified or network.prefixlen == 0:
        raise ValueError("Use a specific non-loopback server IP and a non-default CIDR")
except ValueError:
    print("ERROR: CIDR dan listen address harus IPv4 yang valid.")
    raise SystemExit(1)
PY
  [[ "$listen_address" != "localhost" && "$listen_address" != "*" ]] || {
    echo "ERROR: Untuk akses remote, masukkan IP interface server, bukan localhost atau *."
    exit 1
  }
else
  [[ "$listen_address" == "localhost" ]] || {
    echo "ERROR: Listen address non-local membutuhkan CIDR sumber aplikasi."
    exit 1
  }
fi
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
echo "  App network: ${app_client_cidr:-local only}"
echo "  Listen address: $listen_address"
echo "  App password: hanya digunakan jika role belum ada; password role existing tidak diubah."
echo
echo "Catatan:"
echo "- Versi RDS akan dideteksi otomatis; PostgreSQL server/client yang sesuai akan disiapkan pada Development."
echo "- Versi PostgreSQL lain yang sudah terpasang tidak akan dihapus otomatis."
echo "- Server development harus dapat menjangkau endpoint RDS pada port $source_port."
echo "- Security Group RDS harus mengizinkan koneksi dari server development."
echo "- Akses aplikasi remote hanya dibuka untuk CIDR yang dimasukkan; firewall/security group Development tetap perlu diatur manual."
echo "- SSL RDS menggunakan sslmode=require."
echo "- Restore menggunakan --no-owner dan --no-acl; object dimiliki OS role postgres, sedangkan database dimiliki target owner."
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

read -r -p "Path private SSH key [$ssh_key_path_default]: " ssh_key_path
ssh_key_path="${ssh_key_path:-$ssh_key_path_default}"
if [[ "$ssh_key_path" == "~" ]]; then
  ssh_key_path="$HOME"
elif [[ "$ssh_key_path" == "~/"* ]]; then
  ssh_key_path="$HOME/${ssh_key_path#~/}"
fi

printf '%s\0' \
  "$source_host" "$source_port" "$source_database" "$source_username" \
  "$target_server" "$ssh_user" "$target_port" "$target_database" \
  "$target_owner" "$app_username" "$listen_address" "$app_client_cidr" \
  "$ssh_key_path" |
python -c '
import json
import os
import sys
import tempfile

keys = [
    "source_host", "source_port", "source_database", "source_username",
    "target_server", "ssh_user", "target_port", "target_database",
    "target_owner", "app_username", "listen_address", "app_client_cidr",
    "ssh_key_path",
]
raw_values = sys.stdin.buffer.read().split(b"\0")
if raw_values and raw_values[-1] == b"":
    raw_values.pop()
values = [item.decode("utf-8") for item in raw_values]
if len(values) != len(keys):
    raise SystemExit("ERROR: Jumlah nilai konfigurasi tidak sesuai.")
data = {"schema_version": 1, **dict(zip(keys, values))}
directory = os.path.dirname(sys.argv[1])
fd, temporary_path = tempfile.mkstemp(prefix=".config.", dir=directory, text=True)
try:
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    os.replace(temporary_path, sys.argv[1])
    os.chmod(sys.argv[1], 0o600)
except Exception:
    try:
        os.unlink(temporary_path)
    except FileNotFoundError:
        pass
    raise
' "$config_file"

echo "Konfigurasi non-rahasia tersimpan di: $config_file"

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
printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s' \
  "$ssh_password" "$sudo_password" "$source_host" "$source_port" \
  "$source_database" "$source_username" "$source_password" \
  "$target_port" "$target_database" "$target_owner" "$overwrite_target" \
  "$app_username" "$app_password" "$listen_address" "$app_client_cidr" |
python -c '
import json, sys
values = [v.decode() for v in sys.stdin.buffer.read().split(b"\0")]
(ssh_password, sudo_password, source_host, source_port, source_db,
 source_user, source_password, target_port, target_db, target_owner,
 overwrite_target, app_username, app_password, listen_address, app_client_cidr) = values
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
    "postgresql_refresh_listen_addresses": listen_address,
    "postgresql_refresh_app_client_cidr": app_client_cidr,
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
