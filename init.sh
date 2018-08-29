#!/bin/bash
#Tru-Strap: prepare an instance for a Puppet run

main() {
    set_args
    setup_rhel7_repo
    install_yum_deps
    install_ruby
    set_gemsources "$@"
    configure_global_gemrc
    install_gem_deps
    clone_git_repo
    symlink_puppet_dir
    fetch_puppet_modules
    run_puppet
}

function log_error() {
    echo "###############------Fatal error!------###############"
    caller
    printf "%s\n" "${1}"
    exit 1
}
#trustrap_args="--role $init_role --environment $init_env --repouser $init_repouser --reponame $init_reponame --repobranch $init_repobranch --repoprivkeyfile '/root/.ssh/id_rsa'"

# Parse the commmand line arguments
set_args() {
  hostnamectl set-hostname devvm.moneysupermarket.com
  set_facter init_role publisher
  set_facter init_env ci1-cms
  set_facter init_repouser MSMFG
  set_facter init_reponame msm-provisioning
  set_facter init_repobranch master
  set_facter init_repodir "/opt/msm-provisioning"
}


# Install yum packages if they're not already installed
yum_install() {
  for i in "$@"
  do
    if ! rpm -q ${i} > /dev/null 2>&1; then
      local RESULT=''
      RESULT=$(yum install -y ${i} 2>&1)
      if [[ $? != 0 ]]; then
        log_error "Failed to install yum package: ${i}\nyum returned:\n${RESULT}"
      else
        echo "Installed yum package: ${i}"
      fi
    fi
  done
}

# Install Ruby gems if they're not already installed
gem_install() {
  local RESULT=''
  for i in "$@"
  do
    if [[ ${i} =~ ^.*:.*$ ]];then
      MODULE=$(echo ${i} | cut -d ':' -f 1)
      VERSION=$(echo ${i} | cut -d ':' -f 2)
      if ! gem list -i --local ${MODULE} --version ${VERSION} > /dev/null 2>&1; then
        echo "Installing ${i}"
        RESULT=$(gem install ${i} --no-ri --no-rdoc)
        if [[ $? != 0 ]]; then
          log_error "Failed to install gem: ${i}\ngem returned:\n${RESULT}"
        fi
      fi
    else
      if ! gem list -i --local ${i} > /dev/null 2>&1; then
        echo "Installing ${i}"
        RESULT=$(gem install ${i} --no-ri --no-rdoc)
        if [[ $? != 0 ]]; then
          log_error "Failed to install gem: ${i}\ngem returned:\n${RESULT}"
        fi
      fi
    fi
  done
}

print_version() {
  echo "${1}" "${2}"
}

# Set custom facter facts
set_facter() {
  local key=${1}
  #Note: The name of the evironment variable is not the same as the facter fact.
  local export_key=FACTER_${key}
  local value=${2}
  export ${export_key}="${value}"
  if [[ ! -d /etc/facter ]]; then
    mkdir -p /etc/facter/facts.d || log_error "Failed to create /etc/facter/facts.d"
  fi
  if ! echo "${key}=${value}" > /etc/facter/facts.d/"${key}".txt; then
    log_error "Failed to create /etc/facter/facts.d/${key}.txt"
  fi
  chmod -R 600 /etc/facter || log_error "Failed to set permissions on /etc/facter"
  cat /etc/facter/facts.d/"${key}".txt || log_error "Failed to create ${key}.txt"
}

setup_rhel7_repo() {
  yum_install redhat-lsb-core
  dist=$(lsb_release -is)
  majorversion=$(lsb_release -rs | cut -f1 -d.)
  if [[ "$majorversion" == "7" ]] && [[ "$dist" == "RedHatEnterpriseServer" ]]; then
    echo "RedHat Enterprise version 7- adding extra repo for *-devel"
    yum_install yum-utils
    yum-config-manager --enable rhui-REGION-rhel-server-optional || log_error "Failed to run yum-config-manager"
  fi

}

install_ruby() {
  majorversion=$(lsb_release -rs | cut -f1 -d.)
  ruby_v="2.1.5"
  ruby -v  > /dev/null 2>&1
  if [[ $? -ne 0 ]] || [[ $(ruby -v | awk '{print $2}' | cut -d 'p' -f 1) != $ruby_v ]]; then
    yum remove -y ruby-* || log_error "Failed to remove old ruby"
    yum_install https://s3-eu-west-1.amazonaws.com/msm-public-repo/ruby/ruby-2.1.5-2.el${majorversion}.x86_64.rpm
  fi
}

