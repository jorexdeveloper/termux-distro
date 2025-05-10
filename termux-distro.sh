#!/data/data/com.termux/files/usr/bin/bash

################################################################################
#                                                                              #
# Termux Distro Template.                                                      #
#                                                                              #
# Template for installing Linux Distro in Termux.                              #
#                                                                              #
# Copyright (C) 2023-2025 Jore <https://github.com/jorexdeveloper>             #
#                                                                              #
# This program is free software: you can redistribute it and/or modify         #
# it under the terms of the GNU General Public License as published by         #
# the Free Software Foundation, either version 3 of the License, or            #
# (at your option) any later version.                                          #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program.  If not, see <https://www.gnu.org/licenses/>.       #
#                                                                              #
################################################################################
# shellcheck disable=SC2155 disable=SC2154

################################################################################
# Prevents running this program in the wrong environment.                      #
################################################################################
safety_check() {
	if [ "${EUID}" = "0" ] || [ "$(id -u)" = "0" ]; then
		msg -aq "I can't let you run this program with root permissions! This can cause several issues and potentially damage your phone."
	fi
	local pid="$(grep TracerPid "/proc/$$/status" | cut -d $'\t' -f 2)"
	if [ "${pid}" != 0 ]; then
		if [ "$(grep Name "/proc/${pid}/status" | cut -d $'\t' -f 2)" = "proot" ]; then
			msg -aq "I can't let you run this program within proot! This can lead to performance degradation and other issues."
		fi
	fi
}

################################################################################
# Prints the distro an introducing message.                                    #
################################################################################
print_intro() {
	msg -t "Hi, I'm ${AUTHOR}."
	msg "I am here to help you to ${action:-install} ${DISTRO_NAME} in Termux."
}

################################################################################
# Checks if the device architecture is supported                               #
# Sets global variables: SYS_ARCH LIB_GCC_PATH                                 #
################################################################################
check_arch() {
	msg -t "First, lemme check if your device architecture is supported."
	local arch
	if [ -x "$(command -v getprop)" ]; then
		arch="$(getprop ro.product.cpu.abi 2>>"${LOG_FILE}")"
	elif [ -x "$(command -v uname)" ]; then
		arch="$(uname -m 2>>"${LOG_FILE}")"
	else
		msg -q "Sorry, have I failed to get your device architecture."
	fi
	case "${arch}" in
		"arm64-v8a" | "armv8l")
			SYS_ARCH="arm64"
			LIB_GCC_PATH="/usr/lib/aarch64-linux-gnu/libgcc_s.so.1"
			;;
		"armeabi" | "armv7l" | "armeabi-v7a")
			SYS_ARCH="armhf"
			LIB_GCC_PATH="/usr/lib/arm-linux-gnueabihf/libgcc_s.so.1"
			;;
		*) msg -q "Sorry, '${Y}${arch}${R}' is currently not supported." ;;
	esac
	msg -s "Yup, '${Y}${arch}${G}' is supported!"
}

################################################################################
# Updates installed packages and checks if the required commands that are not  #
# pre-installed are installed, if not, attempts to install them                #
################################################################################
check_pkgs() {
	msg -t "Now lemme make sure that all your packages are up to date."
	if [ -x "$(command -v pkg)" ] && pkg update -y < <(echo -e "y\ny\ny\ny\ny") >>"${LOG_FILE}" 2>&1 && pkg upgrade -y < <(echo -e "y\ny\ny\ny\ny") >>"${LOG_FILE}" 2>&1; then # || apt-get -qq -o=Dpkg::Use-Pty=0 update -y >>"${LOG_FILE}" 2>&1 || apt-get -qq -o=Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" dist-upgrade -y >>"${LOG_FILE}" 2>&1; then
		msg -s "Yup, Everything looks good!"
	else
		msg -qm0 "Sorry, have I failed to update your packages."
	fi
	msg -t "Lemme also check if all the required packages are installed."
	for package in awk basename curl du proot pulseaudio readlink realpath sed tar unzip xz; do
		if ! [ -x "$(command -v "${package}")" ]; then
			msg "Oops, looks like '${Y}${package}${C}' is missing! Let me install it now."
			if pkg install -y "${package}" < <(echo -e "y\ny\ny\ny\ny") >>"${LOG_FILE}" 2>&1; then # || apt-get -qq -o=Dpkg::Use-Pty=0 install -y "${package}" >>"${LOG_FILE}" 2>&1; then
				msg -s "Done, '${Y}${package}${G}' is now installed!"
			else
				msg -qm0 "Sorry, have I failed to install '${Y}${package}${R}'."
			fi
		fi
	done
	msg -s "Yup, you have all the required packages!"
	unset package
}

################################################################################
# Checks if there is an existing rootfs directory, or a file with similar name #
# Sets global variables: KEEP_ROOTFS_DIRECTORY                                 #
################################################################################
check_rootfs_directory() {
	unset KEEP_ROOTFS_DIRECTORY
	if [ -e "${ROOTFS_DIRECTORY}" ]; then
		if [ -d "${ROOTFS_DIRECTORY}" ]; then
			if [ -n "$(ls -UA "${ROOTFS_DIRECTORY}" 2>>"${LOG_FILE}")" ]; then
				msg -tn "Wait, There is an existing rootfs directory of size: ..."
				msg -a "\b\b\b${Y}$(du -sh "${ROOTFS_DIRECTORY}" 2>>"${LOG_FILE}" | awk '{print $1}' 2>>"${LOG_FILE}")${C}!"
				msg "What should I do with it?"
				msg -l "Use" "${R}Delete${C}" "Exit (default)"
				msg -n "Select action: "
				read -ren 1 reply
				case "${reply}" in
					1 | u | U)
						msg "Okay, I shall proceed with it."
						KEEP_ROOTFS_DIRECTORY=1
						return
						;;
					2 | d | D) ;;
					*) msg -q "Alright, exiting!" ;;
				esac
				unset reply
			else
				rmdir "${ROOTFS_DIRECTORY}" >>"${LOG_FILE}" 2>&1
				return
			fi
		else
			msg -t "Wait, There is a file of size: ${Y}$(du -sh "${ROOTFS_DIRECTORY}" 2>>"${LOG_FILE}" | awk '{print $1}' 2>>"${LOG_FILE}")${C}"
			msg "With the same name as the rootfs directory!"
			if ! ask -n "Should I ${R}delete${C} the it and proceed?"; then
				msg -q "Alright, exiting!"
			fi
		fi
		msg "Okay, deleting '${Y}${ROOTFS_DIRECTORY}${C}'!"
		if remove "${ROOTFS_DIRECTORY}" >>"${LOG_FILE}" 2>&1; then
			msg -s "Done, let's proceed."
		else
			msg -q "Sorry, have I failed to delete '${Y}${ROOTFS_DIRECTORY}${R}'."
		fi
	fi
}

################################################################################
# Downloads the rootfs archive if it does not exist in the current directory   #
# Sets global variables: KEEP_ROOTFS_ARCHIVE                                   #
################################################################################
download_rootfs_archive() {
	unset KEEP_ROOTFS_ARCHIVE
	if [ -z "${KEEP_ROOTFS_DIRECTORY}" ]; then
		if [ -e "${ARCHIVE_NAME}" ]; then
			if [ -f "${ARCHIVE_NAME}" ]; then
				msg -t "Wait, There is an existing rootfs archive!"
				if ! ask -n "Should I ${R}delete${C} it and download a new one?"; then
					msg "Okay, lemme use it."
					KEEP_ROOTFS_ARCHIVE=1
					return
				fi
			else
				msg -t "Wait, There is something with the same name as the rootfs archive!"
				if ! ask -n "Should I ${R}delete${C} it and proceed?"; then
					msg -q "Alright, exiting!"
				fi
			fi
			msg "Okay, deleting '${Y}${ARCHIVE_NAME}${C}'."
			if remove "${ARCHIVE_NAME}" >>"${LOG_FILE}" 2>&1; then
				msg -s "Done, let's proceed."
			else
				msg -q "Sorry, have I failed to delete '${Y}${ARCHIVE_NAME}${R}'."
			fi
		fi
		local tmp_dload="${ARCHIVE_NAME}.pending"
		msg -t "Alright, now lemme download the rootfs archive. This might take a while."
		if curl --disable --fail --location --progress-meter --retry-connrefused --retry 0 --retry-delay 3 --continue-at - --output "${tmp_dload}" "${BASE_URL}/${ARCHIVE_NAME}"; then
			mv "${tmp_dload}" "${ARCHIVE_NAME}" >>"${LOG_FILE}" 2>&1
			msg -s "Great, the rootfs download is complete!"
		else
			msg -qm0 "Sorry, have I failed to download the rootfs archive."
		fi
	fi
}

################################################################################
# Checks the integrity of the rootfs archive                                   #
################################################################################
verify_rootfs_archive() {
	if [ -z "${KEEP_ROOTFS_DIRECTORY}" ]; then
		msg -t "Give me a sec to make sure the rootfs archive is ok."
		if grep --regexp="${ARCHIVE_NAME}$" <<<"${TRUSTED_SHASUMS}" 2>>"${LOG_FILE}" | "${SHASUM_CMD}" --quiet --check >>"${LOG_FILE}" 2>&1; then
			msg -s "Yup, the rootfs archive looks fine!"
			return
		else
			msg -q "Sorry, the rootfs archive is corrupted and not safe for installation."
		fi
	fi
}

