{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  networking.nameservers = [
    "1.1.1.1"
    "1.0.0.1"
    "8.8.8.8"
    "8.8.4.4"
  ];

  # Localization
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

  # Desktop - XFCE
  services.xserver = {
    enable = true;

    displayManager.lightdm.enable = true;

    desktopManager.xfce.enable = true;

    xkb = {
      layout = "us";
      variant = "";
    };
  };

  services.displayManager.defaultSession = "xfce";

  # Printing
  services.printing.enable = true;

  # Audio - PipeWire
  services.pulseaudio.enable = false;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # User
  users.users.and = {
    isNormalUser = true;
    description = "and";

    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # Applications
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
  ];

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true;
    options = "--delete-older-than 15d";
  };

  # NixOS release
  system.stateVersion = "26.05";
}
