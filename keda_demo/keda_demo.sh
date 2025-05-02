#!/usr/bin/env bash

# ascii art demo of http based scaler and KEDA
# requirements: jq, hey, kubecolor, kedify kubectl plugin

set -euo pipefail

trap "kill $(pidof hey) 2>/dev/null; kill -SIGKILL $(pidof watch) 2>/dev/null" EXIT
IP=$(kubectl get -ndefault ingress app -o json | jq --raw-output '.status.loadBalancer.ingress[].ip')

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
function info() {
    echo -e "${italic}${gray}\$ kubectl get deployment -ndefault app${normal}"
    kubecolor --force-colors get deployment -ndefault app
    echo ""
    echo -e "${italic}${gray}\$ kubectl kedify debug so app${normal}"
    queue="$(kubectl kedify debug so app)"
    first_line=$(echo "$queue" | head -n 1)
    second_line=$(echo "$queue" | head -n 2 | tail -n 1)
    echo "${bold}${first_line}${normal}"
    echo "${second_line}"

    echo ""
    draw_graph
    cat /tmp/hey.output
}
export -f info

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

function update_graph() {
    scale=$(kubectl get -ndefault deployment app -o json | jq --raw-output '.status.replicas')
    if [[ "$scale" == "null" ]]; then
        scale=0
    fi
    echo "$scale" >> /tmp/graph
    sed -i '1d' /tmp/graph
}
export -f update_graph

function run_benchmark() {
    echo "${bold}${blue} ❄ cold-start${white}${normal}" >> /tmp/hey.output
    sleep 3
    sed '$d' -i /tmp/hey.output
    echo "${blue} ❄ cold-start${white}" >> /tmp/hey.output
    
    echo "${bold}${red} 🔥warming up the application${white}${normal}" >> /tmp/hey.output
    curl --connect-timeout 5 --max-time 5 -H "host: app.com" http://${IP} > /dev/null 2>&1
    sed '$d' -i /tmp/hey.output
    echo "${red} 🔥warming up the application${white}" >> /tmp/hey.output
    
    echo "${bold}${green} ⚙ app is ready for traffic${white}${normal}" >> /tmp/hey.output
    sleep 3
    sed '$d' -i /tmp/hey.output
    echo "${green} ⚙ app is ready for traffic${white}" >> /tmp/hey.output
    
    echo "${bold}${yellow} ↗ running benchmark${white}${normal}" >> /tmp/hey.output
    echo "${white}   ~5 req/sec for 10s${white}" >> /tmp/hey.output
    hey -z 10s -c 5 -q 1 -host app.com http://${IP} > /dev/null
    sed '$d' -i /tmp/hey.output
    echo "${gray}   ~5 req/sec for 10s${white}" >> /tmp/hey.output
    
    echo "  ~50 req/sec for 35s" >> /tmp/hey.output
    hey -z 35s -c 50 -q 1 -host app.com http://${IP} > /dev/null
    sed '$d' -i /tmp/hey.output
    echo "${gray}  ~50 req/sec for 35s${white}" >> /tmp/hey.output
    
    echo "   ~1 req/sec for 15s" >> /tmp/hey.output
    hey -z 15s -c 1 -q 1 -host app.com http://${IP} > /dev/null
    sed '$d' -i /tmp/hey.output
    echo "${gray}   ~1 req/sec for 15s${white}" >> /tmp/hey.output
    
    sed '$d' -i /tmp/hey.output
    sed '$d' -i /tmp/hey.output
    sed '$d' -i /tmp/hey.output
    sed '$d' -i /tmp/hey.output
    echo "${yellow} ↗ running benchmark${white}" >> /tmp/hey.output
    echo "${gray}   ~5 req/sec for 10s${white}" >> /tmp/hey.output
    echo "${gray}  ~50 req/sec for 35s${white}" >> /tmp/hey.output
    echo "${gray}   ~1 req/sec for 15s${white}" >> /tmp/hey.output
    
    echo "${bold}${yellow} ↘ stopping traffic${white}${normal}" >> /tmp/hey.output
    while true; do
        val=$(kubectl kedify debug so app -ndefault -ojson | jq --raw-output '.[0].triggers[0].value')
        if [[ $val == "0" ]]; then
            break;
        fi
        sleep 1
    done
    sed '$d' -i /tmp/hey.output
    echo "${yellow} ↘ stopping traffic${white}" >> /tmp/hey.output
    echo "${bold} ✓ ctrl+c to exit${normal}" >> /tmp/hey.output
}

# clear the terminal page
clear

# run the grap update function in the background
echo "" > /tmp/graph
for i in $(seq 1 $graph_width); do
    echo "0" >> /tmp/graph
done
( while true; do update_graph; sleep 1; done )&

# warm up the application
echo "" > /tmp/hey.output
info
read -p "Press enter to continue"

# run the benchmark function in the background
( run_benchmark )&

# run the watch loop
watch --no-title -n1 --color -x bash -c "info"
