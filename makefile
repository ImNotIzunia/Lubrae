.PHONY: help lint run
.DEFAULT_GOAL := help

help:
	@echo "make lint : Check the script (ShellCheck)"
	@echo "make run  : Launch the script (Destructive)"

lint:
	shellcheck lubrae.sh

run:
	sudo ./lubrae.sh
