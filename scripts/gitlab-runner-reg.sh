#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

INVENTORY="ansible/inventory/dev/hosts.yml"
PLAYBOOK="ansible/playbooks/gitlab-runner.yml"
ANSIBLE_PLAYBOOK="${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/ansible-playbook}"

if [[ -z "${VIRTUAL_ENV:-}" || ! -x "$ANSIBLE_PLAYBOOK" ]]; then
  echo "ERROR: Aktifkan virtual environment yang berisi Ansible."
  echo "Contoh: source ../.venv/bin/activate"
  exit 1
fi

for cmd in ssh python mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERROR: Perintah '$cmd' tidak ditemukan."
    exit 1
  }
done

echo "=== GitLab Runner Quick Start ==="
echo

if [[ -f "$INVENTORY" ]]; then
  echo "Inventory lokal sudah ada: $INVENTORY"
  read -r -p "Timpa inventory lokal tersebut? [y/N] " overwrite
  [[ "$overwrite" =~ ^[Yy]$ ]] || exit 0
fi

read -r -p "IP atau hostname server Runner: " server
read -r -p "Username SSH: " ssh_user

[[ -n "$server" && -n "$ssh_user" ]] || {
  echo "ERROR: IP/hostname dan username SSH wajib diisi."
  exit 1
}

if [[ "$server" == "192.0.2."* ||
      "$server" == "198.51.100."* ||
      "$server" == "203.0.113."* ]]; then
  echo "ERROR: IP dokumentasi tidak boleh digunakan sebagai target."
  exit 1
fi

echo
echo "Pilih executor:"
echo "  1) Docker (default)"
echo "  2) Shell"
read -r -p "Pilihan [1]: " choice
case "${choice:-1}" in
  1) executor="docker" ;;
  2) executor="shell" ;;
  *) echo "ERROR: Pilihan executor tidak valid."; exit 1 ;;
esac

echo
read -r -p "Nama runner: " runner_name
[[ -n "$runner_name" ]] || {
  echo "ERROR: Nama runner wajib diisi."
  exit 1
}

read -r -p "Tag runner (pisahkan dengan koma): " runner_tags_input
[[ -n "$runner_tags_input" ]] || {
  echo "ERROR: Minimal satu tag runner wajib diisi."
  exit 1
}

echo
read -r -p "URL GitLab [https://gitlab.com]: " gitlab_url
gitlab_url="${gitlab_url:-https://gitlab.com}"

