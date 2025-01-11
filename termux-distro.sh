#!/data/data/com.termux/files/usr/bin/bash

################################################################################
#                                                                              #
#     Termux Distro Template.                                                  #
#                                                                              #
#     Template for installing Linux Distro in Termux.                          #
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

################################################################################
# Prevents running this program in the wrong environment.                      #
################################################################################
safety_check() {
	if [ "${EUID}" = "0" ] || [ "$(id -u)" = "0" ]; then
		msg -ae "Nope, I can't let you run this program with root permissions!"
		msg -an "The least of your problems will be damaging system files."
		msg -aq ""
	fi
	local pid="$(grep TracerPid "/proc/$$/status" | cut -d $'\t' -f 2)"
	if [ "${pid}" != 0 ]; then
		local name="$(grep Name "/proc/${pid}/status" | cut -d $'\t' -f 2)"
		if [ "$name" = "proot" ]; then
			msg -ae "Nope, I can't let you run this program within proot!"
			msg -an "The least of your problems will be a very slow environment."
			msg -aq ""
		fi
	fi
}

################################################################################
# Prints the distro an introducing message.                                    #
################################################################################
print_intro() {
	msg -t "Hey there, I'm ${AUTHOR}."
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
	if [ -x "$(command -v pkg)" ] && pkg update -y < <(echo -e "y\ny\ny\ny\ny") &>>"${LOG_FILE}" && pkg upgrade -y < <(echo -e "y\ny\ny\ny\ny") &>>"${LOG_FILE}"; then # || apt-get -qq -o=Dpkg::Use-Pty=0 update -y &>>"${LOG_FILE}" || apt-get -qq -o=Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" dist-upgrade -y &>>"${LOG_FILE}"; then
		msg -s "Yup, Everything looks good!"
	else
		msg -qm0 "Sorry, have I failed to update your packages."
	fi
	msg -t "Lemme also check if all the required packages are installed."
	for package in awk basename curl du proot pulseaudio readlink realpath sed tar unzip xz; do
		if ! [ -x "$(command -v "${package}")" ]; then
			msg "Oops, looks like '${Y}${package}${C}' is missing! Let me install it now."
			if pkg install -y "${package}" < <(echo -e "y\ny\ny\ny\ny") &>>"${LOG_FILE}"; then # || apt-get -qq -o=Dpkg::Use-Pty=0 install -y "${package}" &>>"${LOG_FILE}"; then
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
				msg -l "Use" "Delete" "Abort (default)"
				msg -n "Select action: "
				read -ren 1 reply
				case "${reply}" in
					1 | u | U)
						msg "Okay, I shall proceed with it."
						KEEP_ROOTFS_DIRECTORY=1
						return
						;;
					2 | d | D) ;;
					*) msg -q "Alright, aborting!" ;;
				esac
				unset reply
			else
				rmdir "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}"
				return
			fi
		else
			msg -t "Wait, There is a file of size (${Y}$(du -sh "${ROOTFS_DIRECTORY}" 2>>"${LOG_FILE}" | awk '{print $1}' 2>>"${LOG_FILE}")${C}) with the same name as the rootfs directory!"
			if ! ask -n "Should I delete the it and proceed?"; then
				msg -q "Alright, aborting!"
			fi
		fi
		msg "Okay, deleting '${Y}${ROOTFS_DIRECTORY}${C}'!"
		if chmod 777 -R "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}" && rm -rf "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}"; then
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
				if ! ask -n "Should I delete it and download a new one?"; then
					msg "Okay, lemme use it."
					KEEP_ROOTFS_ARCHIVE=1
					return
				fi
			else
				msg -t "Wait, There is a non-file with the same name as the rootfs archive!"
				if ! ask -n "Should I delete it and proceed?"; then
					msg -q "Alright, aborting!"
				fi
			fi
			msg "Okay, deleting '${Y}${ARCHIVE_NAME}${C}'."
			if chmod 777 -R "${ARCHIVE_NAME}" &>>"${LOG_FILE}" && rm -rf "${ARCHIVE_NAME}" &>>"${LOG_FILE}"; then
				msg -s "Done, let's proceed."
			else
				msg -q "Sorry, have I failed to delete '${Y}${ARCHIVE_NAME}${R}'."
			fi
		fi
		local tmp_dload="${ARCHIVE_NAME}.pending"
		msg -t "Alright, now lemme download the rootfs archive. This might take a while."
		if curl --disable --fail --location --progress-meter --retry-connrefused --retry 0 --retry-delay 3 --continue-at - --output "${tmp_dload}" "${BASE_URL}/${ARCHIVE_NAME}"; then
			mv "${tmp_dload}" "${ARCHIVE_NAME}" &>>"${LOG_FILE}"
			msg -s "Great, the rootfs download is complete!"
		else
			chmod 777 -R "${tmp_dload}" &>>"${LOG_FILE}" && rm -rf "${tmp_dload}" &>>"${LOG_FILE}"
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
		if grep --regexp="${ARCHIVE_NAME}$" <<<"${TRUSTED_SHASUMS}" 2>>"${LOG_FILE}" | "${SHASUM_CMD}" --quiet --check &>>"${LOG_FILE}"; then
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
		msg -t "Now, grab a coffee while I extract the rootfs archive. This will take a while."
		trap "msg -e \"Extraction process interupted. Clearing cache.                 \";echo -ne \"${N}${V}\";chmod 777 -R \"${ROOTFS_DIRECTORY}\" &>>\"${LOG_FILE}\";rm -rf \"${ROOTFS_DIRECTORY}\" &>>\"${LOG_FILE}\";exit 1" HUP INT TERM
		mkdir -p "${ROOTFS_DIRECTORY}"
		set +e
		if proot --link2symlink tar --strip="${ARCHIVE_STRIP_DIRS}" --delay-directory-restore --preserve-permissions --warning=no-unknown-keyword --extract --auto-compress --exclude="dev" --file="${ARCHIVE_NAME}" --directory="${ROOTFS_DIRECTORY}" --checkpoint=1 --checkpoint-action=ttyout="${I}${Y}   I have extracted %{}T in %ds so far.%*\r${N}${V}" &>>"${LOG_FILE}"; then
			msg -s "Finally, I am done extracting the rootfs archive!."
		else
			chmod 777 -R "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}" && rm -rf "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}"
			msg -q "Sorry, have I failed to extract the rootfs archive."
		fi
		set -e
		trap - HUP INT TERM
	fi
}

