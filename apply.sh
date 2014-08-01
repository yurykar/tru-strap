#!/bin/bash

# Usage: init.sh --role webserver --environment prod1 --site a --repouser jimfdavies --reponame provtest-config

VERSION=0.0.1

if [ ${!#} == "--debug" ]
then
  function progress_bar {
  $@
  }
else
  function progress_bar {
    while :;do echo -n .;sleep 1;done &
    $@ > /dev/null
    kill $!; trap 'kill $!' SIGTERM
    echo -e "\e[0;32m done \e[0m"
  }
fi



# Process command line params

function print_version {
  echo $1 $2
}

function print_help {
  echo Heeelp.
}

function set_facter {
  export FACTER_$1=$2
  puppet apply -e "file { '/etc/facter': ensure => directory, mode => 0600 } -> file { '/etc/facter/facts.d': ensure => directory, mode => 0600 } -> file { '/etc/facter/facts.d/$1.txt': ensure => present, mode => 0600, content => '$1=$2' }" --logdest syslog > /dev/null
  echo -n "Facter says $1 is:"
  echo -e "\e[0;32m $(facter $1) \e[0m"
}

function retrieve_facter {
  export FACTER_$1=`facter $1`
  echo -n "Facter says $1 is:"
  echo -e "\e[0;32m $(facter $1) \e[0m"
}

while test -n "$1"; do
  case "$1" in
  --help|-h)
    print_help
    exit 
    ;;
  --version|-v) 
    print_version $PROGNAME $VERSION
    exit
    ;;
  --role|-r)
    set_facter init_role $2
    shift
    ;;
  --environment|-e)
    set_facter init_env $2
    shift
    ;; 
  --debug)
    shift
    ;;

  *)
    echo "Unknown argument: $1"
    print_help
    exit
    ;;
  esac
  shift
done

usagemessage="Error, USAGE: $(basename $0) --role|-r --environment|-e [--help|-h] [--version|-v]"

# Define required parameters.
if [[ "$FACTER_init_role" == "" || "$FACTER_init_env" == "" ]]; then
  echo $usagemessage
  exit 1
fi

retrieve_facter init_reponame
retrieve_facter init_repodir

# Link /etc/puppet to our private repo.
PUPPET_DIR="$FACTER_init_repodir/puppet"
rm -rf /etc/puppet ; ln -s $PUPPET_DIR /etc/puppet
puppet apply -e "file { '/etc/hiera.yaml': ensure => link, target => '/etc/puppet/hiera.yaml' }" > /dev/null

# # Use RVM to select specific Ruby version (2.1+) for use with Librarian-puppet
rvm use ruby

# Install and execute Librarian Puppet
# Create symlink to role specific Puppetfile
rm -f /etc/puppet/Puppetfile ; cat /etc/puppet/Puppetfiles/Puppetfile.base /etc/puppet/Puppetfiles/Puppetfile.$FACTER_init_role > /etc/puppet/Puppetfile
cd $PUPPET_DIR
echo -n "Installing Puppet modules"
progress_bar librarian-puppet install --verbose
echo -n "Updating Puppet modules"
progress_bar librarian-puppet update --verbose
librarian-puppet show

# # Use RVM to revert Ruby version to back to system default (1.8.7)
rvm --default use system

# Make things happen.
echo ""
echo "Running puppet apply"
puppet apply /etc/puppet/manifests/site.pp