################################################################################
# Extracts the contents of the rootfs archive                                  #
################################################################################
extract_rootfs_archive() {
	if [ -z "${KEEP_ROOTFS_DIRECTORY}" ]; then
		msg -t "Now, grab a coffee while I extract the rootfs archive."
		msg "This will take a while."
		trap 'e=${?}; msg -e "Extraction process interupted. Clearing cache.                 "; echo -ne "${N}${V}"; remove "${ROOTFS_DIRECTORY}" >>"${LOG_FILE}" 2>&1; exit ${e}' HUP INT TERM
		mkdir -p "${ROOTFS_DIRECTORY}"
		if proot --link2symlink tar --strip="${ARCHIVE_STRIP_DIRS}" --delay-directory-restore --preserve-permissions --warning=no-unknown-keyword --extract --auto-compress --exclude="dev" --file="${ARCHIVE_NAME}" --directory="${ROOTFS_DIRECTORY}" --checkpoint=1 --checkpoint-action=ttyout="${I}${Y}   I have extracted %{}T in %ds so far.%*\r${N}${V}" >>"${LOG_FILE}" 2>&1; then
			msg -s "Finally, I am done extracting the rootfs archive!."
		else
			remove "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}"
			msg -q "Sorry, have I failed to extract the rootfs archive."
		fi
		trap - HUP INT TERM
	fi
}

