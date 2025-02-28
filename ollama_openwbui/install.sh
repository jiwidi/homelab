#!/bin/bash
set -e

if ! command -v ollama > /dev/null; then
  brew install ollama
fi

if ! command -v ollama > /dev/null; then
  echo "ollama is not installed"
  exit 1
fi

healthcheck() {
  curl localhost:11434 -vvv > /dev/null 2>&1
}

if healthcheck; then
  echo "Ollama is running."
else
  echo "Ollama is not running. Starting in tmux session 'ollama'."
  if ! tmux has-session -t ollama 2>/dev/null; then
    tmux new-session -d -s ollama "ollama serve"
    echo "Started tmux session 'ollama' with 'ollama serve'."
  else
    echo "tmux session 'ollama' already exists."
  fi
  for i in {1..10}; do
    if healthcheck; then
      echo "Ollama started successfully."
      break
    fi
    sleep 2
    if [ $i -eq 10 ]; then
      echo "Ollama failed to start in time."
      exit 1
    fi
  done
fi

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
docker-compose -f "$DIR/docker-compose.yaml" up -d