#!/bin/bash
for file in "dsaparam.pem" "dsa_priv.pem" "dsa_pub.pem"; do
  if [ -e "$file" ]; then
    echo "There's already a $file here! Move it aside or be more careful!"
    exit 1
  fi
done
openssl="/usr/bin/openssl"
$openssl dsaparam 1024 < /dev/urandom > dsaparam.pem
$openssl gendsa dsaparam.pem -out dsa_priv.pem
chmod 0400 dsa_priv.pem
$openssl dsa -in dsa_priv.pem -pubout -out dsa_pub.pem
rm dsaparam.pem
chmod 0444 dsa_pub.pem
echo "
Generated private and public keys: dsa_priv.pem and dsa_pub.pem.
BACK UP YOUR PRIVATE KEY AND KEEP IT SAFE!
If you lose it, your users will be unable to upgrade!"
