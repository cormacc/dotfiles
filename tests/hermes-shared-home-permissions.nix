{ config, pkgs }:

let
  package = config.services.hermes-agent.package;
  code = "${package.hermesVenv}/${package.python.sitePackages}";
in
pkgs.runCommand "hermes-shared-home-permissions" { } ''
  ${package.python}/bin/python3 ${./hermes-shared-home-permissions.py} ${code} -v
  touch "$out"
''