# Set custom gem sources
set_gemsources() {
  GEM_SOURCES=
  tmp_sources=false
  for i in "$@"; do
    if [[ "${tmp_sources}" == "true" ]]; then
      GEM_SOURCES="${i}"
      break
      tmp_sources=false
    fi
    if [[ "${i}" == "--gemsources" ]]; then
      tmp_sources=true
    fi
  done

  if [[ ! -z "${GEM_SOURCES}" ]]; then
    echo "Re-configuring gem sources"
    # Remove the old sources
    OLD_GEM_SOURCES=$(gem sources --list | tail -n+3 | tr '\n' ' ')
    for i in $OLD_GEM_SOURCES; do
      gem sources -r "$i" || log_error "Failed to remove gem source ${i}"
    done

    # Add the replacement sources
    local NO_SUCCESS=1
    OIFS=$IFS && IFS=','
    for i in $GEM_SOURCES; do
      MAX_RETRIES=5
      export attempts=1
      exit_code=1
      while [[ $exit_code -ne 0 ]] && [[ $attempts -le ${MAX_RETRIES} ]]; do
        gem sources -a $i
        exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
          sleep_time=$((attempts * 10))
          echo Sleeping for ${sleep_time}s before retrying ${attempts}/${MAX_RETRIES}
          sleep ${sleep_time}s
          attempts=$((attempts + 1))
        else
          NO_SUCCESS=0
        fi
      done
    done
    IFS=$OIFS
    if [[ $NO_SUCCESS == 1 ]]; then
      log_error "All gem sources failed to add"
    fi
  fi
}

# Install the yum dependencies
install_yum_deps() {
  echo "Installing required yum packages"
  yum_install augeas-devel ncurses-devel gcc gcc-c++ curl git redhat-lsb-core
}

# Install the gem dependencies
install_gem_deps() {
  echo "Installing puppet and related gems"
  gem_install unversioned_gem_manifest:1.0.0
  # Default in /tmp may be unreadable for systems that overmount /tmp (AEM)
  export RUBYGEMS_UNVERSIONED_MANIFEST=/var/log/unversioned_gems.yaml  
  gem_install puppet:3.8.7 hiera facter 'ruby-augeas:~>0.5' 'hiera-eyaml:~>2.1' 'ruby-shadow:~>2.5' facter_ipaddress_primary:1.1.0

  # Configure facter_ipaddress_primary so it works outside this script.
  # i.e Users logging in interactively can run puppet apply successfully
  echo 'export FACTERLIB="${FACTERLIB}:$(ipaddress_primary_path)"'>/etc/profile.d/ipaddress_primary.sh
  chmod 0755 /etc/profile.d/ipaddress_primary.sh
}

# Clone the git repo
clone_git_repo() {
  # Clone private repo.
  echo "Cloning ${FACTER_init_repouser}/${FACTER_init_reponame} repo"
  rm -rf "${FACTER_init_repodir}"
  # Exit if the clone fails
  if ! git clone --depth=1 -b "${FACTER_init_repobranch}" git@github.com:"${FACTER_init_repouser}"/"${FACTER_init_reponame}".git "${FACTER_init_repodir}";
  then
    log_error "Failed to clone git@github.com:${FACTER_init_repouser}/${FACTER_init_reponame}.git"
  fi
}

# Symlink the cloned git repo to the usual location for Puppet to run
symlink_puppet_dir() {
  local RESULT=''
  # Link /etc/puppet to our private repo.
  PUPPET_DIR="${FACTER_init_repodir}/puppet"
  if [ -e /etc/puppet ]; then
    RESULT=$(rm -rf /etc/puppet);
    if [[ $? != 0 ]]; then
      log_error "Failed to remove /etc/puppet\nrm returned:\n${RESULT}"
    fi
  fi

  RESULT=$(ln -s "${PUPPET_DIR}" /etc/puppet)
  if [[ $? != 0 ]]; then
    log_error "Failed to create symlink from ${PUPPET_DIR}\nln returned:\n${RESULT}"
  fi

  if [ -e /etc/hiera.yaml ]; then
    RESULT=$(rm -f /etc/hiera.yaml)
    if [[ $? != 0 ]]; then
      log_error "Failed to remove /etc/hiera.yaml\nrm returned:\n${RESULT}"
    fi
  fi

  RESULT=$(ln -s /etc/puppet/hiera.yaml /etc/hiera.yaml)
  if [[ $? != 0 ]]; then
    log_error "Failed to create symlink from /etc/hiera.yaml\nln returned:\n${RESULT}"
  fi
}

run_librarian() {
  echo -n "Running librarian-puppet"
  gem_install activesupport:4.2.6 librarian-puppet:3.0.0
  local RESULT=''
  RESULT=$(librarian-puppet install --verbose)
  if [[ $? != 0 ]]; then
    log_error "librarian-puppet failed.\nThe full output was:\n${RESULT}"
  fi
  librarian-puppet show
}

