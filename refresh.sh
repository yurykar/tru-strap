#!/bin/sh
cd /etc/haproxy
ruby generate_config.rb

if [ ! -f haproxy.cfg ]; then
  # no config file at all - must be first run
  mv haproxy.tmp haproxy.cfg
elif diff haproxy.tmp haproxy.cfg >/dev/null ; then
  # files are identical, remove the newly generated file
  rm haproxy.tmp
else
  # files are different, overwrite config with new file and reload haproxy
  echo Discovery made. Restarting haproxy wih new config
  mv haproxy.tmp haproxy.cfg
  service haproxy reload
fi