################################################################################
# Creates a script used to login into the distro                               #
################################################################################
create_rootfs_launcher() {
	msg -t "Lemme create a command to launch ${DISTRO_NAME}."
	mkdir -p "$(dirname "${DISTRO_LAUNCHER}")" >>"${LOG_FILE}" 2>&1 && cat >"${DISTRO_LAUNCHER}" 2>>"${LOG_FILE}" <<-EOF
		#!${TERMUX_FILES_DIR}/usr/bin/bash

		################################################################################
		#                                                                              #
		# $(
			text="${DISTRO_NAME} Launcher version ${VERSION_NAME}"
			echo -n "${text}"
			len=$((76 - ${#text}))
			while ((len > 0)); do
				echo -n ' '
				((len--))
			done
		) #
		#                                                                              #
		# License GPLv3+: GNU GPL version 3 or later                                   #
		# <https://gnu.org/licenses/gpl.html>                                          #
		#                                                                              #
		# This is free software, you are free to change and redistribute it.           #
		# There is NO WARRANTY, to the extent permitted by law.                        #
		#                                                                              #
		################################################################################

		# Disable termux-exec
		unset LD_PRELOAD

		program_name="$(basename "${DISTRO_LAUNCHER}")"
		working_dir=""
		home_dir=""
		env_vars=(
		    "LANG=C.UTF-8"
		    "TERM=\${TERM:-xterm-256color}"
		    "PATH=${DEFAULT_PATH}:${TERMUX_FILES_DIR}/usr/local/bin:${TERMUX_FILES_DIR}/usr/bin"
		)
		custom_ids=""
		isolated_env=false
		custom_bindings=()
		share_tmp=false
		no_kill_on_exit=false
		no_link2symlink=false
		no_proot_errors=false
		no_sysvipc=false
		fix_ports=false
		kernel_release=""
		user_name=""

		# Process command line arguments
		while [ "\${#}" -gt 0 ]; do
		    case "\${1}" in
		        --wd*)
		            optarg="\${1/--wd/}"
		            optarg="\${optarg/=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--wd' requires an argument."
		                exit 1
		            fi
		            working_dir="\${optarg}"
		            ;;
		        --home*)
		            optarg="\${1/--home/}"
		            optarg="\${optarg/=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--home' requires an argument."
		                exit 1
		            fi
		            home_dir="\${optarg}"
		            ;;
		        --env*)
		            optarg="\${1/--env/}"
		            optarg="\${optarg/=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--env' requires an argument."
		                exit 1
		            fi
		            env_vars+=("\${optarg}")
		            ;;
		        --id*)
		            optarg="\${1/--id/}"
		            optarg="\${optarg/=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--id' requires an argument."
		                exit 1
		            fi
		            custom_ids="\${optarg}"
		            ;;
		        --termux-ids)
		            custom_ids="\$(id -u):\$(id -g)"
		            ;;
		        --isolated)
		            isolated_env=true
		            ;;
		        --bind*)
		            optarg="\${1/--bind/}"
		            optarg="\${optarg/=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--bind' requires an argument."
		                exit 1
		            fi
		            custom_bindings+=("--bind=\${optarg}")
		            ;;
		        --share-tmp)
		            share_tmp=true
		            ;;
		        --no-kill-on-exit)
		            no_kill_on_exit=true
		            ;;
		        --no-link2symlink)
		            no_link2symlink=true
		            ;;
		        --no-proot-errors)
		            no_proot_errors=true
		            ;;
		        --no-sysvipc)
		            no_sysvipc=true
		            ;;
		        --fix-ports)
		            fix_ports=true
		            ;;
		        --kernel*)
		            optarg="\${1/--kernel/}"
		            optarg="\${optarg/=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--kernel' requires an argument."
		                exit 1
		            fi
		            kernel_release="\${optarg}"
		            ;;
		        -r | --rename*)
		            optarg="\${1/--rename/}"
		            optarg="\${optarg/=/}"
		            if [ "\${optarg}" = "-r" ] || [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '-r' or '--rename' requires an argument."
		                exit 1
		            fi
		            if ! [ -e "${ROOTFS_DIRECTORY}" ]; then
		                echo "'${ROOTFS_DIRECTORY}' is missing, exiting."
		                exit 1
		            fi
		            old_chroot="${ROOTFS_DIRECTORY}"
		            new_chroot="\$(realpath "\${optarg}")"
		            rmdir "\${new_chroot}" >/dev/null 2>&1
		            if [ -e "\${new_chroot}" ]; then
		                echo "'\${new_chroot}' already exists, exiting."
		                exit 1
		            fi
		            echo "Renaming '\${old_chroot}' to '\${new_chroot}'."
		            if mv "\${old_chroot}" "\${new_chroot}" &&
		                echo "Updating proot links, this may take a while." &&
		                find "\${new_chroot}" -type l | while read -r name; do
		                    old_target="\$(readlink "\${name}")"
		                    if [ "\${old_target:0:\${#old_chroot}}" = "\${old_chroot}" ]; then
		                        ln -sf "\${old_target/\${old_chroot}/\${new_chroot}}" "\${name}"
		                    fi
		                done &&
		                echo "Updating \${program_name} command." &&
		                sed -Ei "s@\${old_chroot}@\${new_chroot}@" "${DISTRO_LAUNCHER}"; then
		                echo "${DISTRO_NAME} rootfs rename complete."
		                exit
		            else
		                echo "${DISTRO_NAME} rootfs rename failed."
		                exit 1
		            fi
		            ;;
		        -b | --backup*)
		            optarg="\${1/--backup/}"
		            optarg="\${optarg/=/}"
		            if [ "\${optarg}" = "-b" ] || [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '-b' or '--backup' requires an argument."
		                exit 1
		            fi
		            if ! [ -e "${ROOTFS_DIRECTORY}" ]; then
		                echo "'${ROOTFS_DIRECTORY}' is missing, exiting."
		                exit 1
		            fi
		            shift
		            file="\${optarg}"
		            include=(.l2s bin boot captures etc home lib media mnt opt proc root run sbin snap srv sys tmp usr var)
		            exclude=(apex data dev linkerconfig product sdcard storage system vendor "\${@}")
		            echo "Packing ${DISTRO_NAME} into '\${file}'."
		            echo "Including:" "\${include[@]}"
		            echo "Excluding:" "\${exclude[@]}"
		            exclude_args=()
		            for i in "\${exclude[@]}"; do
		                i="\$(echo -n "\${i}" | sed -E "s@^/@@")"
		                exclude_args=("\${exclude_args[@]}" "--exclude=\${i}")
		            done
		            for i in "\${include[@]}" "\${exclude[@]}"; do
		                mkdir -p "${ROOTFS_DIRECTORY}/\${i}" >/dev/null 2>&1
		            done
		            if tar --warning=no-file-ignored --one-file-system --xattrs --xattrs-include='*' --preserve-permissions --create --auto-compress -C "${ROOTFS_DIRECTORY}" --file="\${file}" "\${exclude_args[@]}" "\${include[@]}"; then
		                echo "${DISTRO_NAME} backup complete."
		                exit
		            else
		                echo "${DISTRO_NAME} backup failed."
		                exit 1
		            fi
		            ;;
		        -R | --restore*)
		            optarg="\${1/--restore/}"
		            optarg="\${optarg/=/}"
		            if [ "\${optarg}" = "-R" ] || [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '-R' or '--restore' requires an argument."
		                exit 1
		            fi
		            if ! [ -e "\${optarg}" ]; then
		                echo "'\${optarg}' is missing, exiting."
		                exit 1
		            fi
		            if [ -e "${ROOTFS_DIRECTORY}" ] && ! rmdir "${ROOTFS_DIRECTORY}" >/dev/null 2>&1; then
		                echo "'${ROOTFS_DIRECTORY}' already exists."
		                echo "  <1> Delete"
		                echo "  <2> Overwrite "
		                echo "  <3> Quit (default)"
		                read -r -p "Select action: " choice
		                case "\${choice}" in
		                    1 | d | D)
		                        echo "Deleting '${ROOTFS_DIRECTORY}'"
		                        chmod 777 -R "${ROOTFS_DIRECTORY}" >/dev/null 2>&1
		                        rm -rf "${ROOTFS_DIRECTORY}" || exit 1
		                        ;;
		                    2 | o | O)
		                        echo "Overwriting '${ROOTFS_DIRECTORY}'."
		                        ;;
		                    *)
		                        echo "Operation cancelled."
		                        exit 1
		                        ;;
		                esac
		            fi
		            file="\${optarg}"
		            echo "Restoring ${DISTRO_NAME} from \${file}."
		            mkdir -p "${ROOTFS_DIRECTORY}" >/dev/null 2>&1
		            if tar --delay-directory-restore --preserve-permissions --warning=no-unknown-keyword --extract --auto-compress -C "${ROOTFS_DIRECTORY}" --file "\${file}"; then
		                echo "${DISTRO_NAME} restore complete."
		                exit
		            else
		                echo "${DISTRO_NAME} restore failed."
		                exit 1
		            fi
		            ;;
		        -u | --uninstall)
		            if [ -d "${ROOTFS_DIRECTORY}" ]; then
		                echo "You are about to uninstall ${DISTRO_NAME} from:"
		                echo "  ⇒ '${ROOTFS_DIRECTORY}'."
		                echo "This action will delete all files in this directory!"
		                if read -r -p "Confirm action (y/N): " choice && [[ "\$choice" =~ ^(y|Y) ]]; then
		                    echo "Uninstalling ${DISTRO_NAME}."
		                    chmod 777 -R "${ROOTFS_DIRECTORY}" "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}" >/dev/null 2>&1
		                    if rm -rf "${ROOTFS_DIRECTORY}" "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}"; then
		                        echo "${DISTRO_NAME} uninstall complete."
		                        exit
		                    else
		                        echo "${DISTRO_NAME} uninstall failed."
		                    fi
		                else
		                    echo "Uninstallation cancelled."
		                fi
		            else
		                echo "No rootfs found in '${ROOTFS_DIRECTORY}'."
		            fi
		            exit 1
		            ;;
		        -v | --version)
		            echo "\${program_name} version ${VERSION_NAME}"
		            echo "Copyright (C) 2023-2025 ${AUTHOR} <${GITHUB}>."
		            echo "License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>."
		            echo ""
		            echo "This is free software, you are free to change and redistribute it."
		            echo "There is NO WARRANTY, to the extent permitted by law."
		            exit
		            ;;
		        -h | --help)
		            echo "Usage: \${program_name} [OPTION] [USERNAME] [-- [COMMAND [ARGS]]]"
		            echo ""
		            echo "Login or execute COMMAND in ${DISTRO_NAME} as USERNAME (default=${DEFAULT_LOGIN})."
		            echo ""
		            echo "LOGIN OPTIONS:"
		            echo "      --wd DIR               Set working directory. (defaults to HOME)"
		            echo "      --home DIR             Set home directory."
		            echo "                             (defaults to /home/USERNAME or /root)"
		            echo "      --env VAR=VAL          Set environment variable."
		            echo "      --id UID:GID           Set the current user and group ids."
		            echo "      --termux-ids           Use Termux user and group ids."
		            echo "      --isolated             Do not mount host specific directories in the"
		            echo "                             guest file system."
		            echo "      --bind PATH1[:PATH2]   Make PATH1 accessible as PATH2 in the guest"
		            echo "                             file system. (overrrides '--isolated')"
		            echo "      --share-tmp            Bind Termux TMPDIR to /tmp in the guest file"
		            echo "                             system."
		            echo "      --no-kill-on-exit      Do not kill running processes on exit."
		            echo "      --no-link2symlink      Disable hard-link emulation by proot."
		            echo "      --no-proot-errors      Prevent proot from printing error messages"
		            echo "                             except fatal errors."
		            echo "      --no-sysvipc           Disable System V IPC emulation by proot."
		            echo "      --fix-ports            Modify bindings to protected ports to use a"
		            echo "                             higher port number."
		            echo "      --kernel STRING        Set the current kernel release."
		            echo ""
		            echo "MANAGEMENT OPTIONS:"
		            echo "  -r, --rename PATH          Rename the rootfs directory."
		            echo "  -b, --backup FILE [DIRS]   Backup the rootfs directory excluding DIRS."
		            echo "                             The backup is performed as a TAR archive and"
		            echo "                             compression is determined by the output file"
		            echo "                             extension."
		            echo "  -R, --restore FILE         Restore the rootfs directory from TAR archive."
		            echo "  -u, --uninstall            Uninstall ${DISTRO_NAME}."
		            echo ""
		            echo "OTHER OPTIONS:"
		            echo "  -v, --version              Print program version and exit."
		            echo "  -h, --help                 Print help message and exit."
		            echo ""
		            echo "For more information, visit:"
		            echo "  ⇒ ${GITHUB}/${DISTRO_REPOSITORY}"
		            exit
		            ;;
		        --)
		            shift
		            break
		            ;;
		        -*)
		            echo "Unrecognized option '\${1}'."
		            echo "See '\${program_name} --help' for more information"
		            exit 1
		            ;;
		        *)
		            if [ -z "\${user_name}" ]; then
		                user_name="\${1}"
		            else
		                echo "Received too many arguments. Did you forget to add '--'?"
		                echo "See '\${program_name} --help' for more information"
		                exit 1
		            fi
		            ;;
		    esac
		    shift
		done

		# Set login name
		if [ -z "\${user_name}" ]; then
		    user_name="${DEFAULT_LOGIN}"
		fi

		# Check if user exists
		if ! [ -e "${ROOTFS_DIRECTORY}/etc/passwd" ] || ! grep -qE "^\${user_name}:" "${ROOTFS_DIRECTORY}/etc/passwd" >/dev/null 2>&1; then
		    echo "User '\${user_name}' does not exist in ${DISTRO_NAME}."
		    exit 1
		fi

		# Set home directory
		if [ -z "\${home_dir}" ]; then
		    if [ "\${user_name}" = "root" ]; then
		        home_dir="/root"
		    else
		        home_dir="/home/\${user_name}"
		    fi
		fi

		# Set home directory in environment
		env_vars=("HOME=\${home_dir}" "\${env_vars[@]}")
		mkdir -p "${ROOTFS_DIRECTORY}\${home_dir}" >/dev/null 2>&1

		# Prevent running as root
		if [ "\${EUID}" = "0" ] || [ "\$(id -u)" = "0" ]; then
		    echo "I can't let you start ${DISTRO_NAME} with root permissions! This can cause several issues and potentially damage your phone."
		    exit 1
		fi

		# Prevent running within proot
		pid="\$(grep TracerPid "/proc/\$\$/status" | cut -d \$'\t' -f 2)"
		if [ "\${pid}" != 0 ]; then
		    if [ "\$(grep Name "/proc/\${pid}/status" | cut -d \$'\t' -f 2)" = "proot" ]; then
		        echo "I can't let you start ${DISTRO_NAME} within proot! This can lead to performance degradation and other issues."
		        exit 1
		    fi
		fi

		# Check for login command
		if [ -z "\${*}" ]; then
		    # Prefer su as login command
		    if [ -x "${ROOTFS_DIRECTORY}/usr/bin/su" ]; then
		        set -- su --login "\${user_name}"
		    elif [ -x "${ROOTFS_DIRECTORY}/usr/bin/login" ]; then
		        set -- login "\${user_name}"
		    else
		        echo "Couldn't find any login command in the guest rootfs."
		        echo "See '\${program_name} --help' to learn how to run programs without logging in."
		        exit 1
		    fi
		fi

		# Create directory where proot stores all hard link info
		export PROOT_L2S_DIR="${ROOTFS_DIRECTORY}/.l2s"
		if ! [ -d "\${PROOT_L2S_DIR}" ]; then
		    mkdir -p "\${PROOT_L2S_DIR}"
		fi

		# Create fake /root/.version required by some apps i.e LibreOffice
		if ! [ -f "${ROOTFS_DIRECTORY}/root/.version" ]; then
		    mkdir -p "${ROOTFS_DIRECTORY}/root" && touch "${ROOTFS_DIRECTORY}/root/.version"
		fi

		proot_args=()
		proot_args+=("-L")
		proot_args+=("--cwd=\${working_dir:-\${home_dir}}")
		proot_args+=("--rootfs=${ROOTFS_DIRECTORY}")

		# Use custom UID/GID
		if [ -n "\${custom_ids}" ]; then
		    proot_args+=("--change-id=\${custom_ids}")
		else
		    proot_args+=("--root-id")
		fi

		# Enable proot hard-link emulation
		if ! "\${no_link2symlink}"; then
		    proot_args+=("--link2symlink")
		fi

		# Kill all processes on command exit
		if ! "\${no_kill_on_exit}"; then
		    proot_args+=("--kill-on-exit")
		fi

		# Handle System V IPC syscalls in proot
		if ! "\${no_sysvipc}"; then
		    proot_args+=("--sysvipc")
		fi

		# Make current kernel appear as kernel_release
		proot_args+=("--kernel-release=\${kernel_release:-${KERNEL_RELEASE}}")

		# Turn off proot errors
		if \${no_proot_errors}; then
		    proot_args+=("--verbose=-1")
		fi

		# Core file systems that should always be present.
		proot_args+=("--bind=/dev")
		proot_args+=("--bind=/dev/urandom:/dev/random")
		proot_args+=("--bind=/proc")
		proot_args+=("--bind=/proc/self/fd:/dev/fd")
		proot_args+=("--bind=/proc/self/fd/0:/dev/stdin")
		proot_args+=("--bind=/proc/self/fd/1:/dev/stdout")
		proot_args+=("--bind=/proc/self/fd/2:/dev/stderr")
		proot_args+=("--bind=/sys")

		# Fake system data entries restricted by Android OS
		if ! [ -r /proc/loadavg ]; then
		    proot_args+=("--bind=${ROOTFS_DIRECTORY}/proc/.loadavg:/proc/loadavg")
		fi
		if ! [ -r /proc/stat ]; then
		    proot_args+=("--bind=${ROOTFS_DIRECTORY}/proc/.stat:/proc/stat")
		fi
		if ! [ -r /proc/uptime ]; then
		    proot_args+=("--bind=${ROOTFS_DIRECTORY}/proc/.uptime:/proc/uptime")
		fi
		if ! [ -r /proc/version ]; then
		    proot_args+=("--bind=${ROOTFS_DIRECTORY}/proc/.version:/proc/version")
		fi
		if ! [ -r /proc/vmstat ]; then
		    proot_args+=("--bind=${ROOTFS_DIRECTORY}/proc/.vmstat:/proc/vmstat")
		fi
		if ! [ -r /proc/sys/kernel/cap_last_cap ]; then
		    proot_args+=("--bind=${ROOTFS_DIRECTORY}/proc/.sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap")
		fi

		# Bind /tmp to /dev/shm
		proot_args+=("--bind=${ROOTFS_DIRECTORY}/tmp:/dev/shm")
		if ! [ -d "${ROOTFS_DIRECTORY}/tmp" ]; then
		    mkdir -p "${ROOTFS_DIRECTORY}/tmp"
		fi
		chmod 1777 "${ROOTFS_DIRECTORY}/tmp" >/dev/null 2>&1

		# Add host system specific files and directories
		if ! "\${isolated_env}"; then
		    for dir in /apex /data/app /data/dalvik-cache /data/misc/apexdata/com.android.art/dalvik-cache /product /system /vendor; do
		        if ! [ -d "\${dir}" ]; then
		            continue
		        fi
		        dir_mode="\$(stat --format='%a' "\${dir}")"
		        if [[ \${dir_mode:2} =~ ^[157]$ ]]; then
		            proot_args+=("--bind=\${dir}")
		        fi
		    done

		    # Required by termux-api Android 11
		    if [ -e "/linkerconfig/ld.config.txt" ]; then
		        proot_args+=("--bind=/linkerconfig/ld.config.txt")
		    fi

		    # Used by getprop
		    if [ -f /property_contexts ]; then
		        proot_args+=("--bind=/property_contexts")
		    fi

		    proot_args+=("--bind=/data/data/com.termux/cache")
		    proot_args+=("--bind=${TERMUX_FILES_DIR}/home")
		    proot_args+=("--bind=${TERMUX_FILES_DIR}/usr")

		    if [ -d "${TERMUX_FILES_DIR}/apps" ]; then
		        proot_args+=("--bind=${TERMUX_FILES_DIR}/apps")
		    fi

		    if [ -r /storage ]; then
		        proot_args+=("--bind=/storage")
		        proot_args+=("--bind=/storage/emulated/0:/sdcard")
		    else
		        if [ -r /storage/self/primary/ ]; then
		            storage_path="/storage/self/primary"
		        elif [ -r /storage/emulated/0/ ]; then
		            storage_path="/storage/emulated/0"
		        elif [ -r /sdcard/ ]; then
		            storage_path="/sdcard"
		        else
		            storage_path=""
		        fi
		        if [ -n "\${storage_path}" ]; then
		            proot_args+=("--bind=\${storage_path}:/sdcard")
		            proot_args+=("--bind=\${storage_path}:/storage/emulated/0")
		            proot_args+=("--bind=\${storage_path}:/storage/self/primary")
		        fi
		    fi

		    if [ -n "\${EXTERNAL_STORAGE}" ]; then
		        proot_args+=("--bind=\${EXTERNAL_STORAGE}")
		    fi
		fi

		# Bind the tmp folder of the host system to the guest system (ignores --isolated)
		if \${share_tmp}; then
		    proot_args+=("--bind=\${TMPDIR:-${TERMUX_FILES_DIR}/usr/tmp}:/tmp")
		fi

		# Bind custom directories
		if [ \${#custom_bindings} -gt 0 ]; then
		    proot_args+=("\${custom_bindings[@]}")
		fi

		# Modify bindings to protected ports to use a higher port number.
		if \${fix_ports}; then
		    proot_args+=("-p")
		fi

		# Setup the default environment
		proot_args+=("/usr/bin/env" "-i" "\${env_vars[@]}")

		# Enable audio support in distro (for root users, add option '--system')
		if ! pidof -q pulseaudio >/dev/null 2>&1; then
		    pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
		fi

		# Execute launch command
		exec proot "\${proot_args[@]}" "\${@}"
	EOF
	if ln -sfT "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}" >>"${LOG_FILE}" 2>&1 && termux-fix-shebang "${DISTRO_LAUNCHER}" >>"${LOG_FILE}" 2>&1 && chmod 700 "${DISTRO_LAUNCHER}" >>"${LOG_FILE}" 2>&1; then
		msg -s "Done, launcher created successfully!"
	else
		msg -q "Sorry, have I failed to create the ${DISTRO_NAME} launcher."
	fi
}

################################################################################
# Creates a script used to launch the vnc server in the distro                 #
################################################################################
create_vnc_launcher() {
	msg -t "Lemme create a vnc wrapper in ${DISTRO_NAME}."
	local vnc_launcher="${ROOTFS_DIRECTORY}/usr/local/bin/vnc"
	mkdir -p "${ROOTFS_DIRECTORY}/usr/local/bin" >>"${LOG_FILE}" 2>&1 && cat >"${vnc_launcher}" 2>>"${LOG_FILE}" <<-EOF
		#!/bin/bash

		################################################################################
		#                                                                              #
		#     vnc wrapper.                                                             #
		#                                                                              #
		#     This script starts the vnc server.                                       #
		#                                                                              #
		#     Copyright (C) 2023-2025  ${AUTHOR} <${GITHUB}>        #
		#                                                                              #
		################################################################################

		root_check() {
		    if [ "\${EUID}" = "0" ] || [ "\$(whoami)" = "root" ]; then
		        echo "Some applications may not work properly if you run as root."
		        echo -n "Continue anyway? (y/N) "
		        read -r reply
		        case "\${reply}" in
		            y | Y) return ;;
		        esac
		        echo "Cancelled."
		        return 1
		    fi
		}

		clean_tmp() {
		    if [ -n "\${DISPLAY}" ]; then
		        rm -rf "\${TMPDIR:-/tmp}/.X\${DISPLAY}-lock" "/tmp/.X11-unix/X\${DISPLAY}"
		    fi
		}

		set_geometry() {
		    case "\${ORIENTATION}" in
		        p) geometry="\${HEIGHT}x\${WIDTH}" ;;
		        *) geometry="\${WIDTH}x\${HEIGHT}" ;;
		    esac
		}

		start_session() {
		    if [ -e "\${HOME}/.vnc/passwd" ] || [ -e "\${HOME}/.config/tigervnc/passwd" ]; then
		        export HOME="\${HOME:-/root}"
		        export USER="\${USER:-root}"
		        LD_PRELOAD="${LIB_GCC_PATH}"
		        vncserver "\${DISPLAY}" -geometry "\${geometry}" -depth "\${DEPTH}" "\${@}"
		    else
		        vncpasswd && start_session
		    fi
		}

		check_status() {
		    vncserver -list "\${@}"
		}

		kill_session() {
		    vncserver -clean -kill "\${DISPLAY}" "\${@}" && clean_tmp
		}

		print_usage() {
		    echo "Usage \$(basename "\${0}") [<command>]."
		    echo ""
		    echo "Without any command, starts a new vnc session."
		    echo ""
		    echo "Commands include:"
		    echo "  kill             Kill vnc session."
		    echo "  status           List active vnc sessions."
		    echo "  landscape        Use landscape (\${HEIGHT}x\${WIDTH}) orientation. (default)"
		    echo "  potrait          Use potrait (\${WIDTH}x\${HEIGHT}) orientation."
		    echo "  help             Print this message and exit."
		    echo ""
		    echo "Extra options are parsed to the installed vnc server, see vncserver(1)."
		}

		#############
		# Entry point
		#############

		DEPTH=24
		WIDTH=1440
		HEIGHT=720
		ORIENTATION="l"

		opts=()
		while [ "\${#}" -gt 0 ]; do
		    case "\${1}" in
		        p | potrait)
		            ORIENTATION=p
		            ;;
		        l | landscape)
		            ORIENTATION=l
		            ;;
		        s | status)
		            action=s
		            ;;
		        k | kill)
		            action=k
		            ;;
		        h | help)
		            print_usage
		            exit
		            ;;
		        *) opts=("\${opts[@]}" "\${1}") ;;
		    esac
		    shift
		done

		if ! { [ -x "\$(command -v vncserver)" ] && [ -x "\$(command -v vncpasswd)" ]; }; then
		    echo "No vnc server found."
		    exit 1
		fi

		case "\${action}" in
		    k) kill_session "\${opts[@]}" ;;
		    s) check_status "\${opts[@]}" ;;
		    *) root_check && clean_tmp && set_geometry && start_session "\${opts[@]}" ;;
		esac
	EOF
	if chmod 700 "${vnc_launcher}" >>"${LOG_FILE}" 2>&1; then
		msg -s "Done, wrapper created successfully!"
	else
		msg -e "Sorry, have I failed to create the vnc wrapper."
	fi
}

