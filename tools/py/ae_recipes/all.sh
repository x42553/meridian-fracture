#!/bin/bash
cd "$(dirname "$0")"
python3 style_ae.py && python3 tanks.py && python3 aa.py && python3 arty.py && python3 wheeled.py && python3 inf.py && python3 air.py && python3 ships.py && python3 structs_ae.py && python3 summon.py
