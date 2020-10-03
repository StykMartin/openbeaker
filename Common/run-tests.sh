#!/bin/bash

set -x

env PYTHONPATH=.${PYTHONPATH:+:$PYTHONPATH} nosetests-3 ${*:--v bkr}
