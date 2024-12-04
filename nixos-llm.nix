{ config, lib, pkgs, modulesPath, ... }:

{
  services = {
    # Enabling open-webui services kicks off a ridiculously long-running build
    # Run via docker instead
    # open-webui = {
    #   enable = true;
    #   environment = {
    #     OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
    #     WEBUI_AUTH = "False";
    #   };
    #   port = 1111;
    # };
    # Probably want to enable ollama or llama-cpp -- not both?
    # ollama.enable = true;
    # llama-cpp restricted to one model, but maybe more performant?
    # lamma-cpp = {
    #   enable = true;
    #   extraFlags = [
    #   ];
    # };
  };

  environment.systemPackages = with pkgs; [
    llama-cpp
    ollama
  ];
}