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

function d() {
  pushd ~/Neuromod\ Devices\ Dropbox/$1
}

function t() {
  d NMDProductTesting/$1
}

function it() {
  d NMDIT/$1
}

function pd() {
  d Product_Development/$1
}
