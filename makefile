.PHONY: help lint run
.DEFAULT_GOAL := help

help:
	@echo "make lint  : Check the script (ShellCheck)"
	@echo "make test  : Run the tests file"
	@echo "make check : run the lint & the test" 
	@echo "make demo  : Laucnh the script with a file"
	@echo "make run   : Launch the script (Destructive)"

lint:
	shellcheck lubrae.sh

test:
	bash tests/run.sh

check: lint test

demo:
	truncate -s 100M test.img
	./lubrae.sh --file test.img

run:
	sudo ./lubrae.sh
