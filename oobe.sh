#!/bin/bash
# OOBE Script for Gentoo Linux on WSL
# This script is run during the first launch of the Gentoo WSL distribution.
# It sets up a user account and configures the root password.
# https://learn.microsoft.com/en-us/windows/wsl/build-custom-distro#add-the-wsl-distribution-configuration-file
#
# Error Codes:
#   97 - Required external command not found
#   98 - Required group does not exist
#   99 - Script not run under bash
#
# Exit codes from report_bug() and die() are used for specific error reporting.

DEFAULT_UID=1000
GENTOO_SYNC_URI="https://github.com/gentoo-mirror/gentoo.git"

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
# Don't check for:
# - passwdqc; part of base stage3, and we don't want to enforce password complexity
# - systemctl; we'll assume it's available if systemd is detected

for cmd in chpasswd getuto openssl pr useradd; do
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
trap 'unset password password2 username user_hash root_hash 2>/dev/null || true' EXIT

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
		    - Elevate privileges to root using \`su\` until you set up sudo or doas.
		    - Use \`emerge --sync\` to sync the portage tree (as root).
		      + \`emerge-webrsync\` is a good alternative for systems with restricted network access.
		    - Use \`emerge -uDNav @world\` to update the system (as root).
		    - Read the Gentoo Handbook for more information:
		        https://wiki.gentoo.org/wiki/Handbook:Main_Page
		    - Consider using the binary package host (binhost) and only compiling
		      packages where you want to change the USE flags.
		      This can save time and resources. See:
		        https://wiki.gentoo.org/wiki/Gentoo_Binary_Host_Quickstart
		    - For privilege escalation helpers:
		        su -c 'emerge app-admin/doas'
		        su -c 'emerge app-admin/sudo'

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

		# Even though WSL stage4 images remove the pwqcheck USE flag by default,
		# the binary will be installed because we haven't depcleaned the system yet.
		# Additionally this script / package may be installed on a system built from
		# a 'normal' stage3 with USE pwqcheck enabled; we need to check the PAM configuration.
		if grep 'passwdqc' /etc/pam.d/system-auth; then
			edebug "${FUNCNAME[0]}: PAM passwdqc module detected, checking password complexity."
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
		else
			edebug "${FUNCNAME[0]}: PAM passwdqc module not detected, skipping complexity check."
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
		if ! maybe_run_quiet systemctl mask "$unit"; then
			ewarn "Failed to mask unit: $unit"
		fi
	done
}

# Expand short locale format (e.g., "en_US" -> "en_US.UTF-8 UTF-8")
# Prefers UTF-8 encoding, falls back to first available encoding
expand_locale_shorthand() {
	local short_locale="$1"
	local full_locale

	edebug "${FUNCNAME[0]}: input='$short_locale'"
	# Try UTF-8 first (preferred)
	full_locale=$(grep -E "^$short_locale\.UTF-8" /usr/share/i18n/SUPPORTED | head -n 1)
	edebug "${FUNCNAME[0]}: utf8 result='$full_locale'"
	if [[ -n "$full_locale" ]]; then
		echo "$full_locale"
		return 0
	fi

	# Fall back to any encoding
	full_locale=$(grep -E "^$short_locale\." /usr/share/i18n/SUPPORTED | head -n 1)
	edebug "${FUNCNAME[0]}: fallback result='$full_locale'"
	if [[ -n "$full_locale" ]]; then
		echo "$full_locale"
		return 0
	fi

	edebug "${FUNCNAME[0]}: no match for '$short_locale'"
	# No match found
	return 1
}

set_and_generate_locale() {

	# We need to set and generate some locales to avoid a scary
	# `setlocale: unsupported locale setting` warning when running `emerge`
	local locale
	# This just gets us the list of valid locales, we can infer encoding and it's a lot easier
	# for new users to understand.
	local valid_locales=()
	mapfile -t valid_locales < <(find /usr/share/i18n/locales/ -maxdepth 1 -type f -not -name "*@*" -not -name "*1*" -not -name "*translit*" -printf "%f\n" | sort -u)

	echo "We can set up a some locale settings now if you would like; this will prevent"
	echo "a (harmless) warning when running \`emerge\` or other commands that require locale settings."
	echo "You can also skip this step and set up locales later by"
	echo "editing \`/etc/locale.gen\` and running \`locale-gen\`."
	echo "See https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Base#Locale_generation for more information."

	read -r -p "Do you want to set up a locale now? [Y/n]: " set_locale
	if [[ "$set_locale" =~ ^[Nn][Oo]?$ ]]; then
		return 0
	fi

	echo
	echo "Please select a locale, or press Enter to use the default (\`en_US\`)"
	echo "You can type 'show' to see a list of supported locales."
	echo
	echo "A particular locale and encoding combination (e.g. en_US.UTF-8 UTF-8) can be selected."
	echo "If you aren't sure, use the default; this can be changed later."

	while true; do
		read -r -p "Locale (default: en_US): " locale

		# Handle default case
		if [[ -z "$locale" ]]; then
			locale="en_US.UTF-8 UTF-8"
			break
		fi

		# Handle show command
		if [[ "$locale" == [Ss][Hh][Oo][Ww] ]]; then
			echo "Available locales:"
			echo "${valid_locales[@]}" | pr -9ts"$(printf "\t\t")"
			echo "Please select a locale from the list above."
			continue
		fi

		# Expand short locale format (e.g., "en_US" -> "en_US.UTF-8 UTF-8")
		if [[ "$locale" =~ ^[a-z]{2}_[A-Z]{2}$ ]]; then
			edebug "${FUNCNAME[0]}: Detected short locale format: $locale"
			locale=$(expand_locale_shorthand "$locale") || true
			edebug "${FUNCNAME[0]}: Expanded locale: $locale"
			if [[ -z "$locale" ]]; then
				echo "No matching locale found for the specified country code."
				continue
			fi
		fi

		# Validate final locale format
		if grep -q "^$locale$" /usr/share/i18n/SUPPORTED; then
			break
		else
			echo "Invalid locale format or not found in SUPPORTED locales: '$locale'."
			echo "Use 'show' to see available locales or try a format like 'en_US.UTF-8 UTF-8'."
			continue
		fi
	done

	if [[ -z "$DEBUG_OOBE" ]]; then
		# Only append if not already present
		if ! grep -q "^$locale$" /etc/locale.gen 2>/dev/null; then
			echo "${locale}" >> /etc/locale.gen
		else
			echo "Locale '$locale' already present in /etc/locale.gen, not adding duplicate."
		fi
	else
		edebug "${FUNCNAME[0]}: debug mode: Not modifying /etc/locale.gen"
		edebug "Would run: \`echo \"${locale}\" >> /etc/locale.gen\`"
	fi
	maybe_run locale-gen

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
	local chpasswd_user_success chpasswd_root_success
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

		if maybe_run /usr/sbin/useradd -m -u "$DEFAULT_UID" \
			-s /bin/bash -c '' \
			-G "$(IFS=,; echo "${groups[*]}")" \
			"$username" || [[ -n "$DEBUG_OOBE" ]]; then
			user_hash=$(hashpw "$password")
			root_hash=$(hashpw "$password")

			if ! is_hash_like "$user_hash"; then
				cleanup_and_exit "Generated user password hash does not look valid: $user_hash"
			elif ! is_hash_like "$root_hash"; then
				cleanup_and_exit "Generated root password hash does not look valid: $root_hash"
			fi

			# Set user password
			if printf '%s:%s\n' "$username" "$user_hash" | maybe_run chpasswd -e; then
				chpasswd_user_success=true
			else
				chpasswd_user_success=false
			fi

			# Set root password
			if printf '%s:%s\n' "root" "$root_hash" | maybe_run chpasswd -e; then
				chpasswd_root_success=true
			else
				chpasswd_root_success=false
			fi

			clear_sensitive_vars password user_hash root_hash

			# If this somehow fails we want good debug info - we can't expect good logs...
			if [[ "$chpasswd_user_success" == "false" && "$chpasswd_root_success" == "false" ]]; then
				cleanup_and_exit "Failed to set passwords for both user '$username' and root."
			elif [[ "$chpasswd_user_success" == "false" ]]; then
				cleanup_and_exit "Failed to set password for user '$username', but root password was set."
			elif [[ "$chpasswd_root_success" == "false" ]]; then
				cleanup_and_exit "Failed to set password for root, but user '$username' password was set."
			fi

			einfo "User '$username' created successfully."
			einfo "'root' password set to match the new user password."

			set_and_generate_locale

			maybe_run_quiet etc-update

			if [[ "$has_network" == "true" ]]; then
				# Configure binary package verification and setup ::gentoo
				# requires network connectivity to download keys and sync
				einfo "Configuring binary package verification keyring with Gentoo trust tool (getuto) ..."
				if maybe_run_quiet getuto; then
					einfo "getuto configuration completed successfully"
				else
					ewarn "Warning: getuto configuration failed, this is not a critical issue,"
					ewarn "but you may want to run \`getuto\` manually later."
				fi
				einfo "Setting up gentoo repository for git sync ..."
				# Disable the default gentoo repository if it exists
				if [[ -f /etc/portage/repos.conf/gentoo.conf ]]; then
					einfo "Disabling and removing existing gentoo repository ..."
					maybe_run_quiet eselect repository remove -f gentoo
				fi
				# use eselect repository to add the gentoo repository; use `add`, `enable` is not consistent
				maybe_run_quiet eselect repository add gentoo git "${GENTOO_SYNC_URI}"
				# enable repository verification
				maybe_run_quiet sh -c 'echo "sync-git-verify-commit-signature = yes" >> /etc/portage/repos.conf/eselect-repo.conf'
				einfo "syncing the Gentoo repository ..."
				if maybe_run emerge --sync; then
					einfo "Gentoo repository synced successfully."
					# WSL users really only need to read news that came out after the first sync.
					maybe_run eselect news read --quiet
					maybe_run eselect news purge
				else
					ewarn "Warning: Failed to sync Gentoo repository. this is not a critical issue;"
					ewarn "check network settings and run \`emerge --sync\` manually later."
				fi
			else
				# Network-dependent setup must be deferred when offline
				ewarn "Network connectivity unavailable - skipping getuto binary package setup."
				ewarn "You can run \`getuto\` manually later when network is available;"
				ewarn "the Gentoo repository will need to be synced manually before portage can be used."
			fi

			if command -v systemctl >/dev/null 2>&1; then
				einfo "systemd detected"
				mask_systemd_units
				einfo "running systemd-machine-id-setup"
				maybe_run systemd-machine-id-setup
				ewarn "You should restart WSL to apply systemd changes."
				ewarn "Run \`wsl --terminate Gentoo\` or \`wsl --shutdown\` in PowerShell or Command Prompt."
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