################################################################################
# Creates a script used to login into the distro                               #
################################################################################
create_rootfs_launcher() {
	msg -t "Lemme create a command to launch ${DISTRO_NAME}."
	mkdir -p "$(dirname "${DISTRO_LAUNCHER}")" &>>"${LOG_FILE}" && cat >"${DISTRO_LAUNCHER}" 2>>"${LOG_FILE}" <<-EOF
		#!${TERMUX_FILES_DIR}/usr/bin/bash

		################################################################################
		#                                                                              #
		#     ${DISTRO_NAME} launcher, version ${VERSION_NAME}                         #
		#                                                                              #
		#     Launches ${DISTRO_NAME}.                                                 #
		#                                                                              #
		#     Copyright (C) 2023-2025  ${AUTHOR} <${GITHUB}>        #
		#                                                                              #
		################################################################################

		custom_ids=""
		login_name="${DEFAULT_LOGIN}"
		distro_command=""
		custom_bindings=""
		share_tmp_dir=false
		no_sysvipc=false
		no_kill_on_exit=false
		no_link2symlink=false
		isolated_env=false
		protect_ports=false
		use_termux_ids=false
		kernel_release="${KERNEL_RELEASE}"

		# Process command line arguments
		while [ "\${#}" -gt 0 ]; do
		    case "\${1}" in
		        --command*)
		            optarg="\${1//--command/}"
		            optarg="\${optarg//=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--command' requires an argument."
		                exit 1
		            fi
		            distro_command="\${optarg}"
		            unset optarg
		            ;;
		        --bind*)
		            optarg="\${1//--bind/}"
		            optarg="\${optarg//=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--bind' requires an argument."
		                exit 1
		            fi
		            custom_bindings+=" --bind=\${optarg}"
		            unset optarg
		            ;;
		        --share-tmp-dir)
		            share_tmp_dir=true
		            ;;
		        --no-sysvipc)
		            no_sysvipc=true
		            ;;
		        --no-link2symlink)
		            no_link2symlink=true
		            ;;
		        --no-kill-on-exit)
		            no_kill_on_exit=true
		            ;;
		        --isolated)
		            isolated_env=true
		            ;;
		        --protect-ports)
		            protect_ports=true
		            ;;
		        --use-termux-ids)
		            use_termux_ids=true
		            ;;
		        --id*)
		            optarg="\${1//--id/}"
		            optarg="\${optarg//=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--id' requires an argument."
		                exit 1
		            fi
		            custom_ids="\${optarg}"
		            unset optarg
		            ;;
		        --kernel-release*)
		            optarg="\${1//--kernel-release/}"
		            optarg="\${optarg//=/}"
		            if [ -z "\${optarg}" ]; then
		                shift
		                optarg="\${1}"
		            fi
		            if [ -z "\${optarg}" ]; then
		                echo "Option '--kernel-release' requires an argument."
		                exit 1
		            fi
		            kernel_release="\${optarg}"
		            unset optarg
		            ;;
		        -h | --help)
		            echo "Usage: $(basename "${DISTRO_LAUNCHER}") [OPTION]... [USERNAME]"
		            echo ""
		            echo "Login or execute a comand in ${DISTRO_NAME} as USERNAME (default=${DEFAULT_LOGIN})."
		            echo ""
		            echo "Options:"
		            echo "      --command[=COMMAND]    Execute COMAND in distro."
		            echo "      --bind[=PATH]          Make the content of PATH accessible in the"
		            echo "                             guest rootfs."
		            echo "      --share-tmp-dir        Bind TMPDIR (${TERMUX_FILES_DIR}/usr/tmp"
		            echo "                             if not set) to /tmp in the guest rootfs."
		            echo "      --no-sysvipc           Do not handle System V IPC syscalls in proot"
		            echo "                             (WARNING: use with caution)."
		            echo "      --no-link2symlink      Do not fake hard links with symbolic links"
		            echo "                             (WARNING: prevents hard link support in distro)."
		            echo "      --no-kill-on-exit      Do not kill running processes on command exit."
		            echo "      --isolated             Do not include host specific variables and"
		            echo "                             directories."
		            echo "      --protect-ports        Modify bindings to protected ports to use a"
		            echo "                             higher port number."
		            echo "      --use-termux-ids       Make the current user and group appear as that"
		            echo "                             of termux. (ignores '--id')"
		            echo "      --id[=UID:GID]         Make the current user and group appear as UID"
		            echo "                             and GID."
		            echo "      --kernel-release[=STRING]"
		            echo "                             Make current kernel release appear as"
		            echo "                             STRING. (default='${KERNEL_RELEASE}')"
		            echo "  -v, --version              Print distro version and exit."
		            echo "  -h, --help                 Print this information and exit."
		            echo ""
		            echo "Documentation: ${GITHUB}/${DISTRO_REPOSITORY}"
		            exit
		            ;;
		        -v | --version)
		            echo "${DISTRO_NAME} launcher, version ${VERSION_NAME}."
		            echo "Copyright (C) 2023-2025 ${AUTHOR} <${GITHUB}>."
		            echo "License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>."
		            echo ""
		            echo "This is free software, you are free to change and redistribute it."
		            echo "There is NO WARRANTY, to the extent permitted by law."
		            exit
		            ;;
		        -*)
		            echo "Unrecognized argument/option '\${1}'."
		            echo "Try '$(basename "${DISTRO_LAUNCHER}") --help' for more information"
		            exit 1
		            ;;
		        *) login_name="\${1}" ;;
		    esac
		    shift
		done

		# Prevent running as root
		if [ "\${EUID}" = "0" ] || [ "\$(id -u)" = "0" ]; then
		    echo "Nope, I can't let you start ${DISTRO_NAME} with root permissions!"
		    echo "This can cause several issues and potentially damage your phone."
		    exit 1
		fi

		# Prevent running within a chroot environment
		pid="\$(grep TracerPid "/proc/\$\$/status" | cut -d \$'\t' -f 2)"
		if [ "\${pid}" != 0 ]; then
		    name="\$(grep Name "/proc/\${pid}/status" | cut -d \$'\t' -f 2)"
		    if [ "\$name" = "proot" ]; then
		        echo "Nope, I can't let you start ${DISTRO_NAME} within a chroot environment!"
		        echo "This can cause performance and other issues."
		        exit 1
		    fi
		fi
		unset pid name

		# Check for login command
		if [ -z "\${distro_command}" ]; then
		    # Prefer su as login command
		    if [ -x "${ROOTFS_DIRECTORY}/bin/su" ]; then
		        distro_command="su --login \${login_name}"
		    elif [ -x "${ROOTFS_DIRECTORY}/bin/login" ]; then
		        distro_command="login \${login_name}"
		    else
		        echo "Couldn't find any login command in the guest rootfs."
		        echo "Use '$(basename "${DISTRO_LAUNCHER}") --command[=COMMAND]'."
		        echo "See '$(basename "${DISTRO_LAUNCHER}") --help' for more information."
		        exit 1
		    fi
		fi

		# unset LD_PRELOAD in case termux-exec is installed
		unset LD_PRELOAD

		# Create directory where proot stores all hard link info
		export PROOT_L2S_DIR="${ROOTFS_DIRECTORY}/.l2s"
		if ! [ -d "\${PROOT_L2S_DIR}" ]; then
		    mkdir -p "\${PROOT_L2S_DIR}"
		fi

		# Create fake /root/.version required by some apps i.e LibreOffice
		if [ ! -f "${ROOTFS_DIRECTORY}/root/.version" ]; then
		    mkdir -p "${ROOTFS_DIRECTORY}/root" && touch "${ROOTFS_DIRECTORY}/root/.version"
		fi

		# Launch command
		launch_command="proot"

		# Correct the size returned from lstat for symbolic links
		launch_command+=" -L"
		launch_command+=" --cwd=/root"
		launch_command+=" --rootfs=${ROOTFS_DIRECTORY}"

		# Turn off proot errors
		# launch_command+=" --verbose=-1"

		# Use termux UID/GID
		if \${use_termux_ids}; then
		    launch_command+=" --change-id=\$(id -u):\$(id -g)"
		elif [ -n "\${custom_ids}" ]; then
		    launch_command+=" --change-id=\${custom_ids}"
		else
		    launch_command+=" --root-id"
		fi

		# Fake hard links using symbolic links
		if ! "\${no_link2symlink}"; then
		    launch_command+=" --link2symlink"
		fi

		# Kill all processes on command exit
		if ! "\${no_kill_on_exit}"; then
		    launch_command+=" --kill-on-exit"
		fi

		# Handle System V IPC syscalls in proot
		if ! "\${no_sysvipc}"; then
		    launch_command+=" --sysvipc"
		fi

		# Make current kernel appear as kernel release
		launch_command+=" --kernel-release=\${kernel_release}"

		# Core file systems that should always be present.
		launch_command+=" --bind=/dev"
		launch_command+=" --bind=/dev/urandom:/dev/random"
		launch_command+=" --bind=/proc"
		launch_command+=" --bind=/proc/self/fd:/dev/fd"
		launch_command+=" --bind=/proc/self/fd/0:/dev/stdin"
		launch_command+=" --bind=/proc/self/fd/1:/dev/stdout"
		launch_command+=" --bind=/proc/self/fd/2:/dev/stderr"
		launch_command+=" --bind=/sys"

		# Fake /proc/loadavg if necessary
		if ! [ -r /proc/loadavg ]; then
		    launch_command+=" --bind=${ROOTFS_DIRECTORY}/proc/.loadavg:/proc/loadavg"
		fi

		# Fake /proc/stat if necessary
		if ! [ -r /proc/stat ]; then
		    launch_command+=" --bind=${ROOTFS_DIRECTORY}/proc/.stat:/proc/stat"
		fi

		# Fake /proc/uptime if necessary
		if ! [ -r /proc/uptime ]; then
		    launch_command+=" --bind=${ROOTFS_DIRECTORY}/proc/.uptime:/proc/uptime"
		fi

		# Fake /proc/version if necessary
		if ! [ -r /proc/version ]; then
		    launch_command+=" --bind=${ROOTFS_DIRECTORY}/proc/.version:/proc/version"
		fi

		# Fake /proc/vmstat if necessary
		if ! [ -r /proc/vmstat ]; then
		    launch_command+=" --bind=${ROOTFS_DIRECTORY}/proc/.vmstat:/proc/vmstat"
		fi

		# Fake /proc/sys/kernel/cap_last_cap if necessary
		if ! [ -r /proc/sys/kernel/cap_last_cap ]; then
		    launch_command+=" --bind=${ROOTFS_DIRECTORY}/proc/.sysctl_entry_cap_last_cap:/proc/sys/kernel/cap_last_cap"
		fi

		# Bind /tmp to /dev/shm
		launch_command+=" --bind=${ROOTFS_DIRECTORY}/tmp:/dev/shm"
		if [ ! -d "${ROOTFS_DIRECTORY}/tmp" ]; then
		    mkdir -p "${ROOTFS_DIRECTORY}/tmp"
		fi
		chmod 1777 "${ROOTFS_DIRECTORY}/tmp"

		# Add host system specific variables and directories
		if ! "\${isolated_env}"; then
		    for dir in /apex /data/app /data/dalvik-cache /data/misc/apexdata/com.android.art/dalvik-cache /product /system /vendor; do
		        [ ! -d "\${dir}" ] && continue
		        dir_mode="\$(stat --format='%a' "\${dir}")"
		        if [[ \${dir_mode:2} =~ ^[157]$ ]]; then
		            launch_command+=" --bind=\${dir}"
		        fi
		    done
		    unset dir dir_mode

		    # Required by termux-api Android 11
		    if [ -e "/linkerconfig/ld.config.txt" ]; then
		        launch_command+=" --bind=/linkerconfig/ld.config.txt"
		    fi

		    # Used by getprop
		    if [ -f /property_contexts ]; then
		        launch_command+=" --bind=/property_contexts"
		    fi

		    launch_command+=" --bind=/data/data/com.termux/cache"
		    launch_command+=" --bind=${TERMUX_FILES_DIR}/home"
		    launch_command+=" --bind=${TERMUX_FILES_DIR}/usr"

		    if [ -d "${TERMUX_FILES_DIR}/apps" ]; then
		        launch_command+=" --bind=${TERMUX_FILES_DIR}/apps"
		    fi
		    if [ -r /storage ]; then
		        launch_command+=" --bind=/storage"
		        launch_command+=" --bind=/storage/emulated/0:/sdcard"
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
		            launch_command+=" --bind=\${storage_path}:/sdcard"
		            launch_command+=" --bind=\${storage_path}:/storage/emulated/0"
		            launch_command+=" --bind=\${storage_path}:/storage/self/primary"
		        fi
		        unset storage_path
		    fi

		    if [ -n "\${EXTERNAL_STORAGE}" ]; then
		        launch_command+=" --bind=\${EXTERNAL_STORAGE}"
		    fi
		fi

		# Bind the tmp folder of the host system to the guest system (ignores --isolated)
		if \${share_tmp_dir}; then
		    launch_command+=" --bind=\${TMPDIR:-${TERMUX_FILES_DIR}/usr/tmp}:/tmp"
		fi

		# Bind custom directories
		launch_command+="\${custom_bindings}"

		# Modify bindings to protected ports to use a higher port number.
		if \${protect_ports}; then
		    launch_command+=" -p"
		fi

		# Setup the default environment
		launch_command+=" /bin/env -i HOME=/root LANG=C.UTF-8 TERM=\${TERM:-xterm-256color} PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/games:/usr/local/bin:/usr/local/sbin:/usr/local/games:/system/bin:/system/xbin"

		# Kill all running pulseaudio servers
		if [ -x "\$(command -v killall)" ]; then
		    killall -qw -9 pulseaudio || true
		fi

		# Enable audio support in distro (for root users, add option '--system')
		pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1

		# Execute launch command (exec replaces current shell)
		exec \${launch_command} \${distro_command}
	EOF
	if ln -sfT "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}" &>>"${LOG_FILE}" && termux-fix-shebang "${DISTRO_LAUNCHER}" &>>"${LOG_FILE}" && chmod 700 "${DISTRO_LAUNCHER}" &>>"${LOG_FILE}"; then
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
	mkdir -p "${ROOTFS_DIRECTORY}/usr/local/bin" &>>"${LOG_FILE}" && cat >"${vnc_launcher}" 2>>"${LOG_FILE}" <<-EOF
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
		        echo "Abort."
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
		    echo "Start vnc session."
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
	if chmod 700 "${vnc_launcher}" &>>"${LOG_FILE}"; then
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
	for config in fake_proc_setup android_ids_setup settings_configurations environment_variables_setup; do
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
			[ -f "${ROOTFS_DIRECTORY}/etc/passwd" ] && local default_shell="$(grep root "${ROOTFS_DIRECTORY}/etc/passwd" | cut -d: -f7)"
			[ -z "${default_shell}" ] && default_shell="unknown"
			ask -n -- -t "Do you want to change the default login shell from '${Y}${default_shell}${C}'?"
		fi
	}; then
		local shells=($(grep '^/bin' "${ROOTFS_DIRECTORY}"/etc/shells 2>>"${LOG_FILE}" | cut -d'/' -f3 2>>"${LOG_FILE}"))
		msg "Installed shells: ${Y}${shells[*]}${C}"
		msg -n "Enter shell name:"
		[ "${default_shell}" = "unknown" ] && default_shell="${shells[0]}"
		read -rep " " -i "$(basename "${default_shell}")" shell
		shell="$(basename "${shell}")"
		if [[ ${shells[*]} == *"${shell}"* ]] && [ -x "${ROOTFS_DIRECTORY}/bin/${shell}" ] && {
			distro_exec /bin/chsh -s "/bin/${shell}" root &>>"${LOG_FILE}"
			if [ "${DEFAULT_LOGIN}" != "root" ]; then
				distro_exec /bin/chsh -s "/bin/${shell}" "${DEFAULT_LOGIN}" &>>"${LOG_FILE}"
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
			[ -z "${default_localtime}" ] && default_localtime="unknown"
			ask -n -- -t "Do you want to change the local time from '${Y}${default_localtime}${C}'?"
		fi
	}; then
		msg -n "Enter time zone (format='Country/City'):"
		[ "${default_localtime}" = "unknown" ] && default_localtime="Etc/UTC"
		read -rep " " -i "${default_localtime}" zone
		if [ -f "${ROOTFS_DIRECTORY}/usr/share/zoneinfo/${zone}" ] && echo "${zone}" >"${ROOTFS_DIRECTORY}/etc/timezone" 2>>"${LOG_FILE}" && distro_exec "/bin/ln" -fs -T "/usr/share/zoneinfo/${zone}" "/etc/localtime" 2>>"${LOG_FILE}"; then
			msg -s "The default time zone is now '${Y}${zone}${G}'."
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
clean_up() {
	if [ -z "${KEEP_ROOTFS_DIRECTORY}" ] && [ -z "${KEEP_ROOTFS_ARCHIVE}" ] && [ -f "${ARCHIVE_NAME}" ]; then
		if ask -n -- -t "Can I remove the downloaded the rootfs archive to save space?"; then
			msg "Okay, removing '!{Y}${ARCHIVE_NAME}${C}'"
			if chmod 777 -R "${ARCHIVE_NAME}" &>>"${LOG_FILE}" && rm -rf "${ARCHIVE_NAME}" &>>"${LOG_FILE}"; then
				msg -s "Done, the rootfs archive is gone!"
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
	msg "If you want to login as another user, add the user name as an argument."
	msg -t "I also think you might need a short form for '${Y}$(basename "${DISTRO_LAUNCHER}")${C}'."
	msg "So have I created '${Y}$(basename "${DISTRO_SHORTCUT}")${C}' which is shorter."
	msg -t "If you have further inquiries, read the documentation at:"
	msg "${B}${U}${GITHUB}/${DISTRO_REPOSITORY}${L}${C}"
}

