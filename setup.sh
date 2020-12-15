#!/bin/bash

mkdir -p data/{work,jupyter}
sudo docker-compose run --rm -v $PWD/data/jupyter:/home/jovyan/.jupyter jupyter jupyter notebook password
