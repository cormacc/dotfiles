#!/bin/bash
#
# Function to change to an NMD product directory
# To be sourced from profile or wherever

function n() {
  pushd ~/nmd/$1
}

function p() {
  n products/$1
}

function study() {
  n studies/$1
}

function infra() {
  n infrastructure
}

function mb2() {
  p mb2/$1
}

function mbt() {
  p mbt/$1
}
