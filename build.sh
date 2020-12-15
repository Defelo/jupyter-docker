#!/bin/bash

sudo docker pull jupyter/tensorflow-notebook
sudo docker-compose build --force-rm jupyter