################################################################################
# Uninstalls the rootfs                                                        #
################################################################################
uninstall_rootfs() {
	if [ -d "${ROOTFS_DIRECTORY}" ] && [ -n "$(ls -AU "${ROOTFS_DIRECTORY}" 2>>"${LOG_FILE}")" ]; then
		msg -at "You are about to uninstall ${DISTRO_NAME} from '${Y}${ROOTFS_DIRECTORY}${C}'."
		msg -ae "This action will delete all files (including valuable ones if any) in this directory!"
		if ask -n0 -- -a "Confirm action."; then
			msg -a "Uninstalling ${DISTRO_NAME}, just a sec."
			if chmod 777 -R "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}" && rm -rf "${ROOTFS_DIRECTORY}" &>>"${LOG_FILE}"; then
				msg -as "Done, ${DISTRO_NAME} uninstalled successfully!"
				msg -a "Removing commands."
				if chmod 777 -R "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}" &>>"${LOG_FILE}" && rm -rf "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}" &>>"${LOG_FILE}"; then
					msg -as "Done, commands removed successfully!"
				else
					msg -ae "Sorry, have I failed to remove:"
					msg -l "${DISTRO_LAUNCHER}" "${DISTRO_SHORTCUT}"
				fi
			else
				msg -aq "Sorry, have I failed to uninstall ${DISTRO_NAME}."
			fi
		else
			msg -a "Uninstallation aborted."
		fi
	else
		msg -a "No rootfs found in '${ROOTFS_DIRECTORY}'."
	fi
}

