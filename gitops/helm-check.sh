#!/bin/bash

noFail=0
for dir in $(find helm-charts -mindepth 1 -maxdepth 3 -type d | grep -v keycloak)
do
  if ! [ -e $dir/Chart.yaml ]; then continue; fi
  pushd $dir > /dev/null
  echo -n checking helm: $dir
  if (helm lint 2>&1)
  then
    echo -e '\t [ok]'
  else
    noFail=1
    echo -e '\t [ERROR]' 1>&2
  fi
  popd > /dev/null
done
if [ $noFail == 1 ]; then
  exit 1
fi
