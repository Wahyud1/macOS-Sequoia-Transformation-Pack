# About Panel / Widget Script (placeholder)
#!/usr/bin/env bash

echo "=============================================="
echo "           About This Linux (Sequoia)"
echo "=============================================="
echo "OS: $(lsb_release -d | cut -f2)"
echo "Kernel: $(uname -r)"
echo "Host: $(hostname)"
echo "CPU: $(lscpu | grep 'Model name' | cut -d ':' -f2)"
echo "RAM: $(free -h | awk '/Mem:/ {print $2}')"
echo "Shell: $SHELL"
echo "=============================================="
echo "Sequoia Transformation Pack — Powered by You"
echo "=============================================="
