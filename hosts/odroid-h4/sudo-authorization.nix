{ ... }:

{
  # The operator authenticates only in a visible terminal. Approved agent
  # transactions may then use sudo -n from separate SSH sessions for at most
  # five minutes, with explicit sudo -K revocation at every approval boundary.
  security.sudo.extraConfig = ''
    Defaults:cormacc timestamp_type=global
    Defaults:cormacc timestamp_timeout=5
  '';
}
