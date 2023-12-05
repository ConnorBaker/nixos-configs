# NOTE: You *must* specify the agents settings.
{
  services.hercules-ci-agent = {
    enable = true;
    settings.concurrentTasks = 1;
  };
}
