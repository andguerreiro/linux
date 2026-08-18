# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ---------------------------------------------------------------------------
  # Boot
  # ---------------------------------------------------------------------------

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ---------------------------------------------------------------------------
  # Networking
  # ---------------------------------------------------------------------------

  networking.hostName = "nixos";

  networking.networkmanager.enable = true;

  # Keep these for now because NetworkManager was not obtaining
  # working DNS settings through DHCP on the previous installation.
  networking.nameservers = [
    "1.1.1.1"
    "1.0.0.1"
    "8.8.8.8"
    "8.8.4.4"
  ];


  # ---------------------------------------------------------------------------
  # Localization
  # ---------------------------------------------------------------------------

  time.timeZone = "America/Sao_Paulo";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };


  # ---------------------------------------------------------------------------
  # Desktop
  # ---------------------------------------------------------------------------

  services.xserver.enable = true;

  services.displayManager.lightdm.enable = true;
  services.desktopManager.xfce.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };


  # ---------------------------------------------------------------------------
  # Printing
  # ---------------------------------------------------------------------------

  services.printing.enable = true;


  # ---------------------------------------------------------------------------
  # Audio
  # ---------------------------------------------------------------------------

  services.pulseaudio.enable = false;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };


  # ---------------------------------------------------------------------------
  # User
  # ---------------------------------------------------------------------------

  users.users."and" = {
    isNormalUser = true;
    description = "and";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };


  # ---------------------------------------------------------------------------
  # Applications
  # ---------------------------------------------------------------------------

  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    # Add applications here as you need them.
    #
    # Example:
    #   vim
    #   wget
  ];


  # ---------------------------------------------------------------------------
  # Automatic updates
  # ---------------------------------------------------------------------------

  # system.autoUpgrade = {
  #   enable = true;
  #   dates = "daily";
  #   persistent = true;
  #   allowReboot = false;
  # };


  # ---------------------------------------------------------------------------
  # Garbage collection
  # ---------------------------------------------------------------------------

  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true;
    options = "--delete-older-than 15d";
  };


  # ---------------------------------------------------------------------------
  # NixOS release
  # ---------------------------------------------------------------------------

  # This value determines the default stateful configuration versions
  # used by NixOS. Do not change it casually when upgrading releases.
  system.stateVersion = "26.05";
}
