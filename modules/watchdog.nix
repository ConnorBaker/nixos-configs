{
  # A hang that stops PID 1 otherwise leaves the host down until someone
  # power-cycles it. Arm the board's hardware watchdog through systemd so such
  # a hang resets the host, and reboot after a kernel panic instead of halting.
  systemd.settings.Manager.RuntimeWatchdogSec = "60s";
  boot.kernel.sysctl."kernel.panic" = 10;
}
