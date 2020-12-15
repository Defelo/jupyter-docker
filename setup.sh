#!/bin/bash

mkdir data work
sudo docker-compose run --rm -v $PWD/data:/home/jovyan/.jupyter jupyter jupyter notebook password