################################################################################
# Prints the program version information                                       #
################################################################################
print_version() {
	msg -a "${DISTRO_NAME} installer, version ${Y}${VERSION_NAME}${C}."
	msg -a "Copyright (C) 2023-2025 ${AUTHOR} <${B}${U}${GITHUB}${L}${C}>."
	msg -a "License GPLv3+: GNU GPL version 3 or later <${B}${U}https://gnu.org/licenses/gpl.html${L}${C}>."
	msg -aN "This is free software, you are free to change and redistribute it."
	msg -a "There is NO WARRANTY, to the extent permitted by law."
}

################################################################################
# Prints the program usage information                                         #
################################################################################
print_usage() {
	msg -a "Usage: ${Y}${PROGRAM_NAME}${C} [OPTION]... [DIRECTORY]"
	msg -aN "Install ${DISTRO_NAME} in DIRECTORY."
	msg -a "(default='${Y}${DEFAULT_ROOTFS_DIR}${C}')"
	msg -aN "Options:"
	msg -a "  -d, --directory[=PATH]     Change directory to PATH before execution."
	msg -a "      --install-only         Installation only (use with caution)."
	msg -a "      --config-only          Configurations only (if already installed)."
	msg -a "  -u, --uninstall            Uninstall ${DISTRO_NAME}."
	msg -a "      --color[=WHEN]         Enable/Disable color output if supported"
	msg -a "                             (default='${Y}on${C}'). Valid arguments are:"
	msg -a "                             [always|on] or [never|off]"
	msg -a "  -v, --version              Print program version and exit."
	msg -a "  -h, --help                 Print this information and exit."
	msg -a "  -l, --log                  Create log file (${Y}${PROGRAM_NAME%.sh}.log${C})."
	msg -aN "The install directory must be within '${Y}${TERMUX_FILES_DIR}${C}'"
	msg -a "(or its sub-directories) to prevent permission issues."
	msg -aN "Documentation: ${B}${U}${GITHUB}/${DISTRO_REPOSITORY}${L}${C}"
}

