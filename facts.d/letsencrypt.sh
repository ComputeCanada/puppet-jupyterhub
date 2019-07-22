#!/bin/bash
if [ -d /etc/letsencrypt/live ]; then
cat << EOF
{ "letsencrypt" : { $(for i in /etc/letsencrypt/live/*; do
  echo \"$(basename $i)\" : { $(openssl x509 -enddate -noout -in $i/cert.pem | awk -F= '{printf "\"%s\" : \"%s\"",tolower($1),$2}') }
done | paste -sd',' | sed 's/,/, /') } }
EOF
fi