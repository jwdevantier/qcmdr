# QCmdr
QEMU Commander (qcmdr) is a rewrite of how I manage my QEMU VM configurations for my day job.

## Using
1. Edit `conf.lua` to add/adjust VM configuration entries.
2. Run [htt](https://github.com/jwdevantier/htt) (`htt gen.lua`) to generate the various configuration files.
3. Use `./out/qcmdr` to manage your VMs.

## Features
* Start and stop VMs
    * QCmdr monitors the `qemu` process return code, the PID from the pidfile, and the serial console during start-up to detect success in the shortest possible time.
    * QCmdr attempts a clean shutdown via SSH and will monitor if the process ends. If this fails or a timeout is met, QCmdr will forcibly kill the VM process.
* Synchronize files and directories with Mutagen
    * During start-up and shutdown, QCmdr automatically manages [mutagen](https://mutagen.io) synchronization sessions based on your declarative configuration.
    * Mutagen settings are maintained in a separate directory - no interference with your global setup.
* Use SSH and SCP to communicate with your VM
    * QCmdr provides `ssh` and `scp` commands which ensure the QCmdr SSH configuration file is used.
    * QCmdr uses an entirely separate SSH configuration file - your machine's settings will not interfere adversely with the VM configuration.
    * QCmdr configures SSH to use [connection multiplexing](https://www.cyberciti.biz/faq/linux-unix-reuse-openssh-connection/), meaning subsequent SSH commands run instantaneously.
* Isolated from your global settings
    * Both Mutagen and SSH are configured to use configuration files and data directories separate from the global defaults. This allows QCmdr to tweak the behavior of these tools and avoids harmful interference due to global settings.

## Why did you write it this way?
I've tried writing a similar tool a few times by now - I've written it in Python and Common Lisp, and made prototypes in Go and Zig.

Writing utilities like these includes a lot of busywork, more so if your language is low-level and statically compiled. I see this as I maintain several small utilities to scratch various itches.

I have the benefit of knowing the problem well, by virtue of having done it multiple times. Simply generating naive, repetitive bash code using a [suitable code generator](https://github.com/jwdevantier/htt) means that while this is the most feature-rich version of the tool to date, it's also taken the least time to write.

This took a day and a half, whereas other versions usually took in excess of a week, and often had a more rigid and limited way of configuring the application.

## How do the generated scripts look ?

See [this gist](https://gist.github.com/jwdevantier/5bce76c25586059b3dfd622fe464b1bb).