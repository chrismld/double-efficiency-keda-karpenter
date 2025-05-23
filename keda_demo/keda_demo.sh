#!/usr/bin/env bash

# ascii art demo of http based scaler and KEDA
# requirements: jq, hey, kubecolor, kedify kubectl plugin

set -euo pipefail

trap 'kill $(jobs -p) 2>/dev/null;' EXIT

# init temporary files
echo "" > /tmp/log
echo "" > /tmp/status
echo "" > /tmp/cmd
echo "" > /tmp/cmd-out

# text formatting options
export blue=$(tput setaf 6)
export white=$(tput setaf 7)
export yellow=$(tput setaf 3)
export green=$(tput setaf 2)
export red=$(tput setaf 1)
export gray=$(tput setaf 8)
export bold=$(tput bold)
export italic=$(tput smso)
export normal=$(tput sgr0)

# width of the graph
export graph_width=40

# display scaling information
function render() {
    cat /tmp/info

    echo ""
    draw_graph

    echo ""
    cat /tmp/status
    cat /tmp/log
    echo ""
    cmd=$(cat /tmp/cmd)
    if [[ -n "$cmd" ]]; then
      echo -n ' $ '"$cmd"
    fi
    cat /tmp/cmd-out | awk '{print "", $0}'
}
export -f render 

function draw_graph() {
    values=()
    while read val; do
        values+=("$val")
    done < /tmp/graph
    echo "${bold}REPLICAS OVER TIME:${normal}"
    echo ""
    for row in $(seq 1 5); do
        x=$(( 6-row ))
        printf "%s" " "
        for col in $(seq 1 $graph_width); do
            if [[ "$x" -le "${values[$col]}" ]]; then
                printf "%s" "█"
            else
                printf "%s" " "
            fi
        done
        echo "│ $x"
    done

    echo " ┌─────────┬─────────┬─────────┬─────────┤ 0"
}
export -f draw_graph

function get_info() {
    echo -e "${italic}${gray}\$ kubectl get deployment -ndefault app${normal}"
    kubecolor --force-colors get deployment -ndefault app
    echo ""
    echo -e "${italic}${gray}\$ kubectl kedify debug so app${normal}"
    queue="$(kubectl kedify debug so app)"
    first_line=$(echo "$queue" | head -n 1)
    second_line=$(echo "$queue" | head -n 2 | tail -n 1)
    echo "${bold}${first_line}${normal}"
    echo "${second_line}"
}
export -f get_info

function update_graph() {
    scale=$(kubectl get -ndefault deployment app -o json | jq --raw-output '.status.replicas')
    if [[ "$scale" == "null" ]]; then
        scale=0
    fi
    echo "$scale" >> /tmp/graph
    sed -i '1d' /tmp/graph
}
export -f update_graph

step_count=0
function next_step() {
    step_count=$((step_count + 1))
    echo "${gray} $step_count. next step: $@ ${normal}" > /tmp/log
    while true; do
        input=$(dd if=/dev/tty bs=1 count=1 2>/dev/null)
        if [[ "$input" == "n" ]]; then
            return
        fi
    done
}
export -f next_step

function run_benchmark() {
    echo "${bold}${blue} ❄ cold-start${white}${normal}" > /tmp/status
    next_step "press 'n' to continue"
    
    echo "${bold}${red} 🔥warming up the application ${white}${normal}" > /tmp/status
    echo "curl -sI http://demo.keda" > /tmp/cmd
    next_step "run curl command"
    script -q /dev/null -c 'curl -sI http://demo.keda' > /tmp/cmd-out 2>&1
    
    echo "${bold}${green} ⚙ app is ready for traffic ${white}${normal}" > /tmp/status
    next_step "benchmark with a small load"
    echo "" > /tmp/cmd-out
    
    echo "${bold}${yellow} ↗ benchmark command ${white}${normal}" > /tmp/status
    echo "hey -c 5 -q 1 http://demo.keda" > /tmp/cmd
    next_step "run the benchmark"
    echo "" > /tmp/cmd-out
    (echo ""; hey -z 1h -c 5 -q 1  http://demo.keda | grep -e 'Requests/sec:' -e 'responses$' | awk '{print $1 " | " substr($0, index($0,$2))}' | column -t -s '|') > /tmp/cmd-out &
    pid=$(pidof hey)
    echo $pid > /tmp/pid
    echo "${bold}${yellow} ↗ running benchmark at 5 req/s ${white}${normal}" > /tmp/status
    next_step "results for benchmark"
    kill -SIGINT $pid > /dev/null 2>&1
    echo "${bold}${yellow} ↗ results for 5 req/s benchmark ${white}${normal}" > /tmp/status
   
    next_step "command for high load benchmark"
    echo "${bold}${yellow} ↗ benchmark command ${white}${normal}" > /tmp/status
    echo "hey -c 50 -q 1 http://demo.keda" > /tmp/cmd 
    echo "" > /tmp/cmd-out
    next_step "run the high load benchmark"
    (echo ""; hey -z 1h -c 50 -q 1 http://demo.keda | grep -e 'Requests/sec:' -e 'responses$' | awk '{print $1 " | " substr($0, index($0,$2))}' | column -t -s '|') > /tmp/cmd-out &
    pid=$(pidof hey)
    echo "${bold}${yellow} ↗ running benchmark at 50 req/s ${white}${normal}" > /tmp/status
    next_step "stopping benchmark"
    kill -SIGINT $pid > /dev/null 2>&1
    
    echo "${bold}${yellow} ↘ stopping traffic${white}${normal}" > /tmp/status
    next_step "wait for scale-in"
    
    while true; do
        val=$(kubectl kedify debug so app -ndefault -ojson | jq --raw-output '.[0].triggers[0].value')
        if [[ $val == "0" ]]; then
            break;
        fi
        sleep 1
    done
    echo "${bold} ✓ ctrl+c to exit${normal}" > /tmp/status
    echo "" > /tmp/cmd
    echo "" > /tmp/cmd-out
    echo "" > /tmp/log
}

# clear the terminal page
clear

# run the grap update function in the background
echo "" > /tmp/graph
for i in $(seq 1 $graph_width); do
    echo "0" >> /tmp/graph
done
( while true; do update_graph; sleep 1; done )&
( while true; do get_info > /tmp/info2; mv /tmp/info2 /tmp/info; sleep 1; done )&

# run the benchmark function in the background
run_benchmark &

# run the watch loop
watch --no-title -n0.1 --color -x bash -c "render"