################################################################################
# Makes all the required configurations in the distro                          #
################################################################################
make_configurations() {
	msg -t "Now, lemme make some configurations for you."
	for config in sys_setup ids_setup extra_setups env_setup; do
		status="$(${config} 2>>"${LOG_FILE}")"
		if [ -n "${status//-0/}" ]; then
			msg -e "Oops, ${config//_/ } failed with error code: (${status})"
		fi
	done
	msg -s "Hopefully, that fixes some startup issues."
	unset config status
}

################################################################################
# Sets a custom login shell in distro                                          #
################################################################################
set_user_shell() {
	if [ -x "${ROOTFS_DIRECTORY}/bin/chsh" ] && {
		if [ -z "${shell}" ]; then
			if [ -f "${ROOTFS_DIRECTORY}/etc/passwd" ]; then
				local default_shell="$(grep "${DEFAULT_LOGIN}" "${ROOTFS_DIRECTORY}/etc/passwd" | cut -d: -f7)"
			fi
			if [ -z "${default_shell}" ]; then
				default_shell="unknown"
			fi
			msg -t "Do you want to change the default login shell from:"
			ask -n -- "⇒ '${Y}${default_shell}${C}'?"
		fi
	}; then
		local shells
		mapfile -t shells < <(grep '^/bin' "${ROOTFS_DIRECTORY}"/etc/shells 2>>"${LOG_FILE}" | cut -d'/' -f3 2>>"${LOG_FILE}")
		msg "Installed shells: ${Y}${shells[*]}${C}"
		msg -n "Enter shell name:"
		if [ "${default_shell}" = "unknown" ]; then
			default_shell="${shells[0]}"
		fi
		read -rep " " -i "$(basename "${default_shell}")" shell
		shell="$(basename "${shell}")"
		if [[ ${shells[*]} == *"${shell}"* ]] && [ -x "${ROOTFS_DIRECTORY}/bin/${shell}" ] && {
			distro_exec /bin/chsh -s "/bin/${shell}" root >>"${LOG_FILE}" 2>&1
			if [ "${DEFAULT_LOGIN}" != "root" ]; then
				distro_exec /bin/chsh -s "/bin/${shell}" "${DEFAULT_LOGIN}" >>"${LOG_FILE}" 2>&1
			fi
		}; then
			msg -s "The default login shell is now '${Y}/bin/${shell}${G}'."
		else
			msg -e "Sorry, have I failed to set the default login shell to '${Y}${shell}${R}'."
			ask -n -- "Wanna try again?" && set_user_shell
		fi
		unset shell
	fi
}

