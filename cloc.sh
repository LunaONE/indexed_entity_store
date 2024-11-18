#!/bin/bash

docker run --rm -v "$PWD/":/indexed_entity_store:ro aldanial/cloc --fmt=4 /indexed_entity_store/lib 
