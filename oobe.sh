#!/bin/bash
# OOBE Script for Gentoo Linux on WSL
# This script is run during the first launch of the Gentoo WSL distribution.
# It sets up a user account and configures the root password.
# https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro#add-the-wsl-distribution-configuration-file

DEFAULT_UID=1000

set -ue
set -o pipefail

# =========================
# Logging and Environment
# =========================

export LC_ALL=C # Useful for hashes, required for eselect repository

edebug() {
	if [[ -n "$DEBUG_OOBE" ]]; then
		echo -e " \033[35;1m*\033[0m [DEBUG] $*" >&2
	fi
}

einfo() {
	echo -e " \033[32;1m*\033[0m $*"
}

ewarn() {
	echo -e " \033[33;1m*\033[0m $*"
}

eerror() {
	echo -e " \033[31;1m*\033[0m $*" >&2
}

die() {
	eerror "\033[31;1m!!!\033[0m $*"
	exit 1
}

report_bug() {
	exit_code="$1"
	if [[ -z "$exit_code" ]]; then
		exit_code=1
	fi
	eerror "Please report this issue to the Gentoo WSL Project on bugs.gentoo.org."
	exit "$exit_code"
}

# Check for required external commands
for cmd in chpasswd getuto openssl; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		eerror "Required command '$cmd' not found."
		report_bug 97
	fi
done

# Enforce bash
if [[ -z "$BASH_VERSION" ]]; then
	eerror "This script requires bash."
	exit 99
fi

# Default groups for the new user account
# users: standard user group, wheel: allows sudo/su access
groups=(users wheel)

# Validate required groups exist
for grp in "${groups[@]}"; do
	if ! getent group "$grp" > /dev/null; then
		eerror "Required group '$grp' does not exist. This is probably a bug."
		report_bug 98
	fi
done

# Trap to unset sensitive variables on exit
trap 'unset password password2 username user_hash root_hash' EXIT

# =========================
# Helper Functions
# =========================

check_network_connectivity() {
	local test_hosts=("1.1.1.1" "8.8.8.8" "9.9.9.9" "www.gentoo.org")
	local timeout=5

	edebug "Checking network connectivity..."

	for host in "${test_hosts[@]}"; do
		if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
			edebug "Network connectivity confirmed via $host"
			return 0
		fi
	done

	edebug "Network connectivity check failed for all test hosts"
	return 1
}

shake_salt() {
	< /dev/urandom tr -dc 'A-Za-z0-9./' | head -c16
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

# Validate SHA-512 password hash format: $6$salt$hash
# $6$ = SHA-512, followed by base64-encoded salt and 43+ char hash
is_hash_like() {
	[[ "$1" =~ ^\$6\$[A-Za-z0-9./]+\$[A-Za-z0-9./]{43,}$ ]]
}

# Clear sensitive variables from memory
clear_sensitive_vars() {
	local -a vars_to_clear=("$@")
	for var in "${vars_to_clear[@]}"; do
		printf -v "$var" ''
		unset "$var"
	done
}

maybe_run() {
	if [[ -n "$DEBUG_OOBE" ]]; then
		edebug "Would run:" "$@"
	else
		"$@"
	fi
}

maybe_run_quiet() {
	if [[ -n "$DEBUG_OOBE" ]]; then
		edebug "Would run (quiet):" "$@"
	else
		"$@" >/dev/null 2>&1
	fi
}

show_install_tips() {
	local mode
	if [[ -n "$DEBUG_OOBE" ]]; then
		mode="(DEBUG mode)"
	else
		mode=""
	fi
	if [[ -n "$mode" ]]; then
		mode=" $mode"
	fi
	cat <<-EOF

		OOBE complete!${mode}

		Installation Tips:
		    - Elevate privileges to root using 'su' until you set up sudo or doas.
		    - Use 'emerge --sync' to sync the portage tree (as root).
		      + 'emerge-webrsync' is a good alternative for systems with restricted network access.
		    - Use 'emerge -uDNav @world' to update the system (as root).
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
	# POSIX username validation: start with [a-z_], then [a-z0-9_-]{0,30}, optionally ending with $
	# This ensures compatibility across Unix-like systems (mostly matches shadow-utils, systemd style)
	if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,30}\$?$ ]]; then
		eerror "Username must start with a letter or underscore and contain only lowercase letters, digits, underscores, or dashes." >&2
		return 1
	fi
	if [[ -z "$username" ]]; then
		eerror "Username cannot be empty."
		return 1
	fi
	if [[ "$username" =~ [[:space:]] ]]; then
		eerror "Username cannot contain spaces."
		return 1
	fi
	if [[ "$username" == "root" ]]; then
		eerror "Cannot use 'root' as username."
		return 1
	fi
	if user_exists_by_name "$username"; then
		eerror "User '$username' already exists."
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
		clear_sensitive_vars password password2
		return 0
	done
}


