#!/bin/bash

targetDir="/opt/sendinel"
configureAsterisk=true
configureLighttpd=true
installInitScripts=true
user='sendinel'
group='sendinel'
requiredPackages='asterisk asterisk-dev festival lighttpd sudo build-essential python-flup python-setuptools wget' # wget only for django install
#requiredPythonPackages='Django python-daemon==1.5.5 lockfile'
requiredPythonPackages='Django-1.2.tar.gz lockfile-0.8.tar.gz python-daemon-1.5.5.tar.gz'
#easyInstallArguments='-i http://pypi.python.jp'
tempDir="/tmp"

# targetDir="./installTest"

sourceDir=$(readlink -f "$0")
sourceDir=$(dirname "$sourceDir")
packageDir="$sourceDir/packages"
installLog="$sourceDir/install.log"
targetParentDir="$(dirname $targetDir)"
# timestamp in form 2010-05-03-16-27-15
timestamp=$(date +%F-%k-%M-%S)
pythonBin=$(which python)

error() {
    echo -e "ERROR: $errorMessage$1"
    echo "Sendinel installation aborted."
    exit 1
}

warning() {
    message="$errorMessage"
    if [ "$1" != "" ]; then
        message="$1"
    fi
    if [ "$message" == "" ]; then
        message="An error ocurred. Look for messages above."
    fi
    
    echo -e "WARNING: $message"
    read -p "Do you want to continue anyway - this may not work? (y/n)"
    if [ "$REPLY" != "y" ]; then
        echo "Sendinel installation aborted."
        exit 1
    fi
    echo "Sendinel installation continued despite warning."
}

general_warning() {
    warning "An error ocurred. Look for messages above."
}

debug() {
    echo "$1" >> $installLog
}

message_done() {
    echo -e "done"
    echo "-----------------------"
}

backup_file() {
    file="$1"
    if [ ! -e "$file" ]; then
        return 0
    fi
    backupFile="$file.sendinel-backup-$timestamp"
    debug "Backing up file $file to $backupFile"
    errorMessage='File backup failed.'
    cp -a "$file" "$backupFile" || warning
}

check_file_exists_and_backup() {
    # test wether file already exists - if yes do a backup
    file="$1"
    if [ -e "$file" ]; then
        errorMessage="Configuration file already exists: '$file'. A backup file will be created if you choose to proceed."
        warning
        backup_file "$file"
        return 0
    fi
    return 1
}

remove_or_warning() {
    file="$1"
    errorMessage="The following file could not be removed: '$file'"
    rm "$file" || warning
}

symlink_or_warning() {
    source="$1"
    target="$2"
    if check_file_exists_and_backup "$source"; then
        remove_or_warning "$source"
    fi

    errorMessage="Failed to create symlink from '$source' to '$target'"
    ln -sfv "$target" "$source" || warning
}

copy_file() {
    src="$1"
    dst="$2"
    cp -av "$src" "$dst" >> $installLog || warning "Failed to copy file '$src' to '$dst'."
}

replace_in_file() {
    file="$1"
    searchFor="$2"
    replaceWith=$(echo "$3" | sed -e 's/\(\.\|\/\|\*\|\[\|\]\|\\\)/\\&/g')
    sed -i "s/$searchFor/$replaceWith/g" "$file" || warning 
}

download_extract_and_cd_to_targz() {
    url="$1"
    subDirectory="$2"
    tempFile=$(mktemp "$tempDir/sendinel-install-temp-XXXXXXXXXXXX")
    
    wget --no-verbose -O "$tempFile" "$url" || warning "The download and extraction of $url failed. See above for errors."
    extract_and_cd_to_targz "$tempFile" "$subDirectory"
    rm $tempFile || warning
}
extract_and_cd_to_targz() {
    archiveFile="$1"
    subDirectory="$2"
    
    extractionTempDir=$(mktemp -d "$tempDir/sendinel-install-extr-XXXXXXXXXXXX" || warning)
    extractionOldPwd="$(pwd)"
    
    errorMessage="The download and extraction of $url failed. See above for errors."
    
    tar xzf "$archiveFile" -C "$extractionTempDir" || warning

    extractionDir="$extractionTempDir/$subDirectory"

    cd "$extractionDir" || warning "Could not cd to directory '$extractionDir'. You may manually install $url."
}


cleanup_extraction() {
    cd "$extractionOldPwd" && \
    rm -r "$extractionTempDir" || echo "Clean up of temporary directory $extractionTempDir failed. This hopefully does not affect the sendinel installation."
}

# TODO check /etc/debian_version
echo "-------------------------------------"
echo "Welcome to the sendinel installation!"
echo "-------------------------------------"

