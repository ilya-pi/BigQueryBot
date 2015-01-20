
# don't usually mess with these
NMPATH ?= ./node_modules/.bin
COFFEE ?= ${NMPATH}/coffee
COFFEE_DEBUG ?= ${COFFEE} --nodejs debug

MAIN=./src/main.coffee

setup:
	npm install .

debug:
	${COFFEE_DEBUG} ${MAIN}

build:
	${COFFEE} -o lib/ -c src/

.PHONY:	setup run
