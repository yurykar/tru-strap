# Tru Strap
## What is this?
This is the MSM Public version of the 'tru-strap' script.  Ref: https://github.com/jimfdavies/tru-strap

We have made this repo public so that we can download and start 'tru-strapping' without needing any credentials.  We will pass required credentials as parameters into tru-strap in order for it to download/clone the required private repo(s).

## How do I use it?
Integrate it with your favourite Virtualisation / Cloud platform eg. AWS User Data, RightScale RightScripts .... or use Vagrant with the handy provided Vagrantfile.

### Vagrant
#### Quick Start
```
git clone git@github.com:MSMFG/tru-strap.git
cd tru-strap
cp ~/.ssh/myprivategithubkey myprivategithubkey.pem
export vm_mem=2048
export init_role=myrole
export init_env=myenv
export init_repoprivkeyfile=myprivategithubkey.pem
vagrant up
```

#### Environment Variables
This Vagrantfile requires a few environment variables to be set.

##### Required
- ```init_role``` The Puppet [role](http://www.slideshare.net/PuppetLabs/roles-talk) of the server.
- ```init_env``` The Puppet environment of the server.
- ```init_repoprivkeyfile``` The filename (.pem extension) of your private GitHub key which should be copied into this directory.

##### Optional
- ```init_repouser``` The owner of the github repo, defaults to _MSMFG_
- ```init_reponame``` The name of the github repo, defaults to _msm-provisioning_
- ```init_repobranch``` The name of the github branch, defaults to _master_