################################################################################
# Sets a custom time zone in distro                                            #
################################################################################
set_zone_info() {
	if [ -x "${ROOTFS_DIRECTORY}/bin/ln" ] && {
		if [ -z "${zone}" ]; then
			local default_localtime="$(cat "${ROOTFS_DIRECTORY}/etc/timezone" 2>>"${LOG_FILE}")"
			if [ -z "${default_localtime}" ]; then
				default_localtime="unknown"
			fi
			msg -t "Do you want to change the default local time from:"
			ask -n -- "⇒ '${Y}${default_localtime}${C}'?"
		fi
	}; then
		msg -n "Enter time zone (format='Continent/City'):"
		if [ "${default_localtime}" = "unknown" ]; then
			default_localtime="$(getprop persist.sys.timezone 2>>"${LOG_FILE}")"
		fi
		read -rep " " -i "${default_localtime:-Etc/UTC}" zone
		if [ -f "${ROOTFS_DIRECTORY}/usr/share/zoneinfo/${zone}" ] && echo "${zone}" >"${ROOTFS_DIRECTORY}/etc/timezone" 2>>"${LOG_FILE}" && distro_exec "/bin/ln" -fs -T "/usr/share/zoneinfo/${zone}" "/etc/localtime" 2>>"${LOG_FILE}"; then
			msg -s "The default local time is now '${Y}${zone}${G}'."
		else
			msg -e "Sorry, have I failed to set the local time to '${Y}${zone}${R}'."
			ask -n -- "Wanna try again?" && set_zone_info
		fi
		unset zone
	fi
}

################################################################################
# Makes the necessary clean ups                                                #
################################################################################
prompt_cleanup() {
	if [ -z "${KEEP_ROOTFS_DIRECTORY}" ] && [ -z "${KEEP_ROOTFS_ARCHIVE}" ] && [ -f "${ARCHIVE_NAME}" ]; then
		if ask -n -- -t "Can I ${R}delete${C} the downloaded the rootfs archive to save space?"; then
			msg "Okay, removing '!{Y}${ARCHIVE_NAME}${C}'"
			if remove "${ARCHIVE_NAME}" >>"${LOG_FILE}" 2>&1; then
				msg -s "Done, the rootfs archive is removed!"
			else
				msg -e "Sorry, have I failed to remove the rootfs archive."
			fi
		else
			msg "Alright, lemme leave the rootfs archive."
		fi
	fi
}

################################################################################
# Prints a message for successful installation with other useful information   #
################################################################################
complete_msg() {
	# Just for customizing message
	if [ "${action}" = "install" ]; then
		local name="installed"
	else
		local name="configured"
	fi
	msg -st "That's it, we have now successfuly ${name} ${DISTRO_NAME}."
	msg "You can launch it by executing '${Y}$(basename "${DISTRO_LAUNCHER}")${C}' to login as '${Y}${DEFAULT_LOGIN}${C}'."
	msg "To login as another user, add the user name as an argument."
	msg -t "You can also use '${Y}$(basename "${DISTRO_SHORTCUT}")${C}' as a short form for '${Y}$(basename "${DISTRO_LAUNCHER}")${C}'."
	msg -t "For more information, visit:"
	msg "⇒ ${B}${U}${GITHUB}/${DISTRO_REPOSITORY}${L}${C}"
}

################################################################################
# Uninstalls the rootfs                                                        #
################################################################################
uninstall_rootfs() {
	if [ -d "${ROOTFS_DIRECTORY}" ]; then
		msg -at "You are about to uninstall ${DISTRO_NAME} from:"
		msg "⇒ '${Y}${ROOTFS_DIRECTORY}${C}'."
		msg -a "This action will ${R}delete${C} all files in this directory!"
		if ask -n0 -- -a "Confirm action"; then
			msg -a "Uninstalling ${DISTRO_NAME}."
			if remove "${ROOTFS_DIRECTORY}" "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}" >>"${LOG_FILE}" 2>&1; then
				msg -as "${DISTRO_NAME} uninstall complete."
			else
				msg -aq "${DISTRO_NAME} uninstall failed."
			fi
		else
			msg -aq "Uninstallation cancelled."
		fi
	else
		msg -aq "No rootfs found in '${ROOTFS_DIRECTORY}'."
	fi
}

################################################################################
# Prints the program version information                                       #
################################################################################
print_version() {
	msg -a "${PROGRAM_NAME} version ${Y}${VERSION_NAME}${C}"
	msg -a "Copyright (C) 2023-2025 ${AUTHOR} <${B}${U}${GITHUB}${L}${C}>."
	msg -a "License GPLv3+: GNU GPL version 3 or later <${B}${U}https://gnu.org/licenses/gpl.html${L}${C}>."
	msg -aN "This is free software, you are free to change and redistribute it."
	msg -a "There is NO WARRANTY, to the extent permitted by law."
}

################################################################################
# Prints the program usage information                                         #
################################################################################
print_usage() {
	msg -a "Usage: ${Y}${PROGRAM_NAME}${C} [OPTION] [DIRECTORY]"
	msg -aN "Installs ${DISTRO_NAME} in DIRECTORY."
	msg -a "(default='${Y}${DEFAULT_ROOTFS_DIR}${C}')"
	msg -aN "Options:"
	msg -- "-d, --directory[=PATH] Change directory to PATH before execution."
	msg -- "    --install-only     Installation only (use with caution)."
	msg -- "    --config-only      Configurations only (if already installed)."
	msg -- "-u, --uninstall        Uninstall ${DISTRO_NAME}."
	msg -- "    --color[=WHEN]     Enable/Disable color output if supported"
	msg -- "                       (default='${Y}on${C}'). Valid arguments are:"
	msg -- "                       [always|on] or [never|off]"
	msg -- "-l, --log              Log error messages to ${Y}${PROGRAM_NAME%.sh}.log${C}."
	msg -- "-v, --version          Print program version and exit."
	msg -- "-h, --help             Print help message and exit."
	msg -aN "Note:"
	msg -- "The install directory must be within '${Y}${TERMUX_FILES_DIR}${C}'"
	msg -- "(or its sub-directories) to prevent permission issues."
	msg -aN "For more information, visit:"
	msg -- "⇒ ${B}${U}${GITHUB}/${DISTRO_REPOSITORY}${L}${C}"
}

