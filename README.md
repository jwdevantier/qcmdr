# QEMU Commander (qcmdr)

A quick, homebrewn tool to manage VM configurations and file synchronization.

## What it does
* allows managing VM configurations in a configuration file
  * that file is regular lisp code - you can keep it a declarative
    data-structure or write functions to re-use common parts.
* can start/stop and query the status of VM's
  * stop: first tries to poweroff via SSH, but kills the process if necessary
  * start: shows the VM starting, starts file synchronization
  * status: shows status of all/requested VM(s). Will show if process is alive
    and whether the VM responds to SSH connections or not
* declarative file-synchronization
  * uses [Mutagen](https://mutagen.io) for file-synchronization, specify what
    you wish synchronized directly in the configuration. Qcmdr will start the
    synchronization after the VM is started
* tweaked SSH configuration
  * SSH connection multiplexing - re-use established connections for multiple
    sessions - means subsequent ssh calls to a host connect instantly
  * Disables host key checking - SSH will normally refuse to connect if a VM's
    fingerprint changes - this, however, happens when VM's are rebuilt.
* is not impacted by / nor impacts system-wide SSH & mutagen configurations
  * uses its own tweaked SSH configuration and configures SSH and mutagen
    accordingly via wrapper scripts.

## How to use ?
1) Write a configuration file, `qcmdr.lisp`.
   * See `qcmdr.sample.lisp` for inspiration
2) Run `qcmdr` and follow the help for directions, e.g.
   * `qcmdr status` -- see current status of all VMs from config
   * `qcmdr start --vm foo` -- start vm `foo`
   * `qcmdr stop --vm foo`


## Building the binary
QEMU commander can be built as a binary. The `bin/` directory will hold the
`qcmdr` binary itself and any libraries you may need to execute it.

*NOTE*: I have not tested against anything but the [SBCL](https://www.sbcl.org/)
version of common lisp.

### Using SBCL directly
```
sbcl --load build.lisp
```

### Using roswell
```
exec ros run +R -l build.lisp -q
```

## License

SPDX: GPL-3.0-or-later

