#!/bin/bash -e

cd "$(dirname "$0")"/../..

deployMethod="$1"
leaderIp="$2"
numNodes="$3"
RUST_LOG="$4"
[[ -n $deployMethod ]] || exit
[[ -n $leaderIp ]] || exit
[[ -n $numNodes ]] || exit

source net/common.sh
loadConfigFile

threadCount=$(nproc)
if [[ $threadCount -gt 4 ]]; then
  threadCount=4
fi

scripts/install-earlyoom.sh

case $deployMethod in
snap)
  rsync -vPr "$leaderIp:~/solana/solana.snap" .
  sudo snap install solana.snap --devmode --dangerous
  rm solana.snap

  sudo snap set solana "\
      leader-ip=$leaderIp \
      metrics-config=$SOLANA_METRICS_CONFIG \
      rust-log=$RUST_LOG \
    "
  solana_bench_tps=/snap/bin/solana.bench-tps
  ;;
local)
  PATH="$HOME"/.cargo/bin:"$PATH"
  export USE_INSTALL=1
  export RUST_LOG

  rsync -vPr "$leaderIp:~/.cargo/bin/solana*" ~/.cargo/bin/
  solana_bench_tps="multinode-demo/client.sh $leaderIp:~/solana"
  ;;
*)
  echo "Unknown deployment method: $deployMethod"
  exit 1
esac

scripts/oom-monitor.sh  > oom-monitor.log 2>&1 &

while true; do
  echo "=== Client start: $(date)" >> client.log
  clientCommand="$solana_bench_tps --num-nodes $numNodes --loop -s 600 --sustained -t threadCount"
  echo "$ $clientCommand" >> client.log

  $clientCommand >> client.log 2>&1

  $metricsWriteDatapoint "testnet-deploy,name=$netBasename clientexit=1"
  echo Error: bench-tps should never exit | tee -a client.log
done