################################################################################
# Prepares fake content for system data interfaces restricted by Android OS.   #
# Entries are based on values retrieved from Arch Linux (x86_64) running       #
# a VM with 8 CPUs and 8GiB memory (some values edited to fit the distro)      #
# Date: 2023.03.28, Linux 6.2.1                                                #
################################################################################
sys_setup() {
	local status=""
	local dir
	for dir in proc sys sys/.empty; do
		if ! [ -e "${ROOTFS_DIRECTORY}/${dir}" ]; then
			mkdir -p "${ROOTFS_DIRECTORY}/${dir}"
		fi
		chmod 700 "${ROOTFS_DIRECTORY}/${dir}"
	done
	if ! [ -f "${ROOTFS_DIRECTORY}/proc/.loadavg" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.loadavg"
			0.12 0.07 0.02 2/165 765
		EOF
	fi
	status+="-${?}"
	if ! [ -f "${ROOTFS_DIRECTORY}/proc/.stat" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.stat"
			cpu  1957 0 2877 93280 262 342 254 87 0 0
			cpu0 31 0 226 12027 82 10 4 9 0 0
			cpu1 45 0 664 11144 21 263 233 12 0 0
			cpu2 494 0 537 11283 27 10 3 8 0 0
			cpu3 359 0 234 11723 24 26 5 7 0 0
			cpu4 295 0 268 11772 10 12 2 12 0 0
			cpu5 270 0 251 11833 15 3 1 10 0 0
			cpu6 430 0 520 11386 30 8 1 12 0 0
			cpu7 30 0 172 12108 50 8 1 13 0 0
			intr 127541 38 290 0 0 0 0 4 0 1 0 0 25329 258 0 5777 277 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
			ctxt 140223
			btime 1680020856
			processes 772
			procs_running 2
			procs_blocked 0
			softirq 75663 0 5903 6 25375 10774 0 243 11685 0 21677
		EOF
	fi
	status+="-${?}"
	if ! [ -f "${ROOTFS_DIRECTORY}/proc/.uptime" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.uptime"
			5400.0 0.0
		EOF
	fi
	status+="-${?}"
	if ! [ -f "${ROOTFS_DIRECTORY}/proc/.version" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.version"
			Linux version ${KERNEL_RELEASE} (proot@termux) (gcc (GCC) 12.2.1 20230201, GNU ld (GNU Binutils) 2.40) #1 SMP PREEMPT_DYNAMIC Wed, 01 Mar 2023 00:00:00 +0000
		EOF
	fi
	status+="-${?}"
	if ! [ -f "${ROOTFS_DIRECTORY}/proc/.vmstat" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.vmstat"
			nr_free_pages 1743136
			nr_zone_inactive_anon 179281
			nr_zone_active_anon 7183
			nr_zone_inactive_file 22858
			nr_zone_active_file 51328
			nr_zone_unevictable 642
			nr_zone_write_pending 0
			nr_mlock 0
			nr_bounce 0
			nr_zspages 0
			nr_free_cma 0
			numa_hit 1259626
			numa_miss 0
			numa_foreign 0
			numa_interleave 720
			numa_local 1259626
			numa_other 0
			nr_inactive_anon 179281
			nr_active_anon 7183
			nr_inactive_file 22858
			nr_active_file 51328
			nr_unevictable 642
			nr_slab_reclaimable 8091
			nr_slab_unreclaimable 7804
			nr_isolated_anon 0
			nr_isolated_file 0
			workingset_nodes 0
			workingset_refault_anon 0
			workingset_refault_file 0
			workingset_activate_anon 0
			workingset_activate_file 0
			workingset_restore_anon 0
			workingset_restore_file 0
			workingset_nodereclaim 0
			nr_anon_pages 7723
			nr_mapped 8905
			nr_file_pages 253569
			nr_dirty 0
			nr_writeback 0
			nr_writeback_temp 0
			nr_shmem 178741
			nr_shmem_hugepages 0
			nr_shmem_pmdmapped 0
			nr_file_hugepages 0
			nr_file_pmdmapped 0
			nr_anon_transparent_hugepages 1
			nr_vmscan_write 0
			nr_vmscan_immediate_reclaim 0
			nr_dirtied 0
			nr_written 0
			nr_throttled_written 0
			nr_kernel_misc_reclaimable 0
			nr_foll_pin_acquired 0
			nr_foll_pin_released 0
			nr_kernel_stack 2780
			nr_page_table_pages 344
			nr_sec_page_table_pages 0
			nr_swapcached 0
			pgpromote_success 0
			pgpromote_candidate 0
			nr_dirty_threshold 356564
			nr_dirty_background_threshold 178064
			pgpgin 890508
			pgpgout 0
			pswpin 0
			pswpout 0
			pgalloc_dma 272
			pgalloc_dma32 261
			pgalloc_normal 1328079
			pgalloc_movable 0
			pgalloc_device 0
			allocstall_dma 0
			allocstall_dma32 0
			allocstall_normal 0
			allocstall_movable 0
			allocstall_device 0
			pgskip_dma 0
			pgskip_dma32 0
			pgskip_normal 0
			pgskip_movable 0
			pgskip_device 0
			pgfree 3077011
			pgactivate 0
			pgdeactivate 0
			pglazyfree 0
			pgfault 176973
			pgmajfault 488
			pglazyfreed 0
			pgrefill 0
			pgreuse 19230
			pgsteal_kswapd 0
			pgsteal_direct 0
			pgsteal_khugepaged 0
			pgdemote_kswapd 0
			pgdemote_direct 0
			pgdemote_khugepaged 0
			pgscan_kswapd 0
			pgscan_direct 0
			pgscan_khugepaged 0
			pgscan_direct_throttle 0
			pgscan_anon 0
			pgscan_file 0
			pgsteal_anon 0
			pgsteal_file 0
			zone_reclaim_failed 0
			pginodesteal 0
			slabs_scanned 0
			kswapd_inodesteal 0
			kswapd_low_wmark_hit_quickly 0
			kswapd_high_wmark_hit_quickly 0
			pageoutrun 0
			pgrotated 0
			drop_pagecache 0
			drop_slab 0
			oom_kill 0
			numa_pte_updates 0
			numa_huge_pte_updates 0
			numa_hint_faults 0
			numa_hint_faults_local 0
			numa_pages_migrated 0
			pgmigrate_success 0
			pgmigrate_fail 0
			thp_migration_success 0
			thp_migration_fail 0
			thp_migration_split 0
			compact_migrate_scanned 0
			compact_free_scanned 0
			compact_isolated 0
			compact_stall 0
			compact_fail 0
			compact_success 0
			compact_daemon_wake 0
			compact_daemon_migrate_scanned 0
			compact_daemon_free_scanned 0
			htlb_buddy_alloc_success 0
			htlb_buddy_alloc_fail 0
			cma_alloc_success 0
			cma_alloc_fail 0
			unevictable_pgs_culled 27002
			unevictable_pgs_scanned 0
			unevictable_pgs_rescued 744
			unevictable_pgs_mlocked 744
			unevictable_pgs_munlocked 744
			unevictable_pgs_cleared 0
			unevictable_pgs_stranded 0
			thp_fault_alloc 13
			thp_fault_fallback 0
			thp_fault_fallback_charge 0
			thp_collapse_alloc 4
			thp_collapse_alloc_failed 0
			thp_file_alloc 0
			thp_file_fallback 0
			thp_file_fallback_charge 0
			thp_file_mapped 0
			thp_split_page 0
			thp_split_page_failed 0
			thp_deferred_split_page 1
			thp_split_pmd 1
			thp_scan_exceed_none_pte 0
			thp_scan_exceed_swap_pte 0
			thp_scan_exceed_share_pte 0
			thp_split_pud 0
			thp_zero_page_alloc 0
			thp_zero_page_alloc_failed 0
			thp_swpout 0
			thp_swpout_fallback 0
			balloon_inflate 0
			balloon_deflate 0
			balloon_migrate 0
			swap_ra 0
			swap_ra_hit 0
			ksm_swpin_copy 0
			cow_ksm 0
			zswpin 0
			zswpout 0
			direct_map_level2_splits 29
			direct_map_level3_splits 0
			nr_unstable 0
		EOF
	fi
	status+="-${?}"
	if ! [ -f "${ROOTFS_DIRECTORY}/proc/.sysctl_entry_cap_last_cap" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.sysctl_entry_cap_last_cap"
			40
		EOF
	fi
	status+="-${?}"
	if ! [ -f "${ROOTFS_DIRECTORY}/proc/.sysctl_inotify_max_user_watches" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.sysctl_inotify_max_user_watches"
			4096
		EOF
	fi
	status+="-${?}"
	echo -n "${status}"
}

################################################################################
# Writes important environment variables to /etc/environment.                  #
################################################################################
env_setup() {
	local marker="${PROGRAM_NAME} variables"
	local env_file="${ROOTFS_DIRECTORY}/etc/environment"
	local status=""
	sed -i "/^### start\s${marker}\s###$/,/^###\send\s${marker}\s###$/d; /^$/d" "${env_file}"
	{
		echo -e "\n### start ${marker} ###"
		echo -e "# These variables were added by ${PROGRAM_NAME} during"
		echo -e "# the rootfs installation/configuration and are updated"
		echo -e "# automatically every time ${PROGRAM_NAME} is executed.\n"
		cat >>"${env_file}" <<-EOF
			# Environment variables
			export PATH="${DEFAULT_PATH}:${TERMUX_FILES_DIR}/usr/local/bin:${TERMUX_FILES_DIR}/usr/bin"
			export TERM="${TERM:-xterm-256color}"
			if [ -z "\${LANG}" ]; then
			    export LANG="en_US.UTF-8"
			fi

			# pulseaudio server
			export PULSE_SERVER=127.0.0.1

			# vncserver display
			export DISPLAY=:0

			# Misc variables
			export MOZ_FAKE_NO_SANDBOX=1
			export TMPDIR="/tmp"
		EOF
	} >>"${env_file}"
	status+="-${?}"
	echo -e "\n# Host system variables" >>"${env_file}"
	for var in COLORTERM ANDROID_DATA ANDROID_ROOT ANDROID_ART_ROOT ANDROID_I18N_ROOT ANDROID_RUNTIME_ROOT ANDROID_TZDATA_ROOT BOOTCLASSPATH DEX2OATBOOTCLASSPATH; do
		if [ -n "${!var}" ]; then
			echo "export ${var}=\"${!var}\"" >>"${env_file}"
		fi
	done
	status+="-${?}"
	unset var
	echo -e "\n### end ${marker} ###\n" >>"${env_file}"
	# Fix PATH in some configuration files.
	# for f in /etc/bash.bashrc /etc/profile; do # /etc/login.defs
	# 	! [ -e "${ROOTFS_DIRECTORY}${f}" ] && continue
	# 	sed -i -E "s@\<(PATH=)(\"?[^\"[:space:]]+(\"|\$|\>))@\1\"${DEFAULT_PATH}\"@g" "${ROOTFS_DIRECTORY}${f}"
	# done
	# status+="-${?}"
	unset f
	echo -n "${status}"
}

################################################################################
# Adds android-specific UIDs/GIDs to /etc/group and /etc/gshadow               #
################################################################################
ids_setup() {
	local status=""
	chmod u+rw "${ROOTFS_DIRECTORY}/etc/passwd" "${ROOTFS_DIRECTORY}/etc/shadow" "${ROOTFS_DIRECTORY}/etc/group" "${ROOTFS_DIRECTORY}/etc/gshadow" >>"${LOG_FILE}" 2>&1
	status+="-${?}"
	if ! grep -qe ':Termux:/:/sbin/nologin' "${ROOTFS_DIRECTORY}/etc/passwd"; then
		echo "aid_$(id -un):x:$(id -u):$(id -g):Termux:/:/sbin/nologin" >>"${ROOTFS_DIRECTORY}/etc/passwd"
	fi
	status+="-${?}"
	if ! grep -qe ':18446:0:99999:7:' "${ROOTFS_DIRECTORY}/etc/shadow"; then
		echo "aid_$(id -un):*:18446:0:99999:7:::" >>"${ROOTFS_DIRECTORY}/etc/shadow"
	fi
	status+="-${?}"
	while read -r group_name group_id; do
		if ! grep -qe "${group_name}" "${ROOTFS_DIRECTORY}/etc/group"; then
			echo "aid_${group_name}:x:${group_id}:root,aid_$(id -un)" >>"${ROOTFS_DIRECTORY}/etc/group"
		fi
		if ! grep -qe "${group_name}" "${ROOTFS_DIRECTORY}/etc/gshadow"; then
			echo "aid_${group_name}:*::root,aid_$(id -un)" >>"${ROOTFS_DIRECTORY}/etc/gshadow"
		fi
	done < <(paste <(id -Gn | tr ' ' '\n') <(id -G | tr ' ' '\n'))
	unset group_name group_id
	status+="-${?}"
	echo -n "${status}"
}

################################################################################
# Configures root access, sets the nameservers and sets host information       #
################################################################################
extra_setups() {
	local status=""
	if [ -f "${ROOTFS_DIRECTORY}/root/.bash_profile" ]; then
		sed -i '/^if/,/^fi/d' "${ROOTFS_DIRECTORY}/root/.bash_profile"
	fi
	status+="-${?}"
	if [ -x "${ROOTFS_DIRECTORY}/bin/passwd" ]; then
		distro_exec "/bin/passwd" -d root
		if [ "${DEFAULT_LOGIN}" != "root" ]; then
			distro_exec "/bin/passwd" -d "${DEFAULT_LOGIN}"
		fi
	fi >>"${LOG_FILE}" 2>&1
	status+="-${?}"
	local dir="${ROOTFS_DIRECTORY}/bin"
	if [ -x "${dir}/sudo" ]; then
		chmod +s "${dir}/sudo"
		if [ "${DEFAULT_LOGIN}" != "root" ]; then
			echo "${DEFAULT_LOGIN}   ALL=(ALL:ALL) NOPASSWD: ALL" >"${ROOTFS_DIRECTORY}/etc/sudoers.d/${DEFAULT_LOGIN}"
		fi
		echo "Set disable_coredump false" >"${ROOTFS_DIRECTORY}/etc/sudo.conf"
	fi
	if [ -x "${dir}/su" ]; then
		chmod +s "${dir}/su"
	fi
	status+="-${?}"
	local resolv_conf="${ROOTFS_DIRECTORY}/etc/resolv.conf"
	chmod 777 -R "${resolv_conf}"
	rm -f "${resolv_conf}"
	if [ -n "${PREFIX}" ] && [ -f "${PREFIX}/etc/resolv.conf" ]; then
		cp "${PREFIX}/etc/resolv.conf" "${resolv_conf}"
	elif touch "${resolv_conf}" && chmod +w "${resolv_conf}"; then
		cat >"${resolv_conf}" <<-EOF
			nameserver 8.8.8.8
			nameserver 8.8.4.4
		EOF
	fi
	status+="-${?}"
	cat >"${ROOTFS_DIRECTORY}/etc/hosts" <<-EOF
		# IPv4
		127.0.0.1   localhost.localdomain localhost

		# IPv6
		::1         localhost.localdomain localhost ip6-localhost ip6-loopback
		fe00::0     ip6-localnet
		ff00::0     ip6-mcastprefix
		ff02::1     ip6-allnodes
		ff02::2     ip6-allrouters
		ff02::3     ip6-allhosts
	EOF
	status+="-${?}"
	echo -n "${status}"
}

################################################################################
# Executes a command in the distro.                                            #
################################################################################
distro_exec() {
	unset LD_PRELOAD
	proot -L \
		--cwd=/ \
		--root-id \
		--bind=/dev \
		--bind="/dev/urandom:/dev/random" \
		--bind=/proc \
		--bind="/proc/self/fd:/dev/fd" \
		--bind="/proc/self/fd/0:/dev/stdin" \
		--bind="/proc/self/fd/1:/dev/stdout" \
		--bind="/proc/self/fd/2:/dev/stderr" \
		--bind=/sys \
		--bind="${ROOTFS_DIRECTORY}/proc/.loadavg:/proc/loadavg" \
		--bind="${ROOTFS_DIRECTORY}/proc/.stat:/proc/stat" \
		--bind="${ROOTFS_DIRECTORY}/proc/.uptime:/proc/uptime" \
		--bind="${ROOTFS_DIRECTORY}/proc/.version:/proc/version" \
		--bind="${ROOTFS_DIRECTORY}/proc/.vmstat:/proc/vmstat" \
		--bind="${ROOTFS_DIRECTORY}/proc/.sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap" \
		--bind="${ROOTFS_DIRECTORY}/proc/.sysctl_inotify_max_user_watches:/proc/sys/fs/inotify/max_user_watches" \
		--bind="${ROOTFS_DIRECTORY}/sys/.empty:/sys/fs/selinux" \
		--kernel-release="${KERNEL_RELEASE}" \
		--rootfs="${ROOTFS_DIRECTORY}" \
		--link2symlink \
		--kill-on-exit \
		/bin/env -i \
		"HOME=/root" \
		"LANG=C.UTF-8" \
		"PATH=${DEFAULT_PATH}" \
		"TERM=${TERM:-xterm-256color}" \
		"TMPDIR=/tmp" \
		"${@}"
}

################################################################################
# Initializes the color variables                                              #
################################################################################
set_colors() {
	if [ -x "$(command -v tput)" ] && [ "$(tput colors)" -ge 8 ] && [[ ${COLOR_SUPPORT} =~ "on"|"always"|"auto" ]]; then
		R="$(echo -ne "sgr0\nbold\nsetaf 1" | tput -S)"
		G="$(echo -ne "sgr0\nbold\nsetaf 2" | tput -S)"
		Y="$(echo -ne "sgr0\nbold\nsetaf 3" | tput -S)"
		B="$(echo -ne "sgr0\nbold\nsetaf 4" | tput -S)"
		C="$(echo -ne "sgr0\nbold\nsetaf 6" | tput -S)"
		I="$(tput civis)" # hide cursor
		V="$(tput cvvis)" # show cursor
		U="$(tput smul)"  # underline
		L="$(tput rmul)"  # remove underline
		N="$(tput sgr0)"  # remove color
	else
		R=""
		G=""
		Y=""
		B=""
		C=""
		I=""
		V=""
		U=""
		L=""
		N=""
	fi
}

################################################################################
# Removes files                                                                #
################################################################################
remove() {
	chmod 777 -R "${@}"
	rm -rf "${@}"
}

################################################################################
# Prints parsed message to the standard output. All messages MUST be printed   #
# with this function                                                           #
# Allows options (see case inside)                                             #
################################################################################
msg() {
	local color="${C}"
	local prefix="   "
	local postfix=""
	local quit=false
	local append=false
	local extra_msg=""
	local list_items=false
	local lead_newline=false
	local trail_newline=true
	while getopts ":tseanNqm:l" opt; do
		case "${opt}" in
			t)
				prefix="\n${Y}⇒ "
				continue
				;;
			s)
				color="${G}"
				continue
				;;
			e)
				color="${R}"
				continue
				;;
			a)
				append=true
				continue
				;;
			n)
				trail_newline=false
				continue
				;;
			N)
				lead_newline=true
				continue
				;;
			q)
				color="${R}"
				quit=true
				continue
				;;
			m)
				local msgs=(
					"An active internet connection is required."
					"See '${Y}${PROGRAM_NAME} --help${C}' for more information.")
				extra_msg="${C}${msgs[${OPTARG}]}${N}"
				continue
				;;
			l)
				list_items=true
				color="${G}"
				continue
				;;
			*) ;;
		esac
	done
	shift $((OPTIND - 1))
	unset OPTARG OPTIND opt
	if ${list_items}; then
		local i=1
		for item in "${@}"; do
			echo -ne "\r${prefix}    ${color}<${Y}${i}${color}> ${item}${postfix}${N}\n"
			((i++))
		done
		unset item
	else
		local args
		local message="${*}"
		if [ -z "${message}" ] && [ -n "${extra_msg}" ]; then
			message="${extra_msg}"
			extra_msg=""
		fi
		while true; do
			args=""
			${lead_newline} && args+="\n"
			${append} || args+="\r${prefix}"
			args+="${color}${message}${postfix}${N}"
			${trail_newline} && args+="\n"
			echo -ne "${args}"
			if [ -n "${extra_msg}" ]; then
				message="${extra_msg}"
				extra_msg=""
			else
				break
			fi
		done
	fi
	if ${quit}; then
		exit 1
	fi
}