# test wether target dir already exists
if [ -e "$targetDir" ]; then
    errorMessage="Installation target directory already exists: '$targetDir'"
    errorMessage="$errorMessage\n\tWe don't want to possibly overwrite existing files."
    warning
fi


# test wether we have write permissions to parent of target dir
if  test ! -w "$targetParentDir"; then
    errorMessage="Your user doesn't have write permissions on $targetParentDir. "
    errorMessage="$errorMessage\n\tRun $0 as root: sudo $0"
    error
fi

# package installs
# TODO supress asterisk country code question
echo "Installing required packages: $requiredPackages... this may take a while..."
errorMessage='Installing required packages failed. You may manually install them.'
apt-get -qq update || warning
DEBIAN_FRONTEND='noninteractive' apt-get -o Dpkg::Options::='--force-confnew' -y -qq -y install $requiredPackages || warning
message_done


# check python version
python -c 'import sys; exit( not (sys.version_info >= (2,4) and sys.version_info < (2,7)))' \
        || warning "Sendinel was tested with Python 2.5 and 2.6. Other versions may not work."

# python package installs
echo "Installing required python packages: $requiredPythonPackages"
errorMessage='Installing required python packages failed. You may manually install them.'
#easy_install -q $easyInstallArguments $requiredPythonPackages || warning
# install local packages
for package in $requiredPythonPackages; do
    easy_install "$packageDir/$package" || warning
done
message_done

# determine django directory
djangoDir=$("$pythonBin" -c 'import django; print django.__path__[0]')

# sendinel user and group
echo "Creating user '$user' and group '$group'..."

errorMessage="Group '$group' could not be created. Look for errors above."
groupadd "$group" || warning

errorMessage="User '$user' could not be created. Look for errors above."
useradd -N -G "$group,asterisk" $user || warning
message_done




echo "Copying files to $targetDir... "
mkdir -p "$targetDir/sendinel"
if [ "$?" -ne "0" ]; then
    errorMessage="Creating directory '$targetDir/sendinel' failed. Look for errors above."
    error
fi

errorMessage="Copying files failed. Look for errors above."
cp -a "$sourceDir/sendinel" "$sourceDir/configs" "$targetDir/" >> $installLog || error
message_done


echo "Installing sendinel configuration..."
localSettingsSrc="$sourceDir/configs/sendinel/local_settings.py"
localSettings="$targetDir/sendinel/local_settings.py"
if [ -e "$localSettings" ]; then
    echo "$localSettings already exists - not replacing your configuration file."
else
    copy_file "$localSettingsSrc" "$localSettings"
fi
message_done

echo "Setting permissions for sendinel..."
chown -R "$user:$group" "$targetDir" || error
message_done

echo "Setting up database and installing example data..."
cd "$targetDir/sendinel" && \
    su "$user" -c "$pythonBin manage.py syncdb -v0" && \
    su "$user" -c "$pythonBin manage.py loaddata backend" || warning
message_done




# sudo
# TODO check wether sudoers already contains sendinel line
# TODO fix python path
echo "Configuring permissions for phone authentication in /etc/sudoers..."
sudoersFile="/etc/sudoers"
backup_file "$sudoersFile"
sudoLine="asterisk      ALL = ($user)NOPASSWD: /usr/bin/python $targetDir/sendinel/asterisk/log_call.py"

errorMessage='Writing the sudoers file failed. You can try to add the following line manually using visudo:'
errorMessage="$errorMessage\n$sudoLine"
echo -e "\n\n#This line was added by the sendinel install script." >> $sudoersFile && \
echo "$sudoLine" >> $sudoersFile || warning "$errorMessage"
message_done


# asterisk config
asteriskDir="/etc/asterisk"
echo "Configuring Asterisk telephony server..."
asteriskConfigsDir="$targetDir/configs/asterisk"

# replace extensions.conf
extensionsTarget="$asteriskDir/extensions.conf"
backup_file "$extensionsTarget"
errorMessage="Failed to replace asterisk configuration file '$extensionsTarget'"
copy_file "$asteriskConfigsDir/extensions.conf" "$extensionsTarget"

# copy datacard.conf
dataCardTarget="$asteriskDir/datacard.conf"
backup_file "$dataCardTarget"
errorMessage="Failed to install asterisk configuration file '$dataCardTarget'"
copy_file "$asteriskConfigsDir/datacard.conf" "$dataCardTarget"


# call_log agi script symlink
agiFileName="call_log.agi"
agiLinkSource="/usr/share/asterisk/agi-bin"
agiLinkTarget="$asteriskConfigsDir/$agiFileName"

mkdir -p "$agiLinkSource" || general_warning
symlink_or_warning "$agiLinkSource/$agiFileName" "$agiLinkTarget"


backup_file "$agiLinkTarget"
replace_in_file "$agiLinkTarget" '%targetDir%' "$targetDir" 
replace_in_file "$agiLinkTarget" '%user%' "$user"
message_done




