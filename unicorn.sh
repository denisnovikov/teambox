#!/bin/bash

case "$1" in 
  '-r' | '--restart') 
    echo Restarting Unicorn:`cat ./tmp/pids/unicorn.pid`...
    sudo -u www-data kill -HUP `cat ./tmp/pids/unicorn.pid`
    echo Restarted. Unicorn:`cat ./tmp/pids/unicorn.pid`
  ;;
  '-s' | '--stop')
    echo Stopping Unicorn:`cat ./tmp/pids/unicorn.pid`...
    sudo -u www-data kill `cat ./tmp/pids/unicorn.pid`
    echo Stopped.
  ;;
  '-a' | '--run')
    echo Starting Unicorn.
    sudo -u www-data bash -c "unicorn_rails -p 3000 -E production -D >> ./log/unicorn.log"
    echo Started. Unicorn:`cat ./tmp/pids/unicorn.pid`
  ;;
  '-d' | '--rundev')
    echo Starting Unicorn in dev mode.
    sudo -u www-data bash -c "unicorn_rails -p 3000 -E development -D >> ./log/unicorn.log"
    echo Started. Unicorn:`cat ./tmp/pids/unicorn.pid`
  ;;
  *)
    echo -r, --restart - restart
    echo -s, --stop - stop
    echo -a, --run - run
    echo -d, --rundev - run in development environment
  ;;
esac