# Fetch the Puppet modules via the moduleshttpcache or librarian-puppet
fetch_puppet_modules() {
  ENV_BASE_PUPPETFILE="${FACTER_init_env}/Puppetfile.base"
  ENV_ROLE_PUPPETFILE="${FACTER_init_env}/Puppetfile.${FACTER_init_role}"
  BASE_PUPPETFILE=Puppetfile.base
  ROLE_PUPPETFILE=Puppetfile."${FACTER_init_role}"

  # Override ./Puppetfile.base with $ENV/Puppetfile.base if one exists.
  if [[ -f "/etc/puppet/Puppetfiles/${ENV_BASE_PUPPETFILE}" ]]; then
    BASE_PUPPETFILE="${ENV_BASE_PUPPETFILE}"
  fi
  # Override Puppetfile.$ROLE with $ENV/Puppetfile.$ROLE if one exists.
  if [[ -f "/etc/puppet/Puppetfiles/${ENV_ROLE_PUPPETFILE}" ]]; then
    ROLE_PUPPETFILE="${ENV_ROLE_PUPPETFILE}"
  fi

  # Concatenate base, and role specific puppetfiles to produce final module list.
  PUPPETFILE=/etc/puppet/Puppetfile
  rm -f "${PUPPETFILE}" ; cat /etc/puppet/Puppetfiles/"${BASE_PUPPETFILE}" > "${PUPPETFILE}"
  echo "" >> "${PUPPETFILE}"
  cat /etc/puppet/Puppetfiles/"${ROLE_PUPPETFILE}" >> "${PUPPETFILE}"

  PUPPETFILE_MD5SUM=$(md5sum "${PUPPETFILE}" | cut -d " " -f 1)
  if [[ ! -z $PASSWD ]]; then
    MODULE_ARCH=${FACTER_init_role}."${PUPPETFILE_MD5SUM}".tar.aes.gz
  else
    MODULE_ARCH=${FACTER_init_role}."${PUPPETFILE_MD5SUM}".tar.gz
  fi
  echo "Cached puppet module tar ball should be ${MODULE_ARCH}, checking if it exists"
  cd "${PUPPET_DIR}" || log_error "Failed to cd to ${PUPPET_DIR}"

  if [[ ! -z "${FACTER_init_moduleshttpcache}" && "200" == $(curl "${FACTER_init_moduleshttpcache}"/"${MODULE_ARCH}"  --head --silent | head -n 1 | cut -d ' ' -f 2) ]]; then
    echo -n "Downloading pre-packed Puppet modules from cache..."
    if [[ ! -z $PASSWD ]]; then
      package=modules.tar
      echo "================="
      echo "Using Encrypted modules ${FACTER_init_moduleshttpcache}/$MODULE_ARCH "
      echo "================="
      curl --silent ${FACTER_init_moduleshttpcache}/$MODULE_ARCH |
        gzip -cd |
        openssl enc -base64 -aes-128-cbc -d -salt -out $package -k $PASSWD
    else
      package=modules.tar.gz
      curl --silent -o $package ${FACTER_init_moduleshttpcache}/$MODULE_ARCH
    fi


    tar tf $package &> /dev/null
    TEST_TAR=$?
    if [[ $TEST_TAR -eq 0 ]]; then
      tar xpf $package
      echo "================="
      echo "Unpacked modules:"
      puppet module list --color false
      echo "================="
    else
      echo "Seems we failed to decrypt archive file... running librarian-puppet instead"
      run_librarian
    fi

  else
    echo "Nope!"
    run_librarian
  fi
}

# Move root's .gemrc to global location (/etc/gemrc) to standardise all gem environment sources
configure_global_gemrc() {
  if [ -f /root/.gemrc ]; then
    echo "Moving root's .gemrc to global location (/etc/gemrc)"
    mv /root/.gemrc /etc/gemrc
  else
    echo "  Warning: /root/.gemrc did not exist!"
  fi
}

# Execute the Puppet run
run_puppet() {
  export LC_ALL=en_GB.utf8
  echo ""
  echo "Running puppet apply"
  mkdir -p /mnt/ephemeral/
  puppet apply -e "include ::aemdispatcher::dispatcher" -vd

  PUPPET_EXIT=$?

  case $PUPPET_EXIT in
    0 )
      echo "Puppet run succeeded with no failures."
      ;;
    1 )
      log_error "Puppet run failed."
      ;;
    2 )
      echo "Puppet run succeeded, and some resources were changed."
      ;;
    4 )
      log_error "Puppet run succeeded, but some resources failed."
      ;;
    6 )
      log_error "Puppet run succeeded, and included both changes and failures."
      ;;
    * )
      log_error "Puppet run returned unexpected exit code."
      ;;
  esac

}



main "$@"

