#!/bin/bash
if [ -d /etc/letsencrypt/live ]; then
cat << EOF
{ "letsencrypt" : { $(
for i in /etc/letsencrypt/live/*; do
  if [ -d $i ]; then
    echo \"$(basename $i)\" : { $(openssl x509 -enddate -noout -in $i/cert.pem | awk -F= '{printf "\"%s\" : \"%s\"",tolower($1),$2}') }
  fi
done | paste -sd',' | sed 's/,/, /'
) } }
EOF
fi