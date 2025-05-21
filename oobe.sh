#!/bin/bash

# https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro#add-the-wsl-distribution-configuration-file

DEFAULT_UID=1000

set -ue
set -o pipefail

# =========================
# Logging and Environment
# =========================

log() {
	echo "[OOBE] $*" >&2
}

# Check for required external commands
for cmd in openssl chpasswd; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		log "Required command '$cmd' not found. Please log an issue on bugs.gentoo.org."
		exit 97
	fi
done

# Enforce bash
if [[ -z "$BASH_VERSION" ]]; then
	log "This script requires bash."
	exit 99
fi

groups=(users wheel)

# Validate required groups exist
for grp in "${groups[@]}"; do
	if ! getent group "$grp" > /dev/null; then
		log "Required group '$grp' does not exist. This is probably a bug."
		echo "Please report this issue to the Gentoo WSL team."
		exit 98
	fi
done

# Trap to unset sensitive variables on exit
trap 'unset password password2 username' EXIT

# =========================
# Helper Functions
# =========================

shake_salt() {
	LC_ALL=C < /dev/urandom tr -dc 'A-Za-z0-9./' | head -c16
}

hashpw() {
	local salt plain_password
	plain_password="$1"
	salt=$(shake_salt)
	if [[ -z "$salt" ]]; then
		echo "Failed to generate salt."
		return 1
	fi
	openssl passwd -6 -salt "$salt" "$plain_password"
}

is_hash_like() {
	[[ "$1" =~ ^\$6\$[A-Za-z0-9./]+\$[A-Za-z0-9./]{43,}$ ]]
}

maybe_run() {
	if [[ -n "$DEBUG_OOBE" ]]; then
		echo "[DEBUG] Would run:" "$@"
	else
		"$@"
	fi
}

show_install_tips() {
	local mode="${1:-}"
	cat <<-EOF

		OOBE complete!${mode}

		Installation Tips:
			- Use 'emerge --sync' to sync the portage tree (as root).
			- Use 'emerge -uDN @world' to update the system (as root).
			- Read the Gentoo Handbook for more information:
				https://wiki.gentoo.org/wiki/Handbook:Main_Page
			- Consider using the binary package host (binhost) and only compiling
			  packages where you want to change the USE flags.
			  This can save time and resources. See:
				https://wiki.gentoo.org/wiki/Gentoo_Binary_Host_Quickstart
			- For privilege escalation helpers:
				su -c 'emerge app-admin/sudo'
				su -c 'emerge app-admin/doas'

		Resources:
			Gentoo Forums:        https://forums.gentoo.org/
			Gentoo IRC:           https://web.libera.chat/#gentoo
			Gentoo Wiki:          https://wiki.gentoo.org/
			Gentoo in WSL:        https://wiki.gentoo.org/wiki/Gentoo_in_WSL
	EOF
}

user_exists_by_uid() {
	getent passwd "$1" > /dev/null
}

user_exists_by_name() {
	id -u "$1" >/dev/null 2>&1
}

validate_username() {
	local username="$1"
	# POSIX username: start with [a-z_], then [a-z0-9_-]{0,30}, optionally ending with $
	if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,30}\$?$ ]]; then
		echo "Username must start with a letter or underscore and contain only lowercase letters, digits, underscores, or dashes." >&2
		return 1
	fi
	if [[ -z "$username" ]]; then
		echo "Username cannot be empty."
		return 1
	fi
	if [[ "$username" =~ [[:space:]] ]]; then
		echo "Username cannot contain spaces."
		return 1
	fi
	if [[ "$username" == "root" ]]; then
		echo "Cannot use 'root' as username."
		return 1
	fi
	if user_exists_by_name "$username"; then
		echo "User '$username' already exists."
		return 1
	fi
	return 0
}

