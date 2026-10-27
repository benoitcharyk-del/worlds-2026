#!/bin/sh
# Change le numero de version du site (force les telephones a recharger la derniere version).
B=$(date +%Y%m%d%H%M%S)
sed -i "s/var BUILD='[0-9]*';/var BUILD='$B';/" index.html
printf '{"build":"%s"}\n' "$B" > version.json
echo "version $B"
