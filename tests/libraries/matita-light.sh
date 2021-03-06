#!/bin/bash

BIN="../../../dkcheck.native -q"
SRC="https://deducteam.github.io/data/libraries/matita.tar.gz"
DIR="matita-light"

# Cleaning command (clean and exit).
if [[ "$#" -eq 1 && ("$1" = "clean" || "$1" = "fullclean") ]]; then
  rm -rf ${DIR}
  if [[ "$1" = "fullclean" ]]; then
    rm -f matita.tar.gz
  fi
  exit 0
fi

# Rejecting other command line arguments.
if [[ "$#" -ne 0 ]]; then
  echo "Invalid argument, usage: $0 [clean | fullclean]"
  exit -1
fi

# Prepare the library if necessary.
if [[ ! -d ${DIR} ]]; then
  # The directory is not ready, so we need to work.
  echo "Preparing the library:"

  # Download the library if necessary.
  if [[ ! -f matita.tar.gz ]]; then
    echo -n "  - downloading...      "
    wget -q ${SRC}
    echo "OK"
  fi

  # Extracting the source files.
  echo -n "  - extracting...       "
  tar xf matita.tar.gz
  mv matita $DIR
  rm $DIR/matita_arithmetics_factorial.dk
  rm $DIR/matita_arithmetics_binomial.dk
  rm $DIR/matita_arithmetics_chebyshev_*.dk
  rm $DIR/matita_arithmetics_chinese_reminder.dk
  rm $DIR/matita_arithmetics_congruence.dk
  rm $DIR/matita_arithmetics_fermat_little_theorem.dk
  rm $DIR/matita_arithmetics_gcd.dk
  rm $DIR/matita_arithmetics_ord.dk
  rm $DIR/matita_arithmetics_primes.dk
  echo "OK"
fi

# Checking the files.
cd ${DIR}
\time -f "Finished in %E at %P with %MKb of RAM" make "DKCHECK=$BIN"