prompt_password() {
	local username="$1"
	local password password2

	tty_echo() { echo "$@" > /dev/tty; }

	while true; do
		read -r -s -p "Enter password for $username: " password < /dev/tty
		tty_echo
		if [[ -z "$password" ]]; then
			tty_echo "Password cannot be empty."
			continue
		fi

		if command -v pwqcheck >/dev/null 2>&1; then
			result=$(echo "$password" | pwqcheck -1 2>&1 | tr -d '\r\n')
			if [[ "$result" != "OK" ]]; then
				tty_echo "Password complexity check failed: $result"
				tty_echo "Please try again."
				sleep 1
				continue
			fi
		else
			tty_echo "Warning: Password complexity check (pwqcheck) not available. Proceeding without it."
		fi

		read -r -s -p "Confirm password: " password2 < /dev/tty
		tty_echo
		if [[ "$password" != "$password2" ]]; then
			tty_echo "Passwords do not match."
			continue
		fi

		echo "$password"
		password=""; password2=""
		unset password password2
		return 0
	done
}

# =========================
# Banner and Info
# =========================

head /etc/issue.logo

echo "Welcome to Gentoo Linux ($(uname -m)) on Windows Subsystem for Linux (WSL)!"
echo
echo 'Please create a default UNIX user account. The username does not need to match your Windows username.'
echo 'For more information visit: https://aka.ms/wslusers'

# =========================
# Main Logic
# =========================

DEBUG_OOBE="${DEBUG_OOBE:-}"

if [[ -n "$DEBUG_OOBE" ]]; then
	echo "DEBUG_OOBE is set: Skipping user_exists_by_uid check and system modifications."
fi

if [[ -z "$DEBUG_OOBE" ]]; then
	if user_exists_by_uid "$DEFAULT_UID"; then
		echo 'User account already exists, skipping creation'
		exit 0
	fi
fi

main_oobe_loop() {
	local username password user_hash root_hash
	local chpasswd_user_status chpasswd_root_status
	while true; do
		read -p 'Enter new UNIX username: ' username
		validate_username "$username" || continue
		read -p "Create user '$username'? [y/N]: " confirm
		if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
			echo "Aborted."
			exit 1
		fi
		password=$(prompt_password "$username")

		maybe_run /usr/sbin/useradd -m -u "$DEFAULT_UID" \
			-s /bin/bash -c '' \
			-G "$(IFS=,; echo "${groups[*]}")" \
			"$username"
		if [[ $? == 0 || -n "$DEBUG_OOBE" ]]; then
			user_hash=$(hashpw "$password")
			root_hash=$(hashpw "$password")

			if ! is_hash_like "$user_hash"; then
				log "ERROR: Generated user password hash does not look valid: $user_hash"
				maybe_run userdel -r "$username"
				exit 1
			fi
			if ! is_hash_like "$root_hash"; then
				log "ERROR: Generated root password hash does not look valid: $root_hash"
				maybe_run userdel -r "$username"
				exit 1
			fi

			printf '%s:%s\n' "$username" "$user_hash" | maybe_run chpasswd -e
			chpasswd_user_status=$?

			printf '%s:%s\n' "root" "$root_hash" | maybe_run chpasswd -e
			chpasswd_root_status=$?

			if [[ -n "$DEBUG_OOBE" ]]; then
				log "Debug: user chpasswd exit status: $chpasswd_user_status"
				log "Debug: root chpasswd exit status: $chpasswd_root_status"
			fi

			if [[ $chpasswd_user_status -ne 0 && $chpasswd_root_status -ne 0 ]]; then
				log "ERROR: Failed to set passwords for both user '$username' and root."
				log "Cleaning up user '$username'."
				maybe_run userdel -r "$username"
				exit 1
			elif [[ $chpasswd_user_status -ne 0 ]]; then
				log "ERROR: Failed to set password for user '$username', but root password was set."
				log "Cleaning up user '$username'."
				maybe_run userdel -r "$username"
				exit 1
			elif [[ $chpasswd_root_status -ne 0 ]]; then
				log "ERROR: Failed to set password for root, but user '$username' password was set."
				log "Cleaning up user '$username'."
				maybe_run userdel -r "$username"
				exit 1
			fi

			if [[ -n "$DEBUG_OOBE" ]]; then
				echo
				echo "[DEBUG] OOBE complete! No changes made."
				show_install_tips " (DEBUG MODE)"
				echo
				break
			else
				echo "User '$username' created successfully."
				echo "Setting root password to match the new user password."
				echo "Root password set. You can now use 'su' to become root."
				echo
				show_install_tips
				echo
				break
			fi
		else
			echo "Failed to create user. See error above."
		fi
	done
}

main_oobe_loop
