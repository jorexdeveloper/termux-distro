#!/data/data/com.termux/files/usr/bin/bash

################################################################################
#                                                                              #
#     Termux Distro Installer.                                                 #
#                                                                              #
#     Installs Distro in Termux.                                               #
#                                                                              #
#     Copyright (C) 2023-2025  Jore <https://github.com/jorexdeveloper>        #
#                                                                              #
#     This program is free software: you can redistribute it and/or modify     #
#     it under the terms of the GNU General Public License as published by     #
#     the Free Software Foundation, either version 3 of the License, or        #
#     (at your option) any later version.                                      #
#                                                                              #
#     This program is distributed in the hope that it will be useful,          #
#     but WITHOUT ANY WARRANTY; without even the implied warranty of           #
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
#     GNU General Public License for more details.                             #
#                                                                              #
#     You should have received a copy of the GNU General Public License        #
#     along with this program.  If not, see <https://www.gnu.org/licenses/>.   #
#                                                                              #
################################################################################
# shellcheck disable=SC2034

# ATTENTION!!! CHANGE BELOW FUNTIONS FOR DISTRO DEPENDENT ACTIONS!!!

# Called before any safety checks
# New Variables: AUTHOR GITHUB LOG_FILE ACTION_INSTALL ACTION_CONFIGURE
#                ROOTFS_DIRECTORY COLOR_SUPPORT all_available_colors
pre_check_actions() {
	return
}

# Called before printing intro
# New Variables: none
distro_banner() {
	local spaces=''
	local banner='Termux-Distro'
	for ((i = $((($(stty size | cut -d ' ' -f2) - ${#banner}) / 2)); i > 0; i--)); do
		spaces+=' '
	done
	msg -a "${spaces}${banner}"
	msg -a "${spaces}     ${Y}${VERSION_NAME}${C}"
}

# Called after checking architecture and required pkgs
# New Variables: SYS_ARCH LIB_GCC_PATH
post_check_actions() {
	return
}

# Called after checking for rootfs directory
# New Variables: KEEP_ROOTFS_DIRECTORY
pre_install_actions() {
	ARCHIVE_NAME="termux-distro-${SYS_ARCH}.tar.xz"
}

# Called after extracting rootfs
# New Variables: KEEP_ROOTFS_ARCHIVE
post_install_actions() {
	msg -t "Lemme create an xstartup script for vnc."
	local xstartup="$(
		# Customize depending on distribution defaults
		cat 2>>"${LOG_FILE}" <<-EOF
			#!/bin/bash
			#############################
			##          All            ##
			export XDG_RUNTIME_DIR=/tmp/runtime-"\${USER:-root}"
			export SHELL="\${SHELL:-/bin/sh}"

			unset SESSION_MANAGER
			unset DBUS_SESSION_BUS_ADDRESS

			xrdb "\${HOME:-/tmp}"/.Xresources

			#############################
			##          Gnome          ##
			# export XKL_XMODMAP_DISABLE=1
			# exec gnome-session

			############################
			##           LXQT         ##
			# exec startlxqt

			############################
			##          KDE           ##
			# exec startplasma-x11

			############################
			##          XFCE          ##
			# export QT_QPA_PLATFORMTHEME=qt5ct
			# exec startxfce4

			############################
			##           i3           ##
			# exec i3
		EOF
	)"
	if {
		mkdir -p "${ROOTFS_DIRECTORY}/root/.vnc"
		echo "${xstartup}" >"${ROOTFS_DIRECTORY}/root/.vnc/xstartup"
		chmod 744 "${ROOTFS_DIRECTORY}/root/.vnc/xstartup"
		if [ "${DEFAULT_LOGIN}" != "root" ]; then
			mkdir -p "${ROOTFS_DIRECTORY}/home/${DEFAULT_LOGIN}/.vnc"
			echo "${xstartup}" >"${ROOTFS_DIRECTORY}/home/${DEFAULT_LOGIN}/.vnc/xstartup"
			chmod 744 "${ROOTFS_DIRECTORY}/home/${DEFAULT_LOGIN}/.vnc/xstartup"
		fi
	} 2>>"${LOG_FILE}"; then
		msg -s "Done, xstartup script created successfully!"
	else
		msg -e "Sorry, I failed to create the xstartup script for vnc."
	fi
}

# Called before making configurations
# New Variables: none
pre_config_actions() {
	return
}

# Called after configurations
# New Variables: none
post_config_actions() {
	# execute distro specific command for locale generation
	if [ -f "${ROOTFS_DIRECTORY}/etc/locale.gen" ] && [ -x "${ROOTFS_DIRECTORY}/sbin/dpkg-reconfigure" ]; then
		msg -t "Hold on while I generate the locales for you."
		sed -i -E 's/#[[:space:]]?(en_US.UTF-8[[:space:]]+UTF-8)/\1/g' "${ROOTFS_DIRECTORY}/etc/locale.gen"
		if distro_exec locale-gen >>"${LOG_FILE}" 2>&1; then # DEBIAN_FRONTEND=noninteractive /sbin/dpkg-reconfigure locales >>"${LOG_FILE}" 2>&1
			msg -s "Done, the locales are ready!"
		else
			msg -e "Sorry, I failed to generate the locales."
		fi
	fi
}

# Called before complete message
# New Variables: none
pre_complete_actions() {
	return
}

# Called after complete message
# New Variables: none
post_complete_actions() {
	return
}

DISTRO_NAME="Termux Distro"
PROGRAM_NAME="$(basename "${0}")"
DISTRO_REPOSITORY="termux-distro"
VERSION_NAME="1.0"

SHASUM_CMD=sha256sum
TRUSTED_SHASUMS="$(
	cat <<-EOF
		88386c62d1ee127a18658ac99adb34eb9d8e930f2861979f5c98fb003adbd0f9 *termux-distro-arm64.tar.xz
	EOF
)"

ARCHIVE_STRIP_DIRS=0 # directories stripped by tar when extracting rootfs archive
KERNEL_RELEASE="6.2.1-termux-distro-proot"
BASE_URL="https://raw.githubusercontent.com/jorexdeveloper/termux-distro"

TERMUX_FILES_DIR="/data/data/com.termux/files"

DISTRO_SHORTCUT="${TERMUX_FILES_DIR}/usr/bin/td"
DISTRO_LAUNCHER="${TERMUX_FILES_DIR}/usr/bin/termux-distro"

DEFAULT_ROOTFS_DIR="${TERMUX_FILES_DIR}/termux-distro"
DEFAULT_LOGIN="root"

# WARNING!!! DO NOT CHANGE BELOW!!!

# Check in script's directory for template
distro_template="$(realpath "$(dirname "${0}")")/termux-distro.sh"
# shellcheck disable=SC1090
if [ -f "${distro_template}" ] && [ -r "${distro_template}" ]; then
	source "${distro_template}" "${@}"
elif curl -fsSLO "https://raw.githubusercontent.com/jorexdeveloper/termux-distro/main/termux-distro.sh" 2>"/dev/null" && [ -f "${distro_template}" ]; then
	source "${distro_template}"
else
	echo "You need an active internet connection to run this script."
fi
