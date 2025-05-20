{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Bypassing for now -- marked insecure per https://github.com/ventoy/Ventoy/issues/3224
    # The issues appear to be academic/principle rather than real/malicious, so reinstate at need
    # by marking as a permitted insecure package
    ventoy
  ];
}
