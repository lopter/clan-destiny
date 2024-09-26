{
  imports = [
    # contains your disk format and partitioning configuration.
    ./disko.nix
    # this file is shared among all machines
    ../../modules/shared.nix
  ];

  # This is your user login name.
  users.users.user.name = "kal";

  # Set this for clan commands use ssh i.e. `clan machines update`
  # If you change the hostname, you need to update this line to root@<new-hostname>
  # This only works however if you have avahi running on your admin machine else use IP
  clan.core.networking.targetHost = "root@172.28.53.53";

  # You can get your disk id by running the following command on the installer:
  # Replace <IP> with the IP of the installer printed on the screen or by running the `ip addr` command.
  # ssh root@<IP> lsblk --output NAME,ID-LINK,FSTYPE,SIZE,MOUNTPOINT
  disko.devices.disk.main.device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_mSATA_250GB_S33GNX0H807540M";

  # IMPORTANT! Add your SSH key here
  # e.g. > cat ~/.ssh/id_ed25519.pub
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDHG0HKQxkku9UZCSbaWp+PZPuUKOieefPPo6beNPH0elFVJjrjuwNZ6MUYkbVyWwprwHL6oXklpV48GvM/l3vkD886Pc+VUfGSeDayiRIT1aKGqY0ELKvTr6uZVQDH1Kqa36YmHpaLUcpvs7Y9/XCyeOMX8EGfQvwbZ+DbFxn4oPHxsW7Lt2xR+8HgGFOUaxTK0obLxeOJvplPHFpQacoyNvFcXRVt31GspoSu+KcfYbfH888e+nh01URXU+8h5Jlim+WNjUNxbxzYSIr2zQhzRJxL4ZLH08er+v0p6BDCVxgFINwY6zVTLPmKFt0dd9G8kzSS+v/d3EIUIdfYouqH7uNPSFtJZsLcKHdI7VJQdcXRZGhVgbvUoxxqJKQR1MVvppxmed1z8mzsT7S5GvuweRxSKAgJZo920pWSe5v1D6lT0TifbG6rwFjwsgOGpL6OTvmRsgUZamRfwj4G1LU7F3oaJTsK7wggdiX1qC/oLyEXZaH0f0w3iQb6213RRn+Kp8+AmWnKZ6TwcjLZsMAZLVSkYHD39YmNyq4SFWjk+gk8wMqaLp4oVgDOTch9NeEqKN+k7XFi2JmOz4y+tC8cVOXuKbufYGq6y0H4mlrO7soT3nzAPotOEmJXo43x7g4nyWqZIQOEz5zotr+HdprOc8Ynls76XJ4Hv2Ek3HiiyQ== louis_gpg_auth_key_december_2022_december_2024"
  ];

  # Zerotier needs one controller to accept new nodes. Once accepted
  # the controller can be offline and routing still works.
  clan.core.networking.zerotier.controller.enable = true;
}