################################################################################
# Asks the user a Y/N question and returns 0/1 respectively                    #
# Allows options (see case inside)                                             #
# Options after -- are parsed to msg (see msg description)                     #
################################################################################
ask() {
	local prompt
	local default
	local retries=1
	while getopts ":yn0123456789" opt; do
		case "${opt}" in
			y)
				prompt="Y/n"
				default="Y"
				continue
				;;
			n)
				prompt="y/N"
				default="N"
				continue
				;;
			[0-9])
				retries=${opt}
				continue
				;;
			*)
				prompt="y/n"
				default=""
				;;
		esac
	done
	shift $((OPTIND - 1))
	unset OPTARG OPTIND opt
	while true; do
		msg -n "${@}" "(${prompt}): "
		read -ren 1 reply
		if [ -z "${reply}" ]; then
			reply="${default}"
		fi
		case "${reply}" in
			Y | y) return 0 ;;
			N | n) return 1 ;;
		esac
		if [ -n "${default}" ] && [ "${retries}" -eq 0 ]; then
			case "${default}" in
				y | Y) return 0 ;;
				n | N) return 1 ;;
			esac
		fi
		((retries--))
	done
	unset reply
}

################################################################################
# Entry point of program                                                       #
################################################################################

# Project information
GITHUB="https://github.com/jorexdeveloper"
AUTHOR="Jore"