################################################################################
# Prepares fake content for certain /proc entries                              #
# Entries are based on values retrieved from Arch Linux (x86_64) running a VM  #
# with 8 CPUs and 8GiB memory (some values edited to fit the distro)           #
# Date: 2023.03.28, Linux 6.2.1                                                #
################################################################################
fake_proc_setup() {
	local status=""
	mkdir -p "${ROOTFS_DIRECTORY}/proc"
	chmod 700 "${ROOTFS_DIRECTORY}/proc"
	if [ ! -f "${ROOTFS_DIRECTORY}/proc/.loadavg" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.loadavg"
			0.12 0.07 0.02 2/165 765
		EOF
	fi
	status+="-${?}"
	if [ ! -f "${ROOTFS_DIRECTORY}/proc/.stat" ]; then
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
	if [ ! -f "${ROOTFS_DIRECTORY}/proc/.uptime" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.uptime"
			5400.0 0.0
		EOF
	fi
	status+="-${?}"
	if [ ! -f "${ROOTFS_DIRECTORY}/proc/.version" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.version"
			Linux version ${KERNEL_RELEASE} (proot@termux) (gcc (GCC) 12.2.1 20230201, GNU ld (GNU Binutils) 2.40) #1 SMP PREEMPT_DYNAMIC Wed, 01 Mar 2023 00:00:00 +0000
		EOF
	fi
	status+="-${?}"
	if [ ! -f "${ROOTFS_DIRECTORY}/proc/.vmstat" ]; then
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
	if [ ! -f "${ROOTFS_DIRECTORY}/proc/.sysctl_entry_cap_last_cap" ]; then
		cat <<-EOF >"${ROOTFS_DIRECTORY}/proc/.sysctl_entry_cap_last_cap"
			40
		EOF
	fi
	status+="-${?}"
	echo -n "${status}"
}

################################################################################
# Writes important environment variables to /etc/environment.                  #
################################################################################
environment_variables_setup() {
	local marker="${PROGRAM_NAME} variables"
	local env_file="${ROOTFS_DIRECTORY}/etc/environment"
	local status=""
	local path="/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games:/system/bin:/system/xbin:${TERMUX_FILES_DIR}/usr/local/bin:${TERMUX_FILES_DIR}/usr/bin"
	sed -i "/^### start\s${marker}\s###$/,/^###\send\s${marker}\s###$/d" "${env_file}"
	sed -i "/^$/d" "${env_file}"
	echo -e "\n### start ${marker} ###\n" >>"${env_file}"
	cat >>"${env_file}" <<-EOF
		# Environment variables
		export PATH="${path}"
		export TERM="${TERM:-xterm-256color}"
		if [ -z "\${LANG}" ]; then
		    export LANG="en_US.UTF-8"
		fi

		# pulseaudio server
		export PULSE_SERVER=127.0.0.1

		# Display (for vnc)
		if [ "\${EUID}" -eq 0 ] || [ "\$(id -u)" -eq 0 ] || [ "\$(whoami)" = "root" ]; then
		    export DISPLAY=:0
		else
		    export DISPLAY=:1
		fi

		# Misc variables
		export MOZ_FAKE_NO_SANDBOX=1
		export TMPDIR="/tmp"
	EOF
	status+="-${?}"
	local java_home
	if [[ "${SYS_ARCH}" == "armhf" ]]; then
		java_home="/usr/lib/jvm/java-[0-9][0-9]-openjdk-armhf"
	else
		java_home="/usr/lib/jvm/java-[0-9][0-9]-openjdk-aarch64"
	fi
	# These don't work well in env_file
	mkdir -p "${ROOTFS_DIRECTORY}/etc/profile.d/"
	cat >"${ROOTFS_DIRECTORY}/etc/profile.d/java.sh" <<-EOF
		# JDK variables
		export JAVA_HOME="\$(echo ${java_home})"
		export PATH="\${PATH}:\${JAVA_HOME}/bin"
	EOF
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
	# 	[ ! -e "${ROOTFS_DIRECTORY}${f}" ] && continue
	# 	sed -i -E "s@\<(PATH=)(\"?[^\"[:space:]]+(\"|\$|\>))@\1\"${path}\"@g" "${ROOTFS_DIRECTORY}${f}"
	# done
	# status+="-${?}"
	unset f
	echo -n "${status}"
}

################################################################################
# Adds android-specific UIDs/GIDs to /etc/group and /etc/gshadow               #
################################################################################
android_ids_setup() {
	local status=""
	chmod u+rw "${ROOTFS_DIRECTORY}/etc/passwd" "${ROOTFS_DIRECTORY}/etc/shadow" "${ROOTFS_DIRECTORY}/etc/group" "${ROOTFS_DIRECTORY}/etc/gshadow" &>>"${LOG_FILE}"
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
settings_configurations() {
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
	fi &>>"${LOG_FILE}"
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
	chmod 777 -R "${resolv_conf}" && rm -f "${resolv_conf}"
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
		--kernel-release="${KERNEL_RELEASE}" \
		--rootfs="${ROOTFS_DIRECTORY}" \
		--link2symlink \
		--kill-on-exit \
		/bin/env -i \
		"HOME=/root" \
		"LANG=C.UTF-8" \
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
		"TERM=${TERM:-xterm-256color}" \
		"TMPDIR=/tmp" \
		"${@}"
}

################################################################################
# Initializes the color variables                                              #
################################################################################
set_colors() {
	if [ -x "$(command -v tput)" ] && [ "$(tput colors)" -ge 8 ] && [[ ${COLOR_SUPPORT} =~ "on"|"always"|"auto" ]]; then
		R="$(echo -e "sgr0\nbold\nsetaf 1" | tput -S)"
		G="$(echo -e "sgr0\nbold\nsetaf 2" | tput -S)"
		Y="$(echo -e "sgr0\nbold\nsetaf 3" | tput -S)"
		B="$(echo -e "sgr0\nbold\nsetaf 4" | tput -S)"
		C="$(echo -e "sgr0\nbold\nsetaf 6" | tput -S)"
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
				prefix="\n${Y}>> "
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
					"Try '${Y}${PROGRAM_NAME} --help${C}' for more information.")
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

# Output for log messages
LOG_FILE="/dev/null"

# Enable color by default
COLOR_SUPPORT=always

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
			optarg="${1//--directory/}"
			optarg="${optarg//=/}"
			if [ "${optarg}" = "-d" ] || [ -z "${optarg}" ]; then
				shift
				optarg="${1}"
			fi
			if [ -z "${optarg}" ]; then
				msg -aqm1 "Option '--directory' requires an argument."
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
			optarg="${1//--color/}"
			optarg="${optarg//=/}"
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
	safety_check
	# For some mesaage customizations
	if ${ACTION_INSTALL}; then
		action="install"
	else
		action=configure
	fi
	clear
	distro_banner # External function
	print_intro
	check_arch
	check_pkgs
	post_check_actions # External function
	msg -t "I shall now ${action} ${DISTRO_NAME} in '${Y}${ROOTFS_DIRECTORY}${C}'."
fi

# Install actions
if ${ACTION_INSTALL}; then
	check_rootfs_directory
	pre_install_actions # External function
	download_rootfs_archive
	verify_rootfs_archive
	extract_rootfs_archive
	post_install_actions # External function
fi

# Create launchers
if ${ACTION_INSTALL} || ${ACTION_CONFIGURE}; then
	create_rootfs_launcher
	create_vnc_launcher
fi

# Post install configurations
if ${ACTION_CONFIGURE}; then
	pre_config_actions # External function
	make_configurations
	post_config_actions # External function
	set_user_shell
	set_zone_info
fi

# Clean up files
if ${ACTION_INSTALL}; then
	clean_up
fi

# Print message for successful completion
if ${ACTION_INSTALL} || ${ACTION_CONFIGURE}; then
	pre_complete_actions # External function
	complete_msg
	post_complete_actions # External function
fi