mask_systemd_units() {
	# https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro#systemd-recommendations
	local known_bad_units=(
		NetworkManager.service
		systemd-networkd.service
		systemd-networkd.socket
		systemd-resolved.service
		systemd-tmpfiles-clean.service
		systemd-tmpfiles-clean.timer
		systemd-tmpfiles-setup-dev-early.service
		systemd-tmpfiles-setup-dev.service
		systemd-tmpfiles-setup.service
		tmp.mount
	)

	# systemctl mask will make a symlink to /dev/null even if the unit does not exist,
	# so we can safely run this even if the units are not present, and prevent issues
	# in the future; at least it's not a footgun!
	einfo "Masking known problematic systemd units for WSL compatibility."
	for unit in "${known_bad_units[@]}"; do
		maybe_run_quiet systemctl mask "$unit"
		if [[ $? -ne 0 ]]; then
			ewarn "Failed to mask unit: $unit"
		fi
	done
}

cleanup_and_exit() {
	einfo "Cleaning up user '$username'."
	maybe_run userdel -r "$username"
	die "$*"
}

# =========================
# Banner and Info
# =========================

echo
# don't set the background colour; skip the output template
sed -e 's/;40//g' /etc/issue.logo | head

echo "Welcome to Gentoo Linux ($(uname -m)) on Windows Subsystem for Linux (WSL)!"
echo
echo 'Please create a default UNIX user account. The username does not need to match your Windows username.'
echo 'For more information visit: https://aka.ms/wslusers'

# =========================
# Main Logic
# =========================

DEBUG_OOBE="${DEBUG_OOBE:-}"

edebug "DEBUG_OOBE is set: Skipping user_exists_by_uid check and system modifications."

if [[ -z "$DEBUG_OOBE" ]]; then
	if user_exists_by_uid "$DEFAULT_UID"; then
		einfo 'User account already exists, skipping creation'
		exit 0
	fi
fi

main_oobe_loop() {
	local username password user_hash root_hash
	local chpasswd_user_status chpasswd_root_status
	local has_network="false"

	edebug "Starting OOBE loop"

	if check_network_connectivity; then
		has_network="true"
	else
		ewarn "No network connectivity detected. Some features may be limited."
	fi

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
				cleanup_and_exit "Generated user password hash does not look valid: $user_hash"
			elif ! is_hash_like "$root_hash"; then
				cleanup_and_exit "Generated root password hash does not look valid: $root_hash"
			fi

			printf '%s:%s\n' "$username" "$user_hash" | maybe_run chpasswd -e
			chpasswd_user_status=$?

			printf '%s:%s\n' "root" "$root_hash" | maybe_run chpasswd -e
			chpasswd_root_status=$?

			clear_sensitive_vars password user_hash root_hash

			if [[ $chpasswd_user_status -ne 0 && $chpasswd_root_status -ne 0 ]]; then
				cleanup_and_exit "Failed to set passwords for both user '$username' and root."
			elif [[ $chpasswd_user_status -ne 0 ]]; then
				cleanup_and_exit "Failed to set password for user '$username', but root password was set."
			elif [[ $chpasswd_root_status -ne 0 ]]; then
				cleanup_and_exit "Failed to set password for root, but user '$username' password was set."
			fi

			einfo "User '$username' created successfully."
			einfo "'root' password set to match the new user password."

			if [[ "$has_network" == "true" ]]; then
				# Configure binary package verification and setup ::gentoo
				# requires network connectivity to download keys and sync
				einfo "Configuring binary package verification keyring with Gentoo trust tool (getuto) ..."
				maybe_run_quiet getuto
				if [[ $? -eq 0 ]]; then
					einfo "getuto configuration completed successfully"
				else
					ewarn "Warning: getuto configuration failed, this is not a critical issue,"
					ewarn "but you may want to run 'getuto' manually later."
				fi
				einfo "Setting up gentoo repository for git sync ..."
				# Disable the default gentoo repository if it exists
				if [[ -f /etc/portage/repos.conf/gentoo.conf ]]; then
					einfo "Disabling and removing existing gentoo repository ..."
					maybe_run_quiet eselect repository remove -f gentoo
				fi
				# creating it with eselect-repository will default to git sync
				maybe_run_quiet eselect repository enable gentoo
				einfo "syncing the Gentoo repository ..."
				maybe_run emerge --sync
				if [[ $? -eq 0 ]]; then
					einfo "Gentoo repository synced successfully."
					# WSL users really only need to read news that came out after the first sync.
					maybe_run eselect news read --quiet
					maybe_run eselect news purge
				else
					ewarn "Warning: Failed to sync Gentoo repository, this is not a critical issue,"
					ewarn "but you may want to run 'emerge --sync' manually later."
				fi
			else
				# Network-dependent setup must be deferred when offline
				ewarn "Network connectivity unavailable - skipping getuto binary package setup."
				ewarn "You can run 'getuto' manually later when network is available;"
				ewarn "the Gentoo repository will need to be synced manually before portage can be used."
			fi

			if command -v systemctl >/dev/null 2>&1; then
				einfo "systemd detected"
				mask_systemd_units
				einfo "running systemd-machine-id-setup"
				maybe_run systemd-machine-id-setup
				ewarn "You should restart WSL to apply systemd changes."
				ewarn "Run 'wsl --terminate Gentoo' or 'wsl --shutdown' in PowerShell or Command Prompt."
			fi

			edebug "OOBE complete! No changes made."
			show_install_tips
			echo

			break
		else
			echo "Failed to create user. See error above."
		fi
	done
}

main_oobe_loop