# asterisk permissions
# TODO warning about security issues - /var/spool/asterisk/outgoing 
# /var/spool/asterisk/outgoing 770
outgoingDir="/var/spool/asterisk/outgoing"
permissions="770"
echo "Setting permissions of '$outgoingDir' to 770..." 
chmod "$permissions" "$outgoingDir" || warning "failed to set permissions on '$outgoingDir'"
message_done


# download and compile datacard
echo "Downloading and compiling Asterisk chan_datacard module for 3G stick support..."
#url="http://github.com/thomasklingbeil/chan_datacard/tarball/28dffc8a5ed498581ab0421ddca0da322777aec2"
package="$packageDir/thomasklingbeil-chan_datacard-28dffc8.tar.gz"
subDirectory="thomasklingbeil-chan_datacard-28dffc8"
extract_and_cd_to_targz "$package" "$subDirectory"

errorMessage="chan_datacard installation failed. Look for errors above."
make && \
make install || warning

cleanup_extraction
message_done

# restart asterisk
echo "Restarting Asterisk telephony server..."
/etc/init.d/asterisk restart || warning "Failed to start asterisk."
message_done


# lighttpd config
# 
echo "Configuring lighttpd webserver..."
lighttpdDir="/etc/lighttpd"
lighttpdMainConfig="$lighttpdDir/lighttpd.conf"
wwwRoot=$(grep ^server.document-root "$lighttpdMainConfig" | cut -d '"' -f2)
if [ "$wwwRoot" == "" ]; then
    warning "server.document-root could not be found automatically in '$lighttpdMainConfig'. You will have to manually copy configs/www-redirect/index.html to your webserver's document root."
fi

# copy index.html
backup_file "$wwwRoot/index.html"
copy_file "$targetDir/configs/www-redirect/index.html" "$wwwRoot/index.html"

# check for lighttpd/conf-enabled directory
if [ ! -e "$lighttpdDir/conf-enabled" ]; then
    warning "Cannot automatically configure lighttpd since '$lighttpdDir/conf-enabled' could not be found."
fi

lighttpdConfigSrc="$targetDir/configs/lighttpd/conf-enabled/10-sendinel.conf"
lighttpdConfigTarget="$lighttpdDir/conf-enabled/10-sendinel.conf"

backup_file "$lighttpdConfigTarget"
copy_file "$lighttpdConfigSrc" "$lighttpdConfigTarget"
replace_in_file "$lighttpdConfigTarget" "%mediaPath%" "$targetDir/sendinel/media"
replace_in_file "$lighttpdConfigTarget" "%adminMediaPath%" "$djangoDir/contrib/admin/media"
/etc/init.d/lighttpd restart || general_warning
message_done

# install init scripts
echo "Configuring automatic sendinel start on system boot."
initSendinelSrc="$targetDir/configs/init-scripts/sendinel"
initSendinel="/etc/init.d/sendinel"
backup_file "$initSendinel"
copy_file "$initSendinelSrc" "/etc/init.d"
replace_in_file "$initSendinel" "%targetDir%" "$targetDir"
replace_in_file "$initSendinel" "%user%" "$user"
chmod 755 "$initSendinel" || warning
update-rc.d sendinel defaults || warning

initSendinelSchedulerSrc="$targetDir/configs/init-scripts/sendinel-scheduler"
initSendinelScheduler="/etc/init.d/sendinel-scheduler"
backup_file "$initSendinelScheduler"
copy_file "$initSendinelSchedulerSrc" "/etc/init.d"
replace_in_file "$initSendinelScheduler" "%targetDir%" "$targetDir"
replace_in_file "$initSendinelScheduler" "%user%" "$user"
chmod 755 "$initSendinelScheduler" || warning
update-rc.d sendinel-scheduler defaults || warning
message_done


"$targetDir/configs/sendinel/create_initial_settings.sh" "$targetDir/sendinel/local_settings.py"


echo "Starting sendinel services..."
/etc/init.d/sendinel start
/etc/init.d/sendinel-scheduler start
message_done

echo "Congratulations - if you didn't see any error messages, sendinel should be installed and reachable at:"
if eth0_ip=$(ifconfig eth0 | awk '/inet addr/ {split ($2,A,":"); print A[2]}'); then
    echo "http://$eth0_ip/"
    echo "If the address above does not work, you can try the following one(s):"
else
    echo "Your computer seems not to use the default ethernet device eth0. - you may try one of the following addresses:"
fi

for ip in $(ifconfig | awk '/inet addr/ {split ($2,A,":"); print A[2]}'); do 
    # exclude eth0 ip
    if [ "$ip" != "$eth0_ip" ]; then
        echo "http://$ip/"
    fi
done