# Default env path
DEFAULT_PATH="/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/system/bin:/system/xbin"

# Output for log messages
LOG_FILE="/dev/null"

# Enable color in terminals (fd 1 for stdout)
if [ -t 1 ]; then
	COLOR_SUPPORT=on
fi

# Update color variables
set_colors

# Permissions for new files
umask 0022

# Main actions
ACTION_INSTALL=true
ACTION_CONFIGURE=true
ACTION_UNINSTALL=false

# Process command line options
ARGS=()
while [ "${#}" -gt 0 ]; do
	case "${1}" in
		-d | --directory*)
			optarg="${1/--directory/}"
			optarg="${optarg/=/}"
			if [ "${optarg}" = "-d" ] || [ -z "${optarg}" ]; then
				shift
				optarg="${1}"
			fi
			if [ -z "${optarg}" ]; then
				msg -aqm1 "Option '-d' or '--directory' requires an argument."
			fi
			if [ -d "${optarg}" ] && [ -r "${optarg}" ]; then
				cd "${optarg}" || exit 1
			else
				msg -aq "'${optarg}' is not a readable directory!"
			fi
			unset optarg
			;;
		--install-only)
			ACTION_CONFIGURE=false
			;;
		--config-only)
			ACTION_INSTALL=false
			;;
		-u | --uninstall)
			ACTION_UNINSTALL=true
			;;
		-l | --log)
			LOG_FILE="${PROGRAM_NAME%.sh}.log"
			;;
		-v | --version)
			print_version
			exit
			;;
		-h | --help)
			print_usage
			exit
			;;
		--color*)
			optarg="${1/--color/}"
			optarg="${optarg/=/}"
			if [ -z "${optarg}" ]; then
				shift
				optarg="${1}"
			fi
			case "${optarg}" in
				on | off | always | never)
					COLOR_SUPPORT="${optarg}"
					set_colors
					;;
				"") msg -aqm1 "Option '--color' requires an argument." ;;
				*)
					msg -aqm1 "Unrecognized color argument '${optarg}'."
					;;
			esac
			unset optarg
			;;
		# Developer options to speed up testing
		-R | --no-safety-check)
			safety_check=false
			;;
		-P | --no-check-pkgs)
			check_pkgs=false
			;;
		-V | --no-verify-rootfs-archive)
			verify_rootfs_archive=false
			;;
		-L | --no-create-rootfs-launcher)
			create_rootfs_launcher=false
			;;
		-K | --no-create-vnc-launcher)
			create_vnc_launcher=false
			;;
		-J | --no-make-configurations)
			make_configurations=false
			;;
		-S | --no-set-user-shell)
			set_user_shell=false
			;;
		-Z | --no-set-zone-info)
			set_zone_info=false
			;;
		-C | --no-prompt-cleanup)
			prompt_cleanup=false
			;;
		-M | --no-complete-msg)
			complete_msg=false
			;;
		--)
			shift
			ARGS=("${ARGS[@]}" "${@}")
			break
			;;
		-*)
			msg -aqm1 "Unrecognized option '${1}'."
			;;
		*)
			ARGS=("${ARGS[@]}" "${1}")
			;;
	esac
	shift
done
set -- "${ARGS[@]}"
unset ARGS

# Prevent extra arguments except directory
if [ "${#}" -gt 1 ]; then
	msg -aqm1 "Received too many arguments."
fi

# Set the rootfs directory
if [ -n "${1}" ]; then
	ROOTFS_DIRECTORY="$(realpath "${1}")"
	if [[ "${ROOTFS_DIRECTORY}" != "${TERMUX_FILES_DIR}"* ]]; then
		msg -aqm1 "The install directory '${Y}${ROOTFS_DIRECTORY}${R}' is not within '${Y}${TERMUX_FILES_DIR}${R}'."
	fi
else
	ROOTFS_DIRECTORY="${DEFAULT_ROOTFS_DIR}"
fi

# Uninstall rootfs
if ${ACTION_UNINSTALL}; then
	uninstall_rootfs
	exit
fi

# Pre install actions
if ${ACTION_INSTALL} || ${ACTION_CONFIGURE}; then
	pre_check_actions # External function
	${safety_check:-:} &&
		safety_check
	# For some message customizations
	if ${ACTION_INSTALL}; then
		action="install"
	else
		action=configure
	fi
	clear
	distro_banner # External function
	print_intro
	check_arch
	${check_pkgs:-:} &&
		check_pkgs
	post_check_actions # External function
	msg -t "I shall now ${action} ${DISTRO_NAME} in:"
	msg "⇒ ${Y}${ROOTFS_DIRECTORY}${C}"
fi

# Install actions
if ${ACTION_INSTALL}; then
	check_rootfs_directory
	pre_install_actions # External function
	download_rootfs_archive
	${verify_rootfs_archive:-:} &&
		verify_rootfs_archive
	extract_rootfs_archive
	post_install_actions # External function
fi

# Create launchers
if ${ACTION_INSTALL} || ${ACTION_CONFIGURE}; then
	${create_rootfs_launcher:-:} &&
		create_rootfs_launcher
	${create_vnc_launcher:-:} &&
		create_vnc_launcher
fi

# Post install configurations
if ${ACTION_CONFIGURE}; then
	pre_config_actions # External function
	${make_configurations:-:} &&
		make_configurations
	post_config_actions # External function
	${set_user_shell:-:} &&
		set_user_shell
	${set_zone_info:-:} &&
		set_zone_info
fi

# Clean up files
if ${ACTION_INSTALL}; then
	${prompt_cleanup:-:} &&
		prompt_cleanup
fi

# Print message for successful completion
if ${ACTION_INSTALL} || ${ACTION_CONFIGURE}; then
	pre_complete_actions # External function
	${complete_msg:-:} &&
		complete_msg
	post_complete_actions # External function
fi
