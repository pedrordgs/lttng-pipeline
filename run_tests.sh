#!/bin/bash

LOGS_DIR="final_test_results/ansible_logs"

mkdir -p $LOGS_DIR

RUNS=3

# --------

function reset_kube_cluster {
    ansible-playbook -u gsd -i hosts.ini reset-site.yaml
}

function setup_kube_cluster {
    # reset kubernetes cluster
    reset_kube_cluster

    # create kubernetes cluster
    ansible-playbook -u gsd -i hosts.ini playbook.yml

    # prepare setup
    ansible-playbook -u gsd -i hosts.ini dio_playbook.yml --tags prepare_setup
}

function mount_dio_pipeline {
    # destroy previous dio pipeline
    ansible-playbook -u gsd -i hosts.ini dio_playbook.yml --tags delete_dio -e run_all=true

    # create new dio pipeline
    ansible-playbook -u gsd -i hosts.ini dio_playbook.yml --tags deploy_dio -e run_all=true
}

# --------

function vanilla {
    mkdir -p $LOGS_DIR/vanilla/
    reset_kube_cluster

    for ((i=1; i <= $RUNS; i++)); do
        echo "Filebench - Vanilla - Run $i"
        ansible-playbook -u gsd filebench_playbook.yml  --tags vanilla -e run_number="$i" | tee "$LOGS_DIR/vanilla/t00_vanilla_$i.txt" ;
    done
}

# ------------

function lttng_overhead {
    mkdir -p $LOGS_DIR/lttng_overhead/
    setup_kube_cluster

    for ((i=1; i <= $RUNS; i++)); do
        echo "Filebench - LTTng overhead - fs separated analysis - Run $i"
        ansible-playbook -u gsd -i hosts.ini filebench_playbook.yml --tags lttng_overhead_fs_post_analysis -e run_number="$i" | tee "$LOGS_DIR/lttng_overhead/t01_fs_post_analysis-"$i".txt" ;
    done

    for ((i=1; i <= $RUNS; i++)); do
        echo "Filebench - LTTng overhead - live separated analysis - Run $i"
        ansible-playbook -u gsd -i hosts.ini filebench_playbook.yml --tags lttng_overhead_live_post_analysis -e run_number="$i" | tee "$LOGS_DIR/lttng_overhead/t02_live_post_analysis-"$i".txt" ;
    done
}

function babeltrace_overhead {
    mkdir -p $LOGS_DIR/babeltrace_overhead/
    setup_kube_cluster

    for ((i=1; i <= $RUNS; i++)); do
        echo "Filebench - babeltrace2 overhead - write to stdout - Run $i"
        mount_dio_pipeline
        ansible-playbook -u gsd -i hosts.ini filebench_playbook.yml --tags babeltrace_overhead_stdout -e run_number="$i" | tee "$LOGS_DIR/babeltrace_overhead/t01_stdout-"$i".txt" ;
    done

    for ((i=1; i <= $RUNS; i++)); do
        echo "Filebench - babeltrace2 overhead - write to /dev/null - Run $i"
        mount_dio_pipeline
        ansible-playbook -u gsd -i hosts.ini filebench_playbook.yml --tags babeltrace_overhead_discard -e run_number="$i" | tee "$LOGS_DIR/babeltrace_overhead/t02_discard-"$i".txt" ;
    done
}

function elastic_overhead {
    mkdir -p $LOGS_DIR/elastic_overhead/
    setup_kube_cluster

    for ((i=1; i <= $RUNS; i++)); do
        echo "Filebench - elastic plugin overhead - write to /dev/null - Run $i"
        ansible-playbook -u gsd -i hosts.ini filebench_playbook.yml --tags elastic_overhead_discard -e run_number="$i" | tee "$LOGS_DIR/elastic_overhead/t01_discard-"$i".txt" ;
    done

    for ((i=1; i <= $RUNS; i++)); do
        echo "Filebench - elastic plugin overhead - send to elastic search- Run $i"
        mount_dio_pipeline
        ansible-playbook -u gsd -i hosts.ini filebench_playbook.yml --tags elastic_overhead_elk -e run_number="$i" | tee "$LOGS_DIR/elastic_overhead/t02_elk-"$i".txt" ;
    done
}

function analysis_overhead {
    babeltrace_overhead
    elastic_overhead
}

function all {
    lttng_overhead
    analysis_overhead
}

"$@"