if [[ ! "$gitlab_url" =~ ^https://[^/]+/?$ ]]; then
  echo "ERROR: Gunakan URL dasar HTTPS, misalnya https://gitlab.com"
  exit 1
fi

echo "Buat Runner di GitLab terlebih dahulu, lalu masukkan authentication token."
read -r -s -p "GitLab Runner authentication token: " gitlab_token
echo

[[ -n "$gitlab_token" ]] || {
  echo "ERROR: Token tidak boleh kosong."
  exit 1
}

echo
echo "Target : $ssh_user@$server"
echo "Executor: $executor"
echo "GitLab : $gitlab_url"
read -r -p "Lanjutkan? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || {
  unset gitlab_token
  echo "Dibatalkan."
  exit 0
}

mkdir -p "$(dirname "$INVENTORY")"

# Inventory lokal diabaikan oleh Git dan dibatasi hanya untuk pemilik file.
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
chmod 600 "$INVENTORY"

echo
echo "Memeriksa SSH: mencoba ~/.ssh/id_rsa terlebih dahulu..."
ssh_target="$ssh_user@$server"
ssh_auth="key"
ssh_password=""
sudo_password=""
auth_file=""

cleanup() {
  rm -f -- "${secret_file:-}" "${auth_file:-}"
  unset gitlab_token ssh_password sudo_password
}
trap cleanup EXIT INT TERM

if [[ -f "$HOME/.ssh/id_rsa" ]] &&
   ssh -i "$HOME/.ssh/id_rsa" \
       -o IdentitiesOnly=yes \
       -o BatchMode=yes \
       -o ConnectTimeout=8 \
       "$ssh_target" true; then
  echo "SSH key berhasil."
  read -r -s -p "Password sudo untuk $ssh_user: " sudo_password
  echo
else
  echo "SSH key tidak berhasil; menggunakan password SSH."

  if ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: sshpass belum terpasang."
    echo "Debian/Ubuntu/Kali: sudo apt install sshpass"
    exit 1
  fi

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
  echo "Login SSH berhasil."
fi

[[ -n "$sudo_password" ]] || {
  echo "ERROR: Password sudo tidak boleh kosong."
  exit 1
}

if [[ "$ssh_auth" == "password" ]] &&
   ! command -v sshpass >/dev/null 2>&1; then
  echo
  echo "Password SSH memerlukan sshpass untuk Ansible."

  case "$(uname -s)" in
    Darwin)
      echo "macOS:"
      echo "  brew install hudochenkov/sshpass/sshpass"
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        echo "Debian/Ubuntu/Kali:"
        echo "  sudo apt update && sudo apt install -y sshpass"
      elif command -v dnf >/dev/null 2>&1; then
        echo "Fedora/RHEL:"
        echo "  sudo dnf install sshpass"
      elif command -v pacman >/dev/null 2>&1; then
        echo "Arch Linux:"
        echo "  sudo pacman -S sshpass"
      elif command -v zypper >/dev/null 2>&1; then
        echo "openSUSE:"
        echo "  sudo zypper install sshpass"
      else
        echo "Pasang sshpass menggunakan package manager distribusimu."
      fi
      ;;
    *)
      echo "Pasang sshpass secara manual untuk OS ini."
      ;;
  esac

  unset gitlab_token
  echo "Instal dependensi tersebut, lalu jalankan quick-start kembali."
  exit 1
fi

# Rahasia hanya berada di file sementara berizin 0600, bukan inventory atau Git.
secret_file="$(mktemp "${TMPDIR:-/tmp}/mydevops-runner-vars.XXXXXX")"
chmod 600 "$secret_file"


# Kirim rahasia melalui stdin, bukan argumen proses atau environment variable.
printf '%s\0%s\0%s\0%s\0%s\0%s\0%s' \
  "$gitlab_url" "$gitlab_token" "$executor" "$runner_name" \
  "$runner_tags_input" "$ssh_password" "$sudo_password" |
python -c '
import json, sys
url, token, executor, runner_name, tags_input, ssh_password, sudo_password = (
    sys.stdin.buffer.read().split(b"\0")
)
tags = [tag.strip() for tag in tags_input.decode().split(",") if tag.strip()]
if not tags:
    raise SystemExit("Minimal satu tag runner wajib diisi.")
data = {
    "gitlab_runner_gitlab_url": url.decode(),
    "gitlab_runner_auth_token": token.decode(),
    "gitlab_runner_executor": executor.decode(),
    "gitlab_runner_name": runner_name.decode(),
    "gitlab_runner_install_docker": executor == b"docker",
    "gitlab_runner_tags": tags,
    "ansible_become_password": sudo_password.decode(),
}
if ssh_password:
    data["ansible_password"] = ssh_password.decode()

with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(data, f)
    f.write("\n")
' "$secret_file"

unset gitlab_token

echo
echo "Memeriksa sintaks playbook..."
"$ANSIBLE_PLAYBOOK" -i "$INVENTORY" "$PLAYBOOK" --syntax-check

echo
echo "Memulai instalasi GitLab Runner."
echo "Password SSH dan sudo sudah disiapkan untuk Ansible."
echo

"$ANSIBLE_PLAYBOOK" \
  -i "$INVENTORY" \
  "$PLAYBOOK" \
  --extra-vars "@$secret_file"

echo
echo "Playbook selesai. Periksa hasil task di atas untuk memastikan Runner terdaftar."
