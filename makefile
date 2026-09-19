.PHONY: help lint run
.DEFAULT_GOAL := help

help:
	@echo "make lint : Check the script (ShellCheck)"
	@echo "make demo : Laucnh the script with a file"
	@echo "make run  : Launch the script (Destructive)"

lint:
	shellcheck lubrae.sh

demo:
	truncate -s 100M test.img
	./lubrae.sh --file test.img

run:
	sudo ./lubrae.sh